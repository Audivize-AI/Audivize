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
            let timestampBuffer: Utils.TimestampBuffer
            var track: Tracking.SendableTrack
            var lastUpdateTime: Double
            var timeLastSaved: Double = 0
            var speechHistory: [(timestamp: TimeInterval, score: Float)] {
                let timestamps = timestampBuffer.timestamps
                let scores = scoreBuffer.orderedProbabilities
                if timestamps.count != scores.count {
                    print("WARNING: \(timestamps.count) != \(scores.count)")
                    print("TIMESTAMPS: \(timestamps)")
                    print("SCORES: \(scores)")
                }
                return zip(timestamps, scores).map{ ($0, $1) }
            }
            
            init(atTime time: Double, track: Tracking.SendableTrack) {
                self.lastUpdateTime = time
                self.track = track
                self.videoBuffer = .init()
                self.scoreBuffer = .init(capacity: ASDConfiguration.scoreBufferCapacity)
                self.timestampBuffer = .init(atTime: time, capacity: ASDConfiguration.scoreBufferCapacity)
                self.timeLastSaved = time
            }
            
            mutating func updateVideoAndGetLastScore(atTime time: Double, from pixelBuffer: CVPixelBuffer, with track: Tracking.SendableTrack, skip: Bool) -> Float {
                self.videoBuffer.write(from: pixelBuffer, croppedTo: track.rect, skip: skip)
                self.track = track
                self.lastUpdateTime = time
                return self.scoreBuffer.readLogit(at: -1)
            }
            
            mutating func updateTrackAndGetFrames(atTime time: Double, from pixelBuffer: CVPixelBuffer, with track: Tracking.SendableTrack, skip: Bool) -> MLMultiArray {
                self.videoBuffer.write(from: pixelBuffer, croppedTo: track.rect, skip: skip)
                self.track = track
                self.lastUpdateTime = time
                let frames = self.videoBuffer.read(at: -1)
//                if time - self.timeLastSaved >= 1.95 {
//                    print("saving")
//                    Utils.ML.saveMultiArrayAsGIF(frames, to: "\(self.track.id.uuidString.prefix(4)) (\(time)).gif")
//                    self.timeLastSaved = time
//                }
                return frames
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
        private var iteration: Int = 0
        
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
        public func nextIteration() {
            self.iteration += 1
        }
        
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
                if iteration % ASDConfiguration.framesPerUpdate == track.asdSlot {
                    // ASD; Retrieve video frames
                    frames[track.id] = self.videoTracks[track.id, default: .init(atTime: time, track: track)]
                        .updateTrackAndGetFrames(atTime: time, from: pixelBuffer, with: track, skip: skipFrame)
                } else {
                    // No ASD; Retrieve last speaker score
                    _ = self.videoTracks[track.id, default: .init(atTime: time, track: track)]
                        .updateVideoAndGetLastScore(atTime: time, from: pixelBuffer, with: track, skip: skipFrame)
                    speakers.append(.init(track: track,
                                          speechHistory: self.videoTracks[track.id]!.speechHistory,
                                          mirrored: orientation.isMirrored))
                }
            }
            
            // delete inactive tracks
            self.videoTracks = self.videoTracks.filter { _, videoTrack in
                videoTrack.lastUpdateTime >= time
            }
            
            return (frames, speakers)
        }
        
        public func updateScoresAndGetScoredSpeakers(atTime time: Double, with scores: [UUID : [Float]], orientation: Tracking.CameraOrientation) -> (speakers: [SendableSpeaker], scores: TimestampedScoreData)
        {
            var speakers: [SendableSpeaker] = []
            speakers.reserveCapacity(self.videoTracks.count)
            
            for (id, score) in scores {
                if let videoTrack = self.videoTracks[id] {
                    videoTrack.scoreBuffer.write(from: score, count: ASDConfiguration.framesPerUpdate)
                    videoTrack.timestampBuffer.write(atTime: time, count: ASDConfiguration.framesPerUpdate)
//                    print("S = \(videoTrack.scoreBuffer.orderedCumulativeScores)")
                    speakers.append(.init(track: videoTrack.track,
                                          speechHistory: self.videoTracks[id]!.speechHistory,
                                          mirrored: orientation.isMirrored))
                }
            }
            
            self.scoreTimestamps.write(atTime: time, count: ASDConfiguration.framesPerUpdate)
            
            return (speakers: speakers, scores: self.timestampedScoreData)
        }
        
        // MARK: Getter methods 
        public func getScores(atTime time: Double?) -> [UUID : Float] {
            let index = self.scoreTimestamps.indexOf(time ?? self.lastScoreTime)
            return Dictionary(uniqueKeysWithValues: self.videoTracks.map { id, speaker in
                (id, speaker.scoreBuffer.readLogit(at: index))
            })
        }
    }
}
