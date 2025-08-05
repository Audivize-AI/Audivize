//
//  VideoHandler.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/29/25.
//

import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreML


extension ASD {
    actor VideoProcessor {
        struct VideoTrack {
            let videoBuffer: VideoBuffer
            let scoreBuffer: ScoreBuffer
            var track: Tracking.Tracker.SendableTrack
            
            var lastFrameWriteTime: Double
            
            init(atTime time: Double, track: Tracking.Tracker.SendableTrack, backtrackFrames: Int, videoBufferPadding: Int = 25, scoreBufferCapacity: Int = 53) {
                self.lastFrameWriteTime = time
                self.track = track
                self.videoBuffer = .init(frontPadding: backtrackFrames, backPadding: videoBufferPadding)
                self.scoreBuffer = .init(atTime: time, frontPadding: backtrackFrames, capacity: scoreBufferCapacity)
            }
            
            mutating func updateVideo(atTime time: Double, from pixelBuffer: CVPixelBuffer, with track: Tracking.Tracker.SendableTrack, skip: Bool = false) {
                self.videoBuffer.write(from: pixelBuffer, croppedTo: track.rect, skip: skip)
                self.track = track
                self.lastFrameWriteTime = time
            }
        }
        
        // MARK: Public properties
        public private(set) var speakers: [UUID: VideoTrack]
        public var lastVideoTime: Double { self.videoTimestamps.lastWriteTime }
        public var lastScoreTime: Double { self.scoreTimestamps.lastWriteTime }
        
        // MARK: Private properties
        private let tracker: Tracking.Tracker
        private let backtrackFrames: Int
        private let videoBufferPadding: Int
        private let videoTimestamps: Utils.TimestampBuffer
        private let scoreTimestamps: Utils.TimestampBuffer
        
        // MARK: Constructor
        init(atTime time: Double, backtrackFrames: Int, videoBufferPadding: Int = 12) {
            self.videoBufferPadding = videoBufferPadding
            self.backtrackFrames = backtrackFrames
            self.tracker = .init(faceProcessor: .init())
            self.videoTimestamps = .init(atTime: time, capacity: 25 + videoBufferPadding + backtrackFrames)
            self.scoreTimestamps = .init(atTime: time, capacity: 53)
            self.speakers = [:]
        }
        
        // MARK: Updater methods
        public func updateVideos(atTime time: Double, from pixelBuffer: CVPixelBuffer, connection: AVCaptureConnection, skip: Bool) {
            // get tracks
            let orientation = Utils.Images.cgImageOrientation(fromRotationAngle: connection.videoRotationAngle,
                                                              mirrored: connection.isVideoMirrored)
            let tracks = tracker.update(pixelBuffer: pixelBuffer, orientation: orientation)
            
            // update speakers
            for track in tracks where track.rect.width.isNaN == false {
                self.speakers[track.id, default: self.makeSpeaker(atTime: time, track: track)]
                    .updateVideo(atTime: time, from: pixelBuffer, with: track, skip: skip)
            }
            
            self.speakers = self.speakers.filter { _, speaker in
                speaker.lastFrameWriteTime >= time
            }
            
            // update timestamps
            if skip == false {
                self.videoTimestamps.write(atTime: time)
            }
        }
        
        public func updateScores(atTime time: Double, with scores: [UUID : MLMultiArray]) -> [SpeakerData] {
            for (id, score) in scores {
                self.speakers[id]?.scoreBuffer.write(from: score)
            }
            self.videoTimestamps.write(atTime: time)
            return self.speakers.values.map { speaker in
                    .init(track: speaker.track, score: speaker.scoreBuffer.read(at: -12), rect: speaker.videoBuffer.cropRect)
            }
        }
        
        // MARK: Getter methods
        public func getFrames(atTime time: Double) -> [UUID : MLMultiArray] {
            let index = self.videoTimestamps.indexOf(time)
            return Dictionary<UUID, MLMultiArray>(uniqueKeysWithValues: self.speakers.map { id, speaker in
                return (id, speaker.videoBuffer.read(at: index))
            })
        }
        
        // MARK: Getter methods
        public func getFrames(at index: Int = -1) -> [UUID : MLMultiArray] {
            return .init(uniqueKeysWithValues: self.speakers.map { id, speaker in
                return (id, speaker.videoBuffer.read(at: index))
            })
        }
        
        public func getScores(atTime time: Double?) -> [UUID : Float] {
            let index = self.scoreTimestamps.indexOf(time ?? self.lastScoreTime)
            return Dictionary(uniqueKeysWithValues: self.speakers.map { id, speaker in
                (id, speaker.scoreBuffer.read(at: index))
            })
        }
        
        public func getSpeakers(atTime time: Double) -> [SpeakerData] {
            let index = self.scoreTimestamps.indexOf(time)
            return self.speakers.values.map { speaker in
                    .init(track: speaker.track, score: speaker.scoreBuffer.read(at: index), rect: speaker.videoBuffer.cropRect)
            }
        }
        
        // MARK: Private helpers
        @inline(__always)
        private func makeSpeaker(atTime time: Double, track: Tracking.Tracker.SendableTrack) -> VideoTrack {
            return .init(atTime: time,
                         track: track,
                         backtrackFrames: self.backtrackFrames,
                         videoBufferPadding: self.videoBufferPadding,
                         scoreBufferCapacity: 25)
        }
    }
}

extension MLMultiArray: @unchecked @retroactive Sendable {}
