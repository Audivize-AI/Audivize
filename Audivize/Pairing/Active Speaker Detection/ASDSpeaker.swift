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


extension Pairing.ASD {
    class VisualSpeaker: Identifiable {
        typealias ASDModel = ASDConfiguration.ASDModel
        
        public enum Status {
            case inactive   /// Inactive
            case pairing    /// Pairing with a voice
            case paired     /// Paired with a voice
        }
        
        /// VisualSpeaker ID
        public let id: UUID
        /// Name
        public var name: String
        /// Permanence flag
        public var isPermanent: Bool = false
        
        /// Visual embedding vector
        public private(set) var embedding: [Float]
        /// Bounding box
        public private(set) var rect: CGRect
        /// Status
        public private(set) var status: Status
        /// Current Track ID
        public private(set) var trackId: UUID?
        /// Speaker scores
        public private(set) var scores: ScoreStream
        /// ASD Buffer
        public private(set) var asdBuffer: ASDBuffer? = nil
        /// Whether the track missed last time
        public private(set) var wasTrackMissed: Bool
        
        /// Timestamp of first score
        public var startTime: TimeInterval { scores.startTime }
        /// Timestamp of last score
        public var endTime: TimeInterval { scores.endTime }
        /// Total duration on-camera
        public var duration: TimeInterval { scores.duration }
        /// Whether a video buffer is assigned to this speaker
        public var hasASDBuffer: Bool { asdBuffer != nil }
        ///
        /// Number of consecutive missed frames
        public var numMisses: Int { asdBuffer?.frameHistory.missStreak ?? 0 }
        
        /// Whether this speaker should be deleted
        public var isDeletable: Bool {
            !isPermanent && numMisses < ASDConfiguration.deletionAge
        }
        
        private let asdManager: ASDManager
        private var frameIndex: Int { asdManager.frameIndex }
        
        public init(track: Tracking.SendableTrack, videoManager: ASDManager) {
            self.id = UUID()
            self.name = track.name ?? "Speaker \(id.uuidString.prefix(4))"
            self.trackId = track.id
            self.embedding = track.embedding
            self.rect = track.rect
            self.status = .pairing
            self.scores = .init(atFrame: videoManager.frameIndex)
            self.asdManager = videoManager
            self.wasTrackMissed = track.misses > 0
        }
        
        deinit {
            debugPrint("Deinitialized VisualSpeaker with ID: \(id)")
            // recycle the VideoBuffer
            if let asdBuffer {
                asdManager.recycle(asdBuffer)
            } else {
                asdManager.cancelReservation(for: id)
            }
        }
        
        public func getSendable(isMirrored: Bool = false) -> SendableVisualSpeaker {
            .init(id: id,
                  name: name,
                  rect: rect,
                  scores: scores,
                  status: status,
                  isPermanent: isPermanent,
                  embedding: embedding,
                  wasTrackMissed: wasTrackMissed,
                  isMirrored: isMirrored)
        }
        
        /// Add a new frame
        /// - Parameters:
        ///   - pixelBuffer: Source pixel buffer
        ///   - track: Track state
        ///   - drop: Whether to drop the frame for framerate reduction
        public func registerNewFrame(from pixelBuffer: CVPixelBuffer, track: Tracking.SendableTrack, drop: Bool) throws {
            // ensure the track ID is the same
            guard updateWithTrack(track) else { return }
            
            // try to add the frame to the video buffer
            if self.asdBuffer == nil {
                self.asdBuffer = asdManager.requestASDBuffer(for: id)
            }
            try asdBuffer?.writeFrame(from: pixelBuffer,
                                      croppedTo: track.rect,
                                      isMiss: track.misses > 0,
                                      drop: drop)
            
            while let newLogits = asdBuffer?.popNewLogits() {
                try scores.writeScores(from: newLogits)
            }
        }
        
        /// Update videoBuffer with a blank frame.
        /// Used when the speaker is out of frame or inactive
        /// - Parameters:
        ///   - track: Track state
        ///   - drop: Whether to drop the frame for framerate reduction
        public func registerMissedFrame(drop: Bool) throws {
            self.trackId = nil
            self.rect = .null
            self.status = .inactive
            
            // Update scores
            while let newLogits = asdBuffer?.popNewLogits() {
                try scores.writeScores(from: newLogits)
            }
            
            // add blank frame
            asdBuffer?.skipFrame(drop: drop)
            
            guard !drop else { return }
            
            // free video buffer if it's been inactive for long enough
            if !hasASDBuffer {
                asdManager.cancelReservation(for: id)
            } else if let asdBuffer, asdBuffer.isEmpty {
                asdManager.recycle(asdBuffer)
                self.asdBuffer = nil
            }
        }
        
        /// Merge another visual speaker into this one
        /// - Parameter other: The other `VisualSpeaker`
        /// - Note: This speaker should NOT be active (i.e., it should not have a `VideoBuffer` assigned to it).
        public func absorb(_ other: SendableVisualSpeaker) {
            // ensure both speakers are nonempty
            guard !(self.scores.isEmpty || other.scores.isEmpty) else {
                debugPrint("ERROR: VisualSpeaker.mergeWith called with 2 empty speakers")
                return
            }
            
            // Don't absorb a permanent speaker
            guard !other.isPermanent else {
                debugPrint("ERROR: VisualSpeaker cannot absorb a permanent visual speaker")
                return
            }
            
            // Ensure that this speaker is inactive
            guard !self.hasASDBuffer else {
                debugPrint("ERROR: VisualSpeaker.mergeWith called on an active speaker")
                return
            }
             
            self.scores.absorb(other.scores)
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
        public func isSimilarTo(track: Tracking.SendableTrack, threshold: Float = Tracking.TrackingConfiguration.maxAppearanceCost) -> Bool {
            return Utils.ML.cosineDistance(from: track.embedding, to: self.embedding) <= threshold
        }
        
        /// Check if this speaker matches another speaker's embedding
        /// - Parameters:
        ///    - speaker: The speaker being compared
        ///    - threshold: Maximum cosine distance for a match
        /// - Returns: `true` if it's a match, `false` if not
        public func isSimilarTo(speaker: SendableVisualSpeaker, threshold: Float = Tracking.TrackingConfiguration.maxAppearanceCost) -> Bool {
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
            self.wasTrackMissed = track.misses > 0
            self.rect = track.rect
            if let name = track.name {
                self.name = name
            }
            return true
        }
    }
    
    struct SendableVisualSpeaker: Sendable, Identifiable, Hashable, Equatable {
        let id: UUID
        let name: String
        let rect: CGRect
        let scores: ScoreStream
        let status: VisualSpeaker.Status
        let isPermanent: Bool
        let embedding: [Float]
        let wasTrackMissed: Bool
        
        /// Timestamp of first score
        var startTime: TimeInterval { scores.startTime }
        /// Timestamp of last score
        var endTime: TimeInterval { scores.endTime }
        /// Total duration on-camera
        var duration: TimeInterval { scores.endTime - scores.startTime }
        /// Whether this speaker is currently speaking
        var isSpeaking: Bool { scores.last?.isActive == true }
        
        /// Display string
        var displayString: String {
            "\(self.name) \(isSpeaking ? "🗣 " : "")- \(String(format: "%.1f", self.duration))s\nSegments: \(self.scores.segments.count)\nScores: \(self.scores.count)"
        }
        
        init(id: UUID, name: String, rect: CGRect, scores: ScoreStream, status: VisualSpeaker.Status, isPermanent: Bool, embedding: [Float], wasTrackMissed: Bool, isMirrored: Bool) {
            self.id = id
            self.name = name
            self.scores = scores
            self.status = status
            self.isPermanent = isPermanent
            self.embedding = embedding
            self.wasTrackMissed = wasTrackMissed
            
            if isMirrored {
                self.rect = rect
            } else {
                self.rect = .init(x: 1 - rect.maxX,
                                  y: rect.minY,
                                  width: rect.width,
                                  height: rect.height)
            }
            
            debugPrint(self.scores)
        }
        
        public static func ==(lhs: SendableVisualSpeaker, rhs: SendableVisualSpeaker) -> Bool {
            return lhs.id == rhs.id
        }
        
        public func hash(into hasher: inout Hasher) {
            return hasher.combine(self.id)
        }
    }
}
