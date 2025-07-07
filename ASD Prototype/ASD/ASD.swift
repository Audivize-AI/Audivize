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
        typealias TrackingCallback = @Sendable ([SendableSpeaker]) async -> Void
        typealias ASDCallback = @Sendable (VideoProcessor.TimestampedScoreData) async -> Void
        typealias MergeCallback = @Sendable (MergeRequest) -> Void
        
        private let videoProcessor: VideoProcessor
        private let modelPool: Utils.ML.ModelPool<ASDVideoModel>
        private let trackingCallback: TrackingCallback?
        private let asdCallback: ASDCallback?
        
        private var frameSkipCounter: Int = 0
        private var gifCounter: Int = 0
        
        /// - Parameters:
        ///   - time current time
        ///   - videoSize video input size
        ///   - cameraAngle initial camera angle
        ///   - callback callback for when the ASD model finishes determining active speakers.
        ///   - mergeCallback callback for when two tracks are merged
        init(atTime time: Double,
             videoSize: CGSize,
             cameraAngle: CGFloat,
             onTrackComplete trackingCallback: TrackingCallback? = nil,
             onASDComplete asdCallback: ASDCallback? = nil,
             onMerge mergeCallback: MergeCallback? = nil)
        {
            self.videoProcessor = .init(atTime: time,
                                        videoSize: videoSize,
                                        cameraAngle: cameraAngle,
                                        mergeCallback: mergeCallback)
            self.frameSkipCounter = 0
            self.trackingCallback = trackingCallback
            self.asdCallback = asdCallback
            
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndGPU
            
            self.modelPool = try! .init(count: ASDConfiguration.numASDModels) {
                try .init(configuration: configuration)
            }
        }
        
        public func update(videoSample sampleBuffer: CMSampleBuffer, cameraPosition: AVCaptureDevice.Position, connection: AVCaptureConnection) throws {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            let time = sampleBuffer.presentationTimeStamp.seconds
            
            // determine if we skip this frame to update ASD
            self.frameSkipCounter += 1
            let isVideoUpdate = self.frameSkipCounter < 6
            if isVideoUpdate == false {
                self.frameSkipCounter = 0
                self.gifCounter += 1
            }
            
            let gifCounter = self.gifCounter
            let videoProcessor = self.videoProcessor
            let trackingCallback = self.trackingCallback
            let asdCallback = self.asdCallback
            let modelPool = self.modelPool
            
            let orientation = Tracking.CameraOrientation(
                angle: connection.videoRotationAngle,
                mirrored: (connection.isVideoMirrored) != (cameraPosition == .back)
            )
            
            Task.detached(priority: .userInitiated) {
                if isVideoUpdate {
                    // tracking and video buffer update
                    let speakers = await videoProcessor.updateVideosAndGetSpeakers(
                        atTime: time,
                        from: pixelBuffer,
                        orientation: orientation
                    )
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                    await trackingCallback?(speakers)
                } else {
                    // tracking update
                    let videoInputs = await videoProcessor.updateTracksAndGetFrames(atTime: time, from: pixelBuffer)
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                    
                    if gifCounter % 6 == 0 {
                        for (id, videoInput) in videoInputs {
                            Utils.ML.saveMultiArrayAsGIF(videoInput, to: "\(id) (\(gifCounter / 6)).gif")
                        }
                    }
                    
                    // ASD update
                    let newScores = try await ASD.computeSpeakerScores(
                        atTime: time,
                        from: videoInputs,
                        using: modelPool,
                    )
                    
                    let (speakers, scores) = await videoProcessor.updateScoresAndGetScoredSpeakers(
                        atTime: time,
                        with: newScores,
                        orientation: orientation
                    )
                    async let _ = trackingCallback?(speakers)
                    async let _ = asdCallback?(scores)
                }
            }
        }
        
        // MARK: private static helpers
        
        private static func computeSpeakerScores(atTime time: Double,
                                                 from videoInputs: [UUID: MLMultiArray],
                                                 using modelPool: Utils.ML.ModelPool<ASDVideoModel>) async throws -> [UUID: MLMultiArray]
        {
            return try await withThrowingTaskGroup(of: (UUID, MLMultiArray).self) { group in
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
        }
    }
}

extension ASDVideoModelOutput : @unchecked Sendable {}
extension ASDVideoModel: @unchecked Sendable {}

extension ASDVideoModel: MLWrapper {
    typealias Input = ASDVideoModelInput
    typealias Output = ASDVideoModelOutput
}
