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
        public private(set) var endTime: TimeInterval           /// Timestamp of last score
        public private(set) var scores: Deque<Score>            /// Speaker scores
        public private(set) var videoBuffer: VideoBuffer? = nil /// Video Buffer for ASD
        
        public var videoFrames: MLMultiArray? { videoBuffer?.read(at: -1) }
        public var hasVideoBuffer: Bool { videoBuffer != nil }
        public var startTime: TimeInterval { endTime - duration }
        
        public var duration: TimeInterval {
            Double(scores.count - 1) / Double(ASDConfiguration.frameRate)
        }
        
        public var needsASDUpdate: Bool {
            guard let slot = videoBuffer?.slot else { return false }
            return slot == videoBufferPool.asdSchedulePhase
        }
        
        public var numFinalizedScores: Int {
            max(scores.count - ASDConfiguration.ASDModel.videoLength + ASDConfiguration.framesPerUpdate - 1, 0)
        }
        
        private var numUnscoredFrames: Int = 0
        private var videoBufferPool: VideoBufferPool
        
        public init(atTime time: TimeInterval, from track: Tracking.SendableTrack, videoBufferPool: VideoBufferPool) {
            self.id = UUID()
            self.trackId = track.id
            self.embedding = track.embedding
            self.rect = track.rect
            self.status = .pairing
            self.endTime = time
            self.scores = []
            self.videoBufferPool = videoBufferPool
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
        public func addFrame(from pixelBuffer: CVPixelBuffer, track: Tracking.SendableTrack, skip: Bool) {
            // ensure the track ID is the same
            guard updateWithTrack(track) else { return }
            
            // try to add the frame to the video buffer
            if self.videoBuffer == nil {
                self.videoBuffer = videoBufferPool.requestVideoBuffer(for: id)
            }
            videoBuffer?.write(from: pixelBuffer, croppedTo: track.rect, skip: skip)
            
            if !skip {
                self.numUnscoredFrames += 1
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
            // NOTE: This behaves as if numUnscoredFrames were incremented by 1 then reset to 0 after the score is added
            if self.numUnscoredFrames == 0 {
                self.scores.append(.nan)
            } else {
                let blankScores = [Score](repeating: .nan, count: self.numUnscoredFrames+1)
                self.scores.append(contentsOf: blankScores)
                self.numUnscoredFrames = 0
            }
            
            self.endTime = time
        }
        
        /// Update ASD scores
        /// - Parameters:
        ///   - time: Timestamp of ASD inference call
        ///   - logits: ASD prediction logits
        public func updateScores(atTime time: TimeInterval, with logits: [Float]) {
            guard time > endTime else {
                debugPrint("ERROR: VisualSpeaker.updateScores called with a non-increasing time \(time) ≤ \(endTime)")
                return
            }
            
            let numOverlap = max(min(logits.count - numUnscoredFrames, scores.count), 0)
            
            // framerate sanity check
            let fps = TimeInterval(numUnscoredFrames) / (time - endTime)
            if fabs(fps - TimeInterval(ASDConfiguration.frameRate)) > 1.0 {
                debugPrint("WARNING: VisualSpeaker.updateScores called with mismatched framerate: \(fps) != \(ASDConfiguration.frameRate)")
            }
            
            // update old scores
            let overlapStartIndex = scores.count - numOverlap
            for i in 0..<numOverlap {
                scores[overlapStartIndex+i].update(with: logits[i])
            }
            
            // add new scores
            scores.append(contentsOf: logits[numOverlap...].map{ Score.init($0) })
            
            numUnscoredFrames = 0
            endTime = time
        }
        
        /// Clear finalized scores
        /// - Returns: The timestamp of the last finalized score and the finalized scores that were removed
        public func clearFinalizedScores() -> (endTime: TimeInterval, scores: Deque<Score>) {
            // get finalized scores
            let numFinalizedScores = numFinalizedScores
            guard numFinalizedScores > 0 else {
                return (startTime, Deque([]))
            }
            let finalizedScores = Deque(scores.prefix(numFinalizedScores))
            scores.removeFirst(numFinalizedScores)
            
            // get finalized timestamp
            let durationFinalized = TimeInterval(numFinalizedScores - 1) / TimeInterval(ASDConfiguration.frameRate)
            let finalizedTime = endTime - durationFinalized
            
            return (finalizedTime, finalizedScores)
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
            
            let otherStartIndexInSelf = self.getScoreIndex(forTime: other.startTime)
            var overlapWithOther = other.getScoreIndex(forTime: self.endTime) + 1
            
            if other.hasVideoBuffer {
                // transfer the video buffer
                self.videoBuffer = other.videoBuffer
                other.videoBuffer = nil
                
                // Remove all trailing NaN scores from this speaker that overlap with or succeed the other speaker
                let lastKeptIndex = self.scores.lastIndex(where: \.logit.isFinite) ?? 0
                let lastIndex = self.scores.count - 1
                let numCut = min(lastIndex - lastKeptIndex, overlapWithOther)
                self.scores.removeLast(numCut)
                overlapWithOther -= numCut
            } else if videoBufferPool.hasReservation(for: other.id) {
                // transfer the spot in line for the video buffer
                videoBufferPool.replaceReservation(for: other.id, with: self.id)
            }
            
            // Add trailing scores
            var overlappingScores: Slice<Deque<Score>> = other.scores[...]
            
            if overlapWithOther < other.scores.count {
                let addedScores = other.scores.suffix(from: overlapWithOther)
                self.scores.append(contentsOf: addedScores)
                overlappingScores = other.scores.prefix(overlapWithOther)
                
                self.numUnscoredFrames = other.numUnscoredFrames
                self.endTime = other.endTime
            }
            
            for (i, score) in overlappingScores.enumerated() {
                self.scores[i + otherStartIndexInSelf].update(with: score.logit, replaceNan: true)
            }
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
        
        private func getScoreIndex(forTime time: TimeInterval) -> Int {
            let fps = Double(ASDConfiguration.frameRate)
            let lastIndex = scores.count - 1
            let deltaFrames = (endTime - time) * fps
            let index = lastIndex - Int(round(deltaFrames))
            return min(max(index, 0), lastIndex)
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
