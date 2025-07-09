//
//  AudioBuffer.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/24/25.
//

import Foundation
import Accelerate

                    
extension ASD {
    final class AudioBuffer: Buffer {
        typealias Element = Float32
        
        public var count: Int {
            numFrames
        }
        
        public var frameViews: LazyMapSequence<Range<Int>, ArraySlice<Float>> {
            (0..<self.count).lazy.map(self.getFrameView)
        }
        
        public var frames: LazyMapSequence<Range<Int>, Array<Float>> {
            (0..<self.count).lazy.map(self.getFrame)
        }
        
        public var signalView: ArraySlice<Float> {
            self.buffer[startIndex..<writeIndex]
        }
        
        public var paddedSignalView: ArraySlice<Float> {
            self.buffer[startIndex..<endIndex]
        }
        
        public var signal: [Float] {
            Array(self.buffer[startIndex..<writeIndex])
        }
        
        public var paddedSignal: [Float] {
            Array(self.buffer[startIndex..<endIndex])
        }
        
        public var numFrames: Int {
            if writeIndex <= winLen {
                return 1
            }
            return 2 + (writeIndex - startIndex - winLen - 1) / winStep
        }
        
        public let winLen: Int
        public let winStep: Int
        public let preemph: Float
        public let winKernel: [Float]?
        public private(set) var numPaddedFrames: Int
        
        private var buffer: ContiguousArray<Float>
        private var writeIndex: Int
        private var startIndex: Int
        private var endIndex: Int
        private var nextStart: Int
        
        // im gonna crash out if the sample rate drops below 30 fps
        init(sampleRate: Int,
             winlen: Int,
             winstep: Int,
             capacity: Int = 2048,
             preemph: Float = 0.97,
             windowFunction: ((Int) -> Float)? = nil) {
            assert(capacity >= winstep)
            assert(sampleRate > 0)
            
            self.winLen = winlen
            self.winStep = winstep
            self.preemph = preemph
            
            self.numPaddedFrames = 0
            self.writeIndex = 0
            self.startIndex = 0
            self.endIndex = 0
            self.nextStart = 0
            
            self.buffer = .init(repeating: 0, count: capacity)
            
            if let windowFunction = windowFunction {
                self.winKernel = (0..<winlen).map(windowFunction)
            } else {
                self.winKernel = nil
            }
        }
        
        /// Converts duration (seconds) to length (samples)
        /// - Parameter duration duration of something in seconds
        /// - Parameter sampleRate sample rate in Hz
        /// - Returns number of samples that occupy that duration
        static func length(from duration: Float, with sampleRate: Int) -> Int {
            return Int(duration * Float(sampleRate) + 0.5)
        }
        
        public subscript(_ index: Int) -> ArraySlice<Float> {
            let startIndex = self.startIndex + index * winStep
            return buffer[startIndex..<startIndex+winLen]
        }
        
        func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Float>) throws -> R) rethrows -> R {
            return try self.buffer.withUnsafeBufferPointer(body)
        }
        
        func withUnsafeMutableBufferPointer<R>(_ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            return try self.buffer.withUnsafeMutableBufferPointer(body)
        }
        
        public func getFrame(_ index: Int) -> [Float] {
            let start = self.startIndex + index * self.winStep
            let frame = buffer[start ..< start+self.winLen]
            if winKernel != nil {
                return vDSP.multiply(self.winKernel!, frame)
            }
            return Array(frame)
        }
        
        public func getFrameView(_ index: Int) -> ArraySlice<Float> {
            let startIndex = self.startIndex + index * winStep
            return buffer[startIndex ..< startIndex + winLen]
        }
        
        public func write(_ signal: [Float]) {
            self.startIndex = self.nextStart
            let sigCount    = signal.count
            let memCount    = buffer.count
            var wrtIdx      = self.writeIndex
            let sttIdx      = self.startIndex
            let endIdx      = self.endIndex
            let copyCount   = wrtIdx - sttIdx
            let (paddedFrames, paddedCount) = computePaddedLength(sigCount)
            let unpaddedLength = self.computeUnpaddedLength(sigCount).samples
            
            self.numPaddedFrames = paddedFrames
            
            signal.withUnsafeBufferPointer { sigPtr in
                buffer.withUnsafeMutableBufferPointer { memPtr in
                    let base = memPtr.baseAddress!
                    
                    if endIdx > memCount {
                        // move chunk of the array from the end to the beginning
                        memcpy(base,
                               base.advanced(by: sttIdx),
                               copyCount * MemoryLayout<Float>.stride)
                        
                        // write new signal
                        memcpy(base.advanced(by: copyCount),
                               sigPtr.baseAddress!,
                               sigCount * MemoryLayout<Float>.stride)
                        
                        // zero everything else
                        wrtIdx = copyCount
                        self.startIndex = 0
                        self.writeIndex = copyCount + sigCount
                        vDSP.clear(&memPtr[writeIndex...])
                    } else {
                        // write new signal
                        memcpy(base.advanced(by: wrtIdx),
                               sigPtr.baseAddress!,
                               sigCount * MemoryLayout<Float>.stride)
                        self.writeIndex += sigCount
                    }
                }
            }

            self.nextStart = wrtIdx + unpaddedLength
            self.endIndex = writeIndex + paddedCount
            self.preemphasize(from: wrtIdx, to: self.writeIndex)
        }
        
        @inline(__always)
        private func computeNumFramesProcessed(_ signalLength: Int) -> Int {
            return signalLength <= winLen ? 1 : 2 + ((signalLength - winLen - 1) / winStep)
        }
        
        @inline(__always)
        private func computePaddedLength(_ signalLength: Int) -> (frames: Int, samples: Int) {
            if signalLength <= winLen {
                return (1, winLen)
            }
            
            let numFrames = 2 + ((signalLength - winLen - 1) / winStep)
            let numSamples = (numFrames + 1) * winStep + winLen
            return (numFrames, numSamples)
        }
        
        @inline(__always)
        private func computeUnpaddedLength(_ signalLength: Int) -> (frames: Int, samples: Int) {
            if signalLength <= winLen {
                return (0, 0)
            }
            
            let numFrames = (signalLength - winLen) / winStep
            let numSamples = (numFrames + 1) * winStep
            return (numFrames, numSamples)
        }
        
        @inline(__always)
        private func preemphasize(from start: Int, to end: Int) {
            let start = max(1, start)
            vDSP.subtract(self.buffer[start..<end],
                          vDSP.multiply(self.preemph, self.buffer[start-1..<end-1]),
                          result: &self.buffer[start..<end])
        }
    }
}
