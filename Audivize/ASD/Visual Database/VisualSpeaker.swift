//
//  VisualSpeaker.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/6/25.
//

import Foundation
import AVFoundation
import DequeModule
import CoreML


extension ASD {
    
    class VisualSpeaker: Identifiable {
        public enum Status {
            case inactive   /// Inactive
            case pairing    /// Pairing with a voice
            case paired     /// Paired with a voice
        }
        
        public let id: UUID                                     /// VisualSpeaker ID
        public var isPermanent: Bool = false                    /// Permanence flag
        
        public private(set) var embedding: [Float]              /// Visual embedding vector
        public private(set) var rect: CGRect                    /// Bounding box
        public private(set) var status: Status                  /// Status
        public private(set) var trackId: UUID?                  /// Current Track ID
        public private(set) var scores: ScoreStream             /// Speaker scores
        public private(set) var videoBuffer: VideoBuffer? = nil /// Video Buffer for ASD
        
        public var videoFrames: MLMultiArray? { videoBuffer?.read(at: -1) } /// VideoBuffer frames
        public var startTime: TimeInterval { scores.startTime } /// Timestamp of first score
        public var endTime: TimeInterval { scores.endTime }     /// Timestamp of last score
        public var hasVideoBuffer: Bool { videoBuffer != nil }  /// Whether a video buffer is assigned to this speaker
        public var duration: TimeInterval { scores.duration }   /// Total duration on-camera
        
        public var needsASDUpdate: Bool {
            guard let slot = videoBuffer?.slot else { return false }
            return slot == videoBufferPool.asdSchedulePhase
        }
        
        private var videoBufferPool: VideoBufferPool
        private var asdUpdateQueue: [UUID : Int] /// Update ID -> Frame Index
        
        public init(atTime time: TimeInterval, from track: Tracking.SendableTrack, videoBufferPool: VideoBufferPool) {
            self.id = UUID()
            self.trackId = track.id
            self.embedding = track.embedding
            self.rect = track.rect
            self.status = .pairing
            self.scores = .init(atTime: time)
            self.videoBufferPool = videoBufferPool
            self.asdUpdateQueue = [:]
        }
        
        deinit {
            debugPrint("Deinitialized VisualSpeaker with ID: \(id)")
            // recycle the VideoBuffer
            if let videoBuffer {
                videoBufferPool.recycle(videoBuffer)
            } else {
                videoBufferPool.cancelReservation(for: id)
            }
        }
        
        /// Add a new frame
        /// - Parameters:
        ///   - pixelBuffer: Source pixel buffer
        ///   - track: Track state
        ///   - skip: Whether to skip the frame for framerate reduction
        public func addFrame(atTime time: TimeInterval, from pixelBuffer: CVPixelBuffer, track: Tracking.SendableTrack, skip: Bool) {
            // ensure the track ID is the same
            guard updateWithTrack(track) else { return }
            
            // try to add the frame to the video buffer
            if self.videoBuffer == nil {
                self.videoBuffer = videoBufferPool.requestVideoBuffer(for: id)
            }
            videoBuffer?.write(from: pixelBuffer, croppedTo: track.rect, skip: skip)
            
            if !skip {
                self.scores.registerNewFrame(atTime: time)
            }
        }
        
        /// Update videoBuffer with a blank frame.
        /// Used when the speaker is out of frame or inactive
        /// - Parameters:
        ///   - track: Track state
        ///   - skip: Whether to skip the frame for framerate reduction
        public func inactiveUpdate(atTime time: TimeInterval, skip: Bool) {
            self.trackId = nil
            self.rect = .null
            self.status = .inactive
            
            // add blank frame
            videoBuffer?.writeBlankFrame(skip: skip)
            
            guard !skip else { return }
            
            // free video buffer if it's been inactive for long enough
            if !hasVideoBuffer {
                videoBufferPool.cancelReservation(for: id)
            } else if let videoBuffer, videoBuffer.isBlank {
                videoBufferPool.recycle(videoBuffer)
                self.videoBuffer = nil
            }
            
            // update scores
            self.scores.registerMissedFrame(atTime: time)
        }
        
        /// Enqueue an ASD update.
        /// - Returns: ID for the update
        public func enqueueASDUpdate() -> UUID {
            let updateID = UUID()
            self.asdUpdateQueue[updateID] = self.scores.frameIndex
            return updateID
        }
        
        /// Update ASD scores
        /// - Parameters:
        ///   - id: ASD update ID
        ///   - logits: ASD prediction logits
        public func updateScores(from id: UUID, with logits: [Float]) throws {
            guard let frameIndex = asdUpdateQueue.removeValue(forKey: id) else {
                return
            }
            try scores.writeScores(logits, fromFrame: frameIndex)
        }
        
        /// Merge the visual speaker with another one.
        /// - Parameter other: The other `VisualSpeaker`
        /// - Note: `other` should not be marked as permanent.
        /// - Note: `other` should start after this speaker.
        /// - Note: `other` should be deleted after the merge
        /// - Note: This speaker should NOT be active (i.e., it should not have a `VideoBuffer` assigned to it).
        public func mergeWith(_ other: VisualSpeaker) {
            // ensure both speakers are nonempty
            guard !(self.scores.isEmpty || other.scores.isEmpty) else {
                debugPrint("ERROR: VisualSpeaker.mergeWith called with 2 empty speakers")
                return
            }
            
            // Ensure that this speaker is inactive
            guard !self.hasVideoBuffer else {
                debugPrint("ERROR: VisualSpeaker.mergeWith called on an active speaker")
                return
            }
            
            // ensure that the other speaker is NOT permanent
            guard !other.isPermanent else {
                debugPrint("ERROR: VisualSpeaker.mergeWith called with a permanent other speaker")
                return
            }
            
            // ensure that this speaker is older
            guard self.startTime < other.startTime && other.endTime <= self.endTime else {
                debugPrint("ERROR: VisualSpeaker.mergeWith: the speaker's timestamps do not contain all of the other speaker's timestamps")
                return
            }
            
            self.scores.mergeWith(other.scores)
        }
        
        /// Check if this speaker matches an embedding
        /// - Parameters:
        ///    - embedding: 512D face embedding vector
        ///    - threshold: Maximum cosine distance for a match
        /// - Returns: `true` if it's a match, `false` if not
        public func isSimilarTo(embedding: [Float], threshold: Float = Tracking.TrackingConfiguration.maxAppearanceCost) -> Bool {
            return Utils.ML.cosineDistance(from: embedding, to: self.embedding) <= threshold
        }
        
        /// Check if this speaker matches a track's embedding
        /// - Parameters:
        ///    - track: The track being compared
        ///    - threshold: Maximum cosine distance for a match
        /// - Returns: `true` if it's a match, `false` if not
        public func isSimilarTo(track: Tracking.Track, threshold: Float = Tracking.TrackingConfiguration.maxAppearanceCost) -> Bool {
            return Utils.ML.cosineDistance(from: track.embedding, to: self.embedding) <= threshold
        }
        
        /// Check if this speaker matches another speaker's embedding
        /// - Parameters:
        ///    - speaker: The speaker being compared
        ///    - threshold: Maximum cosine distance for a match
        /// - Returns: `true` if it's a match, `false` if not
        public func isSimilarTo(speaker: VisualSpeaker, threshold: Float = Tracking.TrackingConfiguration.maxAppearanceCost) -> Bool {
            return Utils.ML.cosineDistance(from: speaker.embedding, to: self.embedding) <= threshold
        }
        
        /// - Returns: `true` if the track is the correct one, `false` if not
        private func updateWithTrack(_ track: Tracking.SendableTrack) -> Bool {
            guard trackId == nil || track.id == self.trackId else {
                debugPrint("ERROR: VisualSpeaker.updateWithTrack called with a different track ID")
                return false
            }
            self.trackId = track.id
            self.embedding = track.embedding
            self.rect = track.rect
            return true
        }
    }
}
