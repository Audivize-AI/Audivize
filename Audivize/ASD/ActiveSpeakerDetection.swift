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
    
    protocol ASDModelType {
        associatedtype Model
        associatedtype Input
        associatedtype Output
        static var videoLength: Int { get }
        static var minFrames: Int { get }
    }
    
    enum ASD25_AVA: ASDModelType {
        typealias Model = ASDVideoModel25_AVA
        typealias Input = ASDVideoModel25_AVAInput
        typealias Output = ASDVideoModel25_AVAOutput
        static let videoLength = 25
        static let minFrames = 12
    }
    
    enum ASD25_TalkSet: ASDModelType {
        typealias Model = ASDVideoModel25_TalkSet
        typealias Input = ASDVideoModel25_TalkSetInput
        typealias Output = ASDVideoModel25_TalkSetOutput
        static let videoLength = 25
        static let minFrames = 12
    }
    
    enum ASD50_AVA: ASDModelType {
        typealias Model = ASDVideoModel50_AVA
        typealias Input = ASDVideoModel50_AVAInput
        typealias Output = ASDVideoModel50_AVAOutput
        static let videoLength = 50
        static let minFrames = 12
    }
    
    enum ASD50_TalkSet: ASDModelType {
        typealias Model = ASDVideoModel50_TalkSet
        typealias Input = ASDVideoModel50_TalkSetInput
        typealias Output = ASDVideoModel50_TalkSetOutput
        static let videoLength = 50
        static let minFrames = 12
    }
    
    final class ASD {
        typealias TrackingCallback = @Sendable ([SendableSpeaker]) async -> Void
        typealias ASDCallback = @Sendable (VideoProcessor.TimestampedScoreData) async -> Void
        typealias MergeCallback = @Sendable (MergeRequest) -> Void
        typealias ASDModel = ASDConfiguration.ASDModel
        
        // MARK: Private attributes
        private let tracker: Tracking.Tracker
        private let videoProcessor: VideoProcessor
        private let modelPool: Utils.ML.ModelPool<ASDModel.Model>
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
                                 cameraAngle: cameraAngle)
            
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
                                                 using modelPool: Utils.ML.ModelPool<ASDModel.Model>)
            async throws -> [UUID: [Float]]
        {
            return try await withThrowingTaskGroup(of: (UUID, [Float]).self) { group in
                for (id, videoInput) in videoInputs {
                    group.addTask(priority: .userInitiated) {
                        let input = ASDModel.Input(videoInput: videoInput)
                        let scores = try await modelPool.withModel { model in
//                            let start = Date()
                            let result = try model.prediction(input: input).scoresShapedArray.scalars
//                            let end = Date()
//                            print("Active Speaker Detection in \(end.timeIntervalSince(start)) seconds")
                            return result
                        }
                        return (id, scores)
                    }
                }
                
                var results: [UUID: [Float]] = [:]
                
                for try await (id, scores) in group {
                    results[id] = scores
                }
                
                return results
            }
        }
    }
}


extension MLMultiArray: @unchecked @retroactive Sendable {}

extension ASDVideoModel25_TalkSetOutput : @unchecked Sendable {}
extension ASDVideoModel25_TalkSet: @unchecked Sendable, MLWrapper {}

extension ASDVideoModel50_TalkSetOutput : @unchecked Sendable {}
extension ASDVideoModel50_TalkSet: @unchecked Sendable, MLWrapper {}

extension ASDVideoModel25_AVAOutput : @unchecked Sendable {}
extension ASDVideoModel25_AVA: @unchecked Sendable, MLWrapper {}

extension ASDVideoModel50_AVAOutput : @unchecked Sendable {}
extension ASDVideoModel50_AVA: @unchecked Sendable, MLWrapper {}
