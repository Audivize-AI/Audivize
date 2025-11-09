import Foundation
import Accelerate
import CoreAudio

// MARK: - Feature Extraction

/**
 A Swift equivalent for `python_speech_features`.
 Calculates filterbank features. Provides e.g. fbank and mfcc features for use in ASR applications.
 Author: James Lyons 2012
 Swift Translation: Gemini 2.5 Pro (for FFT only), o4-mini-high, and Benjamin Lee (optimization)
 */
extension ASD {
    class MFCC {
        struct Configuration {
            var samplerate: Int?
            var winlen: Float?
            var winstep: Float?
            var siglen: Float?
            var numcep: Int?
            var nfilt: Int?
            var nfft: Int?
            var lowfreq: Float?
            var highfreq: Float?
            var preemph: Float?
            var ceplifter: Int?
            var appendEnergy: Bool?
            var bufferSize: Int?
            var winfunc: ((Int) -> [Float])?
        }
        
        public let samplerate: Int
        public let winlen: Float
        public let winstep: Float
        public let numcep: Int
        public let nfilt: Int
        public let nfft: Int
        public let lowfreq: Float
        public let highfreq: Float
        public let appendEnergy: Bool
        
        /// The machine epsilon value for Float32.
        private static let LOG0 = log(Float32.ulpOfOne)
        
        private let fb: [Float]
        private let lift: [Float]
        public var audioBuffer: AudioBuffer
        
        init(_ config: Configuration)
        {
            self.samplerate     = config.samplerate ?? 16_000
            self.highfreq       = config.highfreq ?? Float(samplerate) / 2.0
            assert(self.highfreq <= Float(samplerate) / 2, "highfreq is greater than samplerate/2")
            self.lowfreq        = config.lowfreq ?? 0
            self.winlen         = config.winlen ?? 0.025
            self.winstep        = config.winstep ?? 0.010
            self.numcep         = config.numcep ?? 13
            self.nfilt          = MFCC.nextDCTLength(config.nfilt ?? 32)
            self.nfft           = config.nfft ?? MFCC.calculateNfft(samplerate: samplerate, winlen: winlen)
            self.appendEnergy   = config.appendEnergy ?? true
            
            self.audioBuffer = .init(
                sampleRate: samplerate,
                winlen: AudioBuffer.length(from: winlen, with: samplerate),
                winstep: AudioBuffer.length(from: winstep, with: samplerate),
                capacity: config.bufferSize ?? 2048,
                preemph: config.preemph ?? 0.97
            )
            
            self.fb = MFCC.getFilterbanks(nfilt: self.nfilt, nfft: self.nfft, samplerate: self.samplerate, lowfreq: self.lowfreq, highfreq: self.highfreq)
            
            // normalization and lifting constants
            let f0 = sqrtf(1.0 / (Float(nfilt)))         // k=0
            let fk = f0 * sqrtf(2.0)                     // k>0
            var scalars = [Float](repeating: fk, count: self.numcep)
            scalars[0] = f0
            
            let ceplifter = Float(config.ceplifter ?? 22)
            let omega = Float.pi / ceplifter
            self.lift = scalars.enumerated().map { k, scalar in
                scalar * (1 + (ceplifter / 2.0) * sin(Float(k) * omega))
            }
        }
        
        public static func ceilLog2(_ n: Int) -> Int {
            return (Int.bitWidth - (n - 1).leadingZeroBitCount)
        }
        
        /**
         Compute MFCC features from an audio signal.
         - Parameter signal: the audio signal.
         - Returns: An array of size (NUMFRAMES by numcep) containing features.
         */
        public func update(signal: [Float]) -> (indices: Range<Int>, features: [Float]) {
            let startIndex = -self.audioBuffer.numPaddedFrames
            let (logFeat, logEnergy) = fbank(signal: signal)
            guard !logFeat.isEmpty else { return (0..<0, []) }
            
            // DCT
            guard let dct = vDSP.DCT(count: nfilt, transformType: .II) else { // segfault
                fatalError("Could not create DCT setup")
            }
            
            if appendEnergy {
                let features = zip(stride(from: 0, to: logFeat.count, by: nfilt), logEnergy).flatMap { i, energy in
                    var res = vDSP.multiply(lift, dct.transform(logFeat[i..<i+nfilt]).prefix(numcep))
                    res[0] = energy
                    return res
                }
                return (startIndex..<startIndex+logEnergy.count, features)
            }
            let features = stride(from: 0, to: logFeat.count, by: nfilt).flatMap { i in
                vDSP.multiply(lift, dct.transform(logFeat[i..<i+nfilt]).prefix(numcep))
            }
            return (startIndex..<startIndex+logEnergy.count, features)
        }
        
        /**
         Calculates the FFT size as a power of two greater than or equal to
         the number of samples in a single window length.
         - Parameters:
         - samplerate: The sample rate of the signal we are working with, in Hz.
         - winlen: The length of the analysis window in seconds.
         - Returns: The calculated FFT size.
         */
        private static func calculateNfft(samplerate: Int, winlen: Float) -> Int {
            return 1 << ceilLog2(Int(winlen * Float(samplerate) + 0.5))
        }
        
        private static func nextDCTLength(_ n: Int) -> Int {
            let l2  =  1 << ceilLog2(n)
            let l3  =  3 << ceilLog2((n + 2) / 3)
            let l5  =  5 << ceilLog2((n + 4) / 5)
            let l15 = 15 << ceilLog2((n + 14) / 15)
            
            return [l2, l3, l5, l15].filter { ($0 & 0b111) == 0 }.min()!
        }
        
        /**
         Convert a value in Hertz to Mels.
         */
        private static func hz2mel(_ hz: Float) -> Float {
            return 2595 * log10(1 + hz / 700)
        }
        
        /**
         Convert a value in Mels to Hertz.
         */
        private static func mel2hz(_ mel: Float) -> Float {
            return 700 * (pow(10, mel / 2595) - 1)
        }
        
        /// Rounds a number to the nearest integer, with halves rounded up.
        /// - Parameter number: The number to round.
        /// - Returns: The rounded integer.
        private static func roundHalfUp(_ number: Float) -> Int {
            return Int(number + 0.5)
        }
        
        /**
         Compute a Mel-filterbank.
         - Returns: An array of size `(nfft/2 + 1, nfilt)` containing the transposed filterbank.
         */
        private static func getFilterbanks(nfilt: Int, nfft: Int, samplerate: Int, lowfreq: Float, highfreq: Float) -> [Float] {
            let lowmel = hz2mel(lowfreq)
            let highmel = hz2mel(highfreq)
            
            let melpoints = Utils.ML.linspace(from: lowmel, through: highmel, count: nfilt + 2)
            
            let bin = melpoints.map { floor((Float(nfft) + 1) * mel2hz($0) / Float(samplerate)) }
            
            let rowSize = nfft / 2 + 1
            var fbank = [Float](repeating: 0, count: nfilt * rowSize)
            
            for j in 0..<nfilt {
                let startBin = Int(bin[j])
                let midBin = Int(bin[j+1])
                let endBin = Int(bin[j+2])
                
                for i in startBin..<midBin {
                    fbank[j + i * nfilt] = (Float(i) - bin[j]) / (bin[j+1] - bin[j])
                }
                for i in midBin..<endBin {
                    fbank[j + i * nfilt] = (bin[j+2] - Float(i)) / (bin[j+2] - bin[j+1])
                }
            }
            
            return fbank
        }
        
        static func powspec(frames: LazyMapSequence<Range<Int>, Array<Float>>, nfft: Int) -> (powspec: [Float], energy: [Float]) {
            // NFFT must be a positive, even number for vDSP's real-to-complex FFT.
            guard nfft > 0, nfft % 2 == 0 else {
                print("Error: NFFT must be a positive, even number.")
                return ([], [])
            }
            
            let halfNFFT = nfft / 2
            let scaleFactor: Float = 0.25 / Float(nfft)
            
            // The FFT setup is created once and reused for each frame to improve performance.
            guard let fftSetup = vDSP.FFT(log2n: vDSP_Length(log2(Float(nfft))),
                                          radix: .radix2,
                                          ofType: DSPSplitComplex.self) else {
                print("Error: Failed to create FFT setup.")
                return ([], [])
            }

            let rowStep = halfNFFT + 1
            var powerSpectra = [Float](repeating: 0, count: frames.count * rowStep)
            var energy = [Float](repeating: 0, count: frames.count)
            var ip = 0;
            
            for (ie, var frame) in frames.enumerated() {
                // Truncate or zero-pad the frame to the NFFT length.
                if frame.count > nfft {
                    print("Warning: Frame length (\(frame.count)) is greater than FFT size (\(nfft)). The frame will be truncated.")
                    frame = Array(frame.prefix(nfft))
                } else if frame.count < nfft {
                    frame.append(contentsOf: [Float](repeating: 0.0, count: nfft - frame.count))
                }
                
                // Create buffers to hold the real and imaginary parts of the complex spectrum.
                var realPart = [Float](repeating: 0.0, count: halfNFFT)
                var imagPart = [Float](repeating: 0.0, count: halfNFFT)
                
                // --- FIX: Pack the real frame into the complex buffers before the FFT ---
                // An in-place real FFT expects the even-indexed elements of the input signal
                // in the real part of the complex buffer and the odd-indexed elements in the
                // imaginary part. The `vDSP_ctoz` function performs this packing.
                realPart.withUnsafeMutableBufferPointer { realPtr in
                    imagPart.withUnsafeMutableBufferPointer { imagPtr in
                        let realBase = realPtr.baseAddress!
                        let imagBase = imagPtr.baseAddress!
                        frame.withUnsafeBytes { frameRawBufferPtr in
                            
                            // Treat the [Float] buffer as a buffer of DSPComplex structs for vDSP_ctoz
                            let frameAsComplex = frameRawBufferPtr.bindMemory(to: DSPComplex.self)
                            
                            
                            var complexDest = DSPSplitComplex(realp: realBase, imagp: imagBase)
                            vDSP_ctoz(frameAsComplex.baseAddress!, 2, &complexDest, 1, vDSP_Length(halfNFFT))
                        }
                        var complexBuffer = DSPSplitComplex(realp: realBase, imagp: imagBase)
                        
                        // This call now works because complexBuffer is the correct input type.
                        fftSetup.forward(input: complexBuffer, output: &complexBuffer)
                    }
                }
                
                // Calculate magnitudes from the packed frequency-domain data.
                // This logic remains the same as the previous correction.
                powerSpectra[ip] = realPart[0] * realPart[0] * scaleFactor
                powerSpectra[ip+halfNFFT] = imagPart[0] * imagPart[0] * scaleFactor
                
                if halfNFFT > 1 {
                    vDSP.multiply(scaleFactor,
                                  vDSP.add(
                                    vDSP.square(realPart.suffix(from: 1)),
                                    vDSP.square(imagPart.suffix(from: 1))
                                  ),
                                  result: &powerSpectra[ip+1..<ip+halfNFFT])
                }
                
                let en = vDSP.sum(powerSpectra[ip...ip+halfNFFT])
                energy[ie] = en != 0 ? log(en) : MFCC.LOG0
                
                ip += rowStep
            }

            return (powspec: powerSpectra, energy: energy)
        }
        
        /**
         Compute Mel-filterbank energy features from an audio signal.
         - Returns: 2 values. The first is an array of size (NUMFRAMES by nfilt) containing features.
         The second return value is the energy in each frame.
         */
        private func fbank(signal: [Float]) -> (feat: [Float], energy: [Float]) {
            self.audioBuffer.write(signal)
            let (pspec, energy) = MFCC.powspec(frames: self.audioBuffer.frames, nfft: nfft)
            
            // Simplified and corrected dimension check
            let halfNfftP1 = nfft / 2 + 1
            let M = vDSP_Length(audioBuffer.count)
            let N = vDSP_Length(nfilt)
            let K = vDSP_Length(halfNfftP1)
            
            var feat = [Float](repeating: 0, count: Int(M * N))
            
            // 2) Multiply A (M×K) × Bᵀ (K×N) → result (M×N)
            vDSP_mmul(
                pspec,   1,
                fb,      1,
                &feat,   1,
                M, N, K
            )
            
            feat = feat.map {
                $0 != 0 ? log($0) : MFCC.LOG0
            }
            
            return (feat, energy)
        }
    }
}
