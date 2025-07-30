//
//  ASD.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/23/25.
//

import Foundation
@preconcurrency import Vision
@preconcurrency import CoreML
@preconcurrency import AVFoundation

extension ASD {
    final class ASD {
        typealias TrackingCallback = @Sendable ([SendableSpeaker]) async -> Void
        typealias ASDCallback = @Sendable (VideoProcessor.TimestampedScoreData) async -> Void
        typealias MergeCallback = @Sendable (MergeRequest) -> Void
        
        // MARK: Private attributes
        private let tracker: Tracking.Tracker
        private let videoProcessor: VideoProcessor
        private let modelPool: Utils.ML.ModelPool<ASDVideoModel>
        private let trackingCallback: TrackingCallback?
        private let asdCallback: ASDCallback?
        
        private var frameSkipCounter: Int = 0
        
        // MARK: Constructors
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
            self.videoProcessor = .init(atTime: time)
            self.tracker = .init(faceProcessor: .init(),
                                 videoSize: videoSize,
                                 cameraAngle: cameraAngle,
                                 onTracksMerged: mergeCallback)
            
            self.frameSkipCounter = 0
            self.trackingCallback = trackingCallback
            self.asdCallback = asdCallback
            
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndGPU
            
            self.modelPool = try! .init(count: ASDConfiguration.numASDModels) {
                try .init(configuration: configuration)
            }
        }
        
        // MARK: Public methods
        
        /// Update active speaker detection
        /// - Parameters:
        ///   - sampleBuffer video sample buffer
        ///   - cameraPosition camera position (front or back)
        ///   - connection capture connection.
        public func update(videoSample sampleBuffer: CMSampleBuffer, cameraPosition: AVCaptureDevice.Position, connection: AVCaptureConnection) throws {
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
            let trackingCallback = self.trackingCallback
            let asdCallback = self.asdCallback
            let modelPool = self.modelPool
            let tracker = self.tracker
            
            let orientation = Tracking.CameraOrientation(
                angle: connection.videoRotationAngle,
                mirrored: (connection.isVideoMirrored) != (cameraPosition == .back)
            )
            
            Task(priority: .userInitiated) {
                // update tracker
                let tracks = await tracker.update(
                    pixelBuffer: pixelBuffer,
                    orientation: orientation
                )
                
                // update video frames
                var (frames, speakers) = await videoProcessor.updateTracks(
                    atTime: time,
                    from: tracks,
                    in: pixelBuffer,
                    orientation: orientation,
                    skipFrame: !isVideoUpdate
                )
                
                // unlock pixel buffer
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                
                // active speaker detection
                if !frames.isEmpty {
                    let speakerScores = try await ASD.computeSpeakerScores(
                        atTime: time,
                        from: frames,
                        using: modelPool,
                    )
                    
                    let (remainingSpeakers, scores) = await videoProcessor.updateScoresAndGetScoredSpeakers(
                        atTime: time,
                        with: speakerScores,
                        orientation: orientation
                    )
                    speakers.append(contentsOf: remainingSpeakers)
                    async let _ = asdCallback?(scores)
                }
                await trackingCallback?(speakers)
            }
        }
        
        // MARK: private static helpers
        
        private static func computeSpeakerScores(atTime time: Double,
                                                 from videoInputs: [UUID: MLMultiArray],
                                                 using modelPool: Utils.ML.ModelPool<ASDVideoModel>)
            async throws -> [UUID: MLMultiArray]
        {
            return try await withThrowingTaskGroup(of: (UUID, MLMultiArray).self) { group in
                for (id, videoInput) in videoInputs {
                    group.addTask(priority: .userInitiated) {
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


extension MLMultiArray: @unchecked @retroactive Sendable {}
extension ASDVideoModelOutput : @unchecked Sendable {}
extension ASDVideoModel: @unchecked Sendable {}

extension ASDVideoModel: MLWrapper {}
