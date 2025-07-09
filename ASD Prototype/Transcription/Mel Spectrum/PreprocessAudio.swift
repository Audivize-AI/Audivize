//
//  AudioPost.swift
//  ASD Prototype
//
//  Created by ChatGPT on 6/24/25.
//

import Foundation
import AVFoundation


extension ASD {
    static func resampleAudioToFloat32(from sampleBuffer: CMSampleBuffer, to sampleRate: Double = 16000.0) -> [Float] {
        guard
            let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
            var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
        else {
            return []
        }
        
        // Original format
        let sourceFormat = AVAudioFormat(streamDescription: &asbd)!
        
        // Wrap CMSampleBuffer in AVAudioPCMBuffer
        let numFrames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(numFrames)) else {
            return []
        }
        
        pcmBuffer.frameLength = AVAudioFrameCount(numFrames)
        let bufferList = pcmBuffer.mutableAudioBufferList
        CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(numFrames),
            into: bufferList
        )
        
        // Target: 16kHz, Float32, non-interleaved
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: sampleRate,
                                               channels: sourceFormat.channelCount,
                                               interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else {
            return []
        }
        
        // Allocate target buffer

        let targetFrameCapacity = AVAudioFrameCount(Double(numFrames) * sampleRate / sourceFormat.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCapacity) else {
            return []
        }
        
        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }
        
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("Conversion failed: \(error)")
            return []
        }
        
        // Extract Float32 data
        guard let floatData = convertedBuffer.floatChannelData else {
            return []
        }
        
        let frameLength = Int(convertedBuffer.frameLength)
        let channelCount = Int(convertedBuffer.format.channelCount)
        
        // For mono:
        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: floatData[0], count: frameLength))
        } else {
            // Flatten interleaved channels manually (if needed)
            var result = [Float]()
            for i in 0..<frameLength {
                for c in 0..<channelCount {
                    result.append(floatData[c][i])
                }
            }
            return result
        }
    }
}
