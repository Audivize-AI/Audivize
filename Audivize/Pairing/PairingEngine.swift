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

extension Pairing {
    typealias ASDCallback = @Sendable ([ASD.SendableVisualSpeaker]) async -> Void
    typealias MergeCallback = @Sendable (MergeRequest) -> Void
    
    final class PairingEngine {
        
        typealias ASDModel = ASD.ASDConfiguration.ASDModel
        
        private let tracker: Tracking.Tracker
        private let asdManager: ASD.ASDManager
        
        private var activeSpeakers: [UUID: ASD.VisualSpeaker] = [:]
        private var inactiveSpeakers: [UUID: ASD.VisualSpeaker] = [:]
        
        private var frameSkipCounter: Int = 0
        private let callback: ASDCallback?
        
        init(atTime time: Double,
             videoSize: CGSize,
             cameraAngle: CGFloat,
             callback: ASDCallback? = nil) throws
        {
            self.tracker = Tracking.Tracker(faceProcessor: .init(),
                                            videoSize: videoSize,
                                            cameraAngle: cameraAngle)
            self.asdManager = try ASD.ASDManager(atTime: time,
                                                 numVideoBuffers: ASD.ASDConfiguration.numVideoBuffers,
                                                 numASDModels: ASD.ASDConfiguration.numASDModels)
            self.callback = callback
        }
        
        /// Update active speaker detection for the provided frame.
        public func update(videoSample sampleBuffer: CMSampleBuffer,
                           cameraPosition: AVCaptureDevice.Position,
                           connection: AVCaptureConnection) throws
        {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            let timestamp = sampleBuffer.presentationTimeStamp.seconds
            
            let orientation = Tracking.CameraOrientation(
                angle: connection.videoRotationAngle,
                mirrored: (connection.isVideoMirrored) != (cameraPosition == .back)
            )
            
//            self.frameSkipCounter += 1
            let dropFrame: Bool = false //frameSkipCounter >= 5
//            if dropFrame {
//                frameSkipCounter = 0
//            }
            
            defer { try? asdManager.advanceFrame(atTime: timestamp, dropFrame: dropFrame) }
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            defer {
                if let callback {
                    let sendableSpeakers = activeSpeakers.values.map {
                        $0.getSendable(isMirrored: orientation.isMirrored)
                    }
                    Task {
                        await callback(sendableSpeakers)
                    }
                }
            }
            
            // tracking update
            var tracks = tracker.update(pixelBuffer: pixelBuffer, orientation: orientation)
            
            var deactivatedSpeakers: [UUID] = []
            var deletedSpeakers: [UUID] = []
            
            // register frame for active speakers
            for (id, speaker) in activeSpeakers {
                if let trackId = speaker.trackId,
                   let track = tracks.removeValue(forKey: trackId) {
                    try speaker.registerNewFrame(from: pixelBuffer, track: track, drop: dropFrame)
                } else {
                    try speaker.registerMissedFrame(drop: dropFrame)
                    if speaker.status == .inactive {
                        deactivatedSpeakers.append(id)
                    }
                }
            }
            
            // register a missed frame for inactive speakers
            for (id, speaker) in inactiveSpeakers {
                try speaker.registerMissedFrame(drop: dropFrame)
                if speaker.isDeletable {
                    deletedSpeakers.append(id)
                }
            }
            
            // deactivate and delete speakers
            for id in deactivatedSpeakers {
                inactiveSpeakers[id] = activeSpeakers.removeValue(forKey: id)
            }
            
            for id in deletedSpeakers {
                inactiveSpeakers.removeValue(forKey: id)
            }
            
            // create new speakers
            for (_, track) in tracks {
                let speaker = ASD.VisualSpeaker(track: track, videoManager: asdManager)
                try speaker.registerNewFrame(from: pixelBuffer, track: track, drop: dropFrame)
                self.activeSpeakers[speaker.id] = speaker
            }
        }
    }
}

extension MLMultiArray: @unchecked @retroactive Sendable {}
