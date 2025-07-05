//
//  VideoHandler.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/29/25.
//

import Foundation
import CoreML
import AVFoundation


extension ASD {
    actor VideoProcessor {
        private struct VideoTrack {
            let videoBuffer: VideoBuffer
            let scoreBuffer: ScoreBuffer
            var track: Tracking.SendableTrack
            
            var lastUpdateTime: Double
            
            init(atTime time: Double, track: Tracking.SendableTrack, videoBufferPadding: Int, scoreBufferCapacity: Int) {
                self.lastUpdateTime = time
                self.track = track
                self.videoBuffer = .init(frontPadding: 0, backPadding: videoBufferPadding)
                self.scoreBuffer = .init(atTime: time, capacity: scoreBufferCapacity)
            }
            
            mutating func updateVideoAndGetLastScore(atTime time: Double, from pixelBuffer: CVPixelBuffer, with track: Tracking.SendableTrack) -> Float {
                self.videoBuffer.write(from: pixelBuffer, croppedTo: track.rect, skip: false)
                self.track = track
                self.lastUpdateTime = time
                return self.scoreBuffer[-1]
            }
            
            mutating func updateTrackAndGetFrames(atTime time: Double, from pixelBuffer: CVPixelBuffer, with track: Tracking.SendableTrack) -> MLMultiArray {
                self.videoBuffer.write(from: pixelBuffer, croppedTo: track.rect, skip: true)
                self.track = track
                self.lastUpdateTime = time
                return self.videoBuffer.read(at: -1)
            }
        }
        
        // MARK: Public properties
        public var lastScoreTime: Double { self.scoreTimestamps.lastWriteTime }
        
        // MARK: Private properties
        private let tracker: Tracking.Tracker
        private let videoBufferPadding: Int
        private let scoreBufferPadding: Int
        private let scoreTimestamps: Utils.TimestampBuffer

        private var videoTracks: [UUID: VideoTrack]
        
        // MARK: Constructor
        init(atTime time: Double,
             videoSize: CGSize,
             cameraAngle: CGFloat,
             videoBufferPadding: Int = 12,
             scoreBufferPadding: Int = 25,
             mergeCallback mergeTracks: @escaping (MergeRequest) -> Void = { _ in })
        {
            self.videoBufferPadding = videoBufferPadding
            self.scoreBufferPadding = scoreBufferPadding
            self.tracker = .init(
                faceProcessor: .init(),
                videoSize: videoSize,
                cameraAngle: cameraAngle,
                mergeCallback: mergeTracks
            )
            self.scoreTimestamps = .init(
                atTime: time,
                capacity: asdVideoLength + scoreBufferPadding
            )
            self.videoTracks = [:]
        }
        
        // MARK: Updater methods
        
        public func updateVideosAndGetSpeakers(atTime time: Double, from pixelBuffer: CVPixelBuffer, orientation: Tracking.CameraOrientation) -> [SendableSpeaker] {
            // get tracks
            let tracks = tracker.update(pixelBuffer: pixelBuffer, orientation: orientation)
            
            var output: [SendableSpeaker] = []
            output.reserveCapacity(tracks.count)
            
            // update videos
            for track in tracks where track.rect.width.isNaN == false {
                let score = self.videoTracks[track.id, default: self.makeTrack(atTime: time, track: track)]
                    .updateVideoAndGetLastScore(atTime: time, from: pixelBuffer, with: track)
                
                output.append(.init(track: track,
                                    score: score,
                                    mirrored: orientation.isMirrored))
            }
            
            self.videoTracks = self.videoTracks.filter { _, videoTrack in
                videoTrack.lastUpdateTime >= time
            }
            
            return output
        }
        
        public func updateTracksAndGetFrames(atTime time: Double, from pixelBuffer: CVPixelBuffer) -> [UUID : MLMultiArray] {
            // get tracks
            let tracks = self.tracker.update(pixelBuffer: pixelBuffer)
            
            var updatedFrames: [UUID : MLMultiArray] = [:]
            updatedFrames.reserveCapacity(tracks.count)
            
            // update video tracks
            for track in tracks where track.rect.width.isNaN == false {
                updatedFrames[track.id] = self.videoTracks[track.id, default: self.makeTrack(atTime: time, track: track)]
                    .updateTrackAndGetFrames(atTime: time, from: pixelBuffer, with: track)
            }
            
            self.videoTracks = self.videoTracks.filter { _, speaker in
                speaker.lastUpdateTime >= time
            }
            
            return updatedFrames
        }
        
        public func updateScoresAndGetSpeakers(atTime time: Double, with scores: [UUID : MLMultiArray], orientation: Tracking.CameraOrientation) -> [SendableSpeaker] {
            var output: [SendableSpeaker] = []
            output.reserveCapacity(self.videoTracks.count)
            
            for (id, score) in scores {
                if let videoTrack = self.videoTracks[id] {
                    videoTrack.scoreBuffer.write(from: score, count: 5)
                    output.append(.init(track: videoTrack.track,
                                        score: videoTrack.scoreBuffer[-1],
                                        mirrored: orientation.isMirrored))
                }
            }
            
            self.scoreTimestamps.write(atTime: time, count: 5)
            
            return output
        }
        
        // MARK: Getter methods
        public func getScores(atTime time: Double?) -> [UUID : Float] {
            let index = self.scoreTimestamps.indexOf(time ?? self.lastScoreTime)
            return Dictionary(uniqueKeysWithValues: self.videoTracks.map { id, speaker in
                (id, speaker.scoreBuffer.read(at: index))
            })
        }
        
        // MARK: Private helpers
        @inline(__always)
        private func makeTrack(atTime time: Double, track: Tracking.SendableTrack) -> VideoTrack {
            return .init(atTime: time,
                         track: track,
                         videoBufferPadding: self.videoBufferPadding,
                         scoreBufferCapacity: asdVideoLength + self.scoreBufferPadding)
        }
    }
}
