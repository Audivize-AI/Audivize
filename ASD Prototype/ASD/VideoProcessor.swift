//
//  VideoHandler.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/29/25.
//

import Foundation
import AVFoundation
@preconcurrency import CoreML


extension ASD {
    actor VideoProcessor {
        struct TimestampedScoreData: Sendable {
            let scoreData: [UUID : ScoreBuffer.SendableState]
            let timestampData: Utils.TimestampBuffer.SendableState
        }
        
        private struct VideoTrack {
            let videoBuffer: VideoBuffer
            let scoreBuffer: ScoreBuffer
            var track: Tracking.SendableTrack
            var lastUpdateTime: Double
            
            init(atTime time: Double, track: Tracking.SendableTrack) {
                self.lastUpdateTime = time
                self.track = track
                self.videoBuffer = .init()
                self.scoreBuffer = .init(capacity: ASDConfiguration.scoreBufferCapacity)
            }
            
            mutating func updateVideoAndGetLastScore(atTime time: Double, from pixelBuffer: CVPixelBuffer, with track: Tracking.SendableTrack, skip: Bool) -> Float {
                self.videoBuffer.write(from: pixelBuffer, croppedTo: track.rect, skip: skip)
                self.track = track
                self.lastUpdateTime = time
                return self.scoreBuffer[-1]
            }
            
            mutating func updateTrackAndGetFrames(atTime time: Double, from pixelBuffer: CVPixelBuffer, with track: Tracking.SendableTrack, skip: Bool) -> MLMultiArray {
                self.videoBuffer.write(from: pixelBuffer, croppedTo: track.rect, skip: skip)
                self.track = track
                self.lastUpdateTime = time
                return self.videoBuffer.read(at: -1)
            }
        }
        
        // MARK: Public properties
        public var lastScoreTime: Double { self.scoreTimestamps.lastWriteTime }
        public var timestampedScoreData: TimestampedScoreData {
            .init(
                scoreData: self.videoTracks.values.reduce(into: [:]) { result, track in
                    result[track.track.id] = track.scoreBuffer.data
                },
                timestampData: self.scoreTimestamps.data
            )
        }
        
        // MARK: Private properties
        private let scoreTimestamps: Utils.TimestampBuffer
        private var videoTracks: [UUID: VideoTrack]
        
        // MARK: Constructor
        init(atTime time: Double)
        {
            self.scoreTimestamps = .init(
                atTime: time,
                capacity: ASDConfiguration.scoreBufferCapacity
            )
            self.videoTracks = [:]
        }
        
        // MARK: Updater methods
        public func updateTracks(atTime time: Double,
                                 from tracks: [Tracking.SendableTrack],
                                 in pixelBuffer: CVPixelBuffer,
                                 orientation: Tracking.CameraOrientation,
                                 skipFrame: Bool)
            -> (frames: [UUID : MLMultiArray], speakers: [SendableSpeaker])
        {
            var frames: [UUID : MLMultiArray] = [:]
            var speakers: [SendableSpeaker] = []
            frames.reserveCapacity(tracks.count)
            
            // update video tracks
            for track in tracks {
                if track.iteration % 6 == 0 {
                    // ASD; Retrieve video frames
                    frames[track.id] = self.videoTracks[track.id, default: .init(atTime: time, track: track)]
                        .updateTrackAndGetFrames(atTime: time, from: pixelBuffer, with: track, skip: skipFrame)
                } else {
                    // No ASD; Retrieve last speaker score
                    let score = self.videoTracks[track.id, default: .init(atTime: time, track: track)]
                        .updateVideoAndGetLastScore(atTime: time, from: pixelBuffer, with: track, skip: skipFrame)
                    speakers.append(.init(track: track,
                                          score: score,
                                          mirrored: orientation.isMirrored))
                }
            }
            
            // delete inactive tracks
            self.videoTracks = self.videoTracks.filter { _, videoTrack in
                videoTrack.lastUpdateTime >= time
            }
            
            return (frames, speakers)
        }
        
        public func updateScoresAndGetScoredSpeakers(atTime time: Double, with scores: [UUID : MLMultiArray], orientation: Tracking.CameraOrientation) -> (speakers: [SendableSpeaker], scores: TimestampedScoreData)
        {
            var speakers: [SendableSpeaker] = []
            speakers.reserveCapacity(self.videoTracks.count)
            
            for (id, score) in scores {
                if let videoTrack = self.videoTracks[id] {
                    videoTrack.scoreBuffer.write(from: score, count: 5)
                    speakers.append(.init(track: videoTrack.track,
                                        score: videoTrack.scoreBuffer[-2],
                                        mirrored: orientation.isMirrored))
                }
            }
            
            self.scoreTimestamps.write(atTime: time, count: 5)
            
            return (speakers: speakers, scores: self.timestampedScoreData)
        }
        
        // MARK: Getter methods
        public func getScores(atTime time: Double?) -> [UUID : Float] {
            let index = self.scoreTimestamps.indexOf(time ?? self.lastScoreTime)
            return Dictionary(uniqueKeysWithValues: self.videoTracks.map { id, speaker in
                (id, speaker.scoreBuffer.read(at: index))
            })
        }
    }
}
