//
//  ASD.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/23/25.
//

import Foundation
@preconcurrency import CoreML
@preconcurrency import AVFoundation
import Vision

extension ASD {
    final class ASD {
        private let videoProcessor: VideoProcessor
        private let modelPool: Utils.ML.ModelPool<ASDVideoModel>
        private let onFused: @Sendable ([SendableSpeaker]) async -> Void
        
        private var frameSkipCounter: Int = 0
        
        init(atTime time: Double,
             onFused: @Sendable @escaping ([SendableSpeaker]) async -> Void,
             onMerge: @Sendable @escaping (MergeRequest) -> Void = { _ in },
             numModels: Int = 8,
             videoBufferPadding: Int = 49,
             scoreBufferPadding: Int = 25)
        {
            self.videoProcessor = .init(atTime: time,
                                        videoBufferPadding: videoBufferPadding,
                                        scoreBufferPadding: scoreBufferPadding,
                                        mergeCallback: onMerge)
            self.frameSkipCounter = 0
            self.onFused = onFused
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndGPU
            self.modelPool = try! .init(count: numModels) {
                try .init(configuration: configuration)
            }
        }
        
        public func update(videoSample sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) throws {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            let time = sampleBuffer.presentationTimeStamp.seconds
            
            // determine if we skip this frame to update ASD
            self.frameSkipCounter += 1
            let isVideoUpdate = self.frameSkipCounter < 6
            if isVideoUpdate == false {
                self.frameSkipCounter = 0
            }
            
            let videoProcessor = self.videoProcessor
            let callback = self.onFused
            let modelPool = self.modelPool
            
            Task.detached(priority: .userInitiated) {
                if isVideoUpdate {
                    // tracking and video buffer update
                    let speakers = await videoProcessor.updateVideosAndGetSpeakers(atTime: time, from: pixelBuffer, connection: connection)
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                    await callback(speakers)
                } else {
                    // tracking update
                    let videoInputs = await videoProcessor.updateTracksAndGetFrames(atTime: time, from: pixelBuffer, connection: connection)
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                    // ASD update
                    let scores: [UUID: MLMultiArray] = try await withThrowingTaskGroup(of: (UUID, MLMultiArray).self) { group in
                        for (id, videoInput) in videoInputs {
                            group.addTask {
                                let input = ASDVideoModelInput(videoInput: videoInput)
                                let scores = try await modelPool.withModel { model in
                                    try model.prediction(input: input).scores
                                }
                                return (id, scores)
                            }
                        }
                        
                        var results: [UUID: MLMultiArray] = [:]
                        
                        for try await (id, scores) in group {
                            results[id] = scores
                        }
                        
                        return results
                    }
                    let res = await videoProcessor.updateScoresAndGetSpeakers(atTime: time, with: scores)
                    await callback(res)
                }
            }
        }
    }
}

extension ASDVideoModelOutput : @unchecked Sendable {}
extension ASDVideoModel: @unchecked Sendable {}

extension ASDVideoModel: MLWrapper {
    typealias Input = ASDVideoModelInput
    typealias Output = ASDVideoModelOutput
}
