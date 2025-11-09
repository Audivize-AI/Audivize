//
//  ScoreTimeline.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/8/25.
//

import Foundation
import DequeModule

extension ASD {
    struct ScoreStream: Sendable {
        enum ScoreStreamError: Error {
            case writeFailedOutdatedSegment
        }
        
        // MARK: - ScoreStream attributes
        
        public private(set) var segments: [ScoreSegment]    /// Score segments

        public let maxFrameDeviation: Int = 2               /// Maximum frame index deviation before a resync
        public let startTime: TimeInterval                  /// Stream start timestamp
                
        /// Timestamp of last score
        public var endTime: TimeInterval {
            guard let duration = segments.last?.endTime else { return startTime }
            return startTime + duration
        }
        
        private var numMisses: Int = 0
        private var frameIndex: Int
        private var endIndex: Int { segments.last?.endIndex ?? 0 }
        
        // MARK: - Init
        
        public init(atTime time: TimeInterval, segments: [ScoreSegment]? = nil) {
            self.startTime = time
            self.frameIndex = Self.getFrameIndex(forTime: time)
            self.segments = segments ?? [ScoreSegment(startIndex: frameIndex)]
        }
        
        // MARK: - Public methods
        
        /// Register the occurrence of a new frame at a given time. Resynchronize timestamps if necessary and create a new segment or stretch back the current one to handle more extreme deviations.
        /// - Parameter time: The current timestamp
        public mutating func registerNewFrame(atTime time: TimeInterval) {
            frameIndex += 1
            
            resynchronizeFrameIndex(atTime: time)
            
            // Extend segment front & try merging if the frame has rewinded signficantly
            if let segmentStartIndex = segments.last?.startIndex, frameIndex < segmentStartIndex {
                segments[segments.count-1].extendFront(by: segmentStartIndex - frameIndex)
                while segments.count > 1 && segments[segments.count-2].tryMerge(segments[segments.count-1]) {
                    segments.removeLast()
                }
                numMisses = 0
            } else {
                // Add new segment if it's a new video track or a massive time skip occurred
                let framesSinceLastUpdate = frameIndex - endIndex
                if numMisses > 0 || framesSinceLastUpdate > ASD.ASDModel.videoLength {
                    segments.append(ScoreSegment(startIndex: frameIndex))
                }
                numMisses = 0
            }
        }
        
        /// Register the occurrence of a new frame at a given time in which the owner of this score stream is out of frame. Resynchronize timestamps if necessary.
        /// - Parameter time: The current timestamp
        public mutating func registerMissedFrame(atTime time: TimeInterval) {
            frameIndex += 1
            let deviation = resynchronizeFrameIndex(atTime: time)
            numMisses += 1 + deviation
        }
        
        /// Write new scores to the stream
        /// - Parameter logits: The score logits to write
        /// - Throws: `writeFailedOutdatedSegment` if the segment is somehow outdated (this should never happen).
        public mutating func writeScores(logits: [Float]) throws {
            precondition(!segments.isEmpty)
            
            // Don't write logits for blank frames
            let numValidLogits = logits.count - numMisses
            guard numValidLogits > 0 else {
                return
            }
            
            // Ensure that the last segment is not outdated
            let segmentEndIndex = endIndex
            let logitsStartIndex = frameIndex - logits.count
            
            guard logitsStartIndex <= segmentEndIndex else {
                throw ScoreStreamError.writeFailedOutdatedSegment
            }
            
            // Update the last segment with the new logits
            segments[segments.count-1].extend(with: logits.prefix(numValidLogits),
                                              to: frameIndex - numMisses)
        }
        
        /// Find the segment containing a given timestamp
        public func getSegment(forTime time: TimeInterval) -> (index: Int, segment: ScoreSegment)? {
            let frameIndex = Self.getFrameIndex(forTime: time)
            
            var mid: Int
            var low: Int = 0
            var high: Int = segments.count - 1
            
            while low < high {
                mid = (low + high) / 2
                let segment = segments[mid]
                
                if segment > frameIndex {
                    high = mid - 1
                } else if segment < frameIndex {
                    low = mid + 1
                } else {
                    return (mid, segment)
                }
            }
            return nil
        }
        
        /// Find the range of segments that intersect a given time interval
        /// - Parameters:
        ///   - startTime: Interval start time
        ///   - endTime: Interval end time
        /// - Returns: The indices of the first and last segment and the array slice of segments if found
        public func getSegments(fromTime startTime: TimeInterval, toTime endTime: TimeInterval) -> (startIndex: Int, endIndex: Int, segments: ArraySlice<ScoreSegment>)? {
            
            guard startTime < endTime else { return nil }
            guard !segments.isEmpty else { return nil }
            
            let startFrame = Self.getFrameIndex(forTime: startTime)
            let endFrame = Self.getFrameIndex(forTime: endTime)
            
            guard let low = segments.firstIndex(where: {$0.endIndex > startFrame}),
                  let high = segments.lastIndex(where: {$0.startIndex <= endFrame})
            else {
                return nil
            }
            
            return (low, high, segments[low...high])
        }
        
        /// Ensure the segments are in the correct order and are non-overlapping.
        public mutating func repair() {
            if !validateSegments() {
                segments.sort { $0.startsBefore($1) }
                reduceSegments()
            }
        }
        
        // MARK: - Private helpers
        
        /// Realign timestamps if they deviate too much
        /// - Returns: The frame deviation
        @discardableResult
        private mutating func resynchronizeFrameIndex(atTime time: TimeInterval) -> Int {
            let expectedFrameIndex = Self.getFrameIndex(forTime: time)
            let deviation = expectedFrameIndex - frameIndex
            if abs(deviation) > maxFrameDeviation {
                debugPrint("WARNING: Skipping ahead in score stream due to timestamp mismatch (\(expectedFrameIndex) != \(frameIndex))")
                frameIndex = expectedFrameIndex
                return deviation
            }
            return 0
        }
        
        /// Merge all overlapping segments
        private mutating func reduceSegments() {
            guard segments.count > 1 else { return }
            let endIndex = segments.count - 1
            
            for i in (0..<endIndex).reversed() {
                if segments[i].tryMerge(segments[i+1]) {
                    segments.remove(at: i+1)
                }
            }
        }
        
        /// Check if all segments are ordered correctly and nonoverlapping
        private func validateSegments() -> Bool {
            guard segments.count > 1 else { return true }
            let endIndex = segments.count - 1
            
            for i in (0..<endIndex) {
                if !(segments[i] < segments[i+1]) {
                    return false
                }
            }
            return true
        }
        
        /// Convert timestamp into a frame index
        private static func getFrameIndex(forTime time: TimeInterval) -> Int {
            return Int(round(time) * ASDConfiguration.frameRate)
        }
    }
}
