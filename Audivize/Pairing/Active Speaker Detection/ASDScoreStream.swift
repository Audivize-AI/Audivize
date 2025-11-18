//
//  ScoreTimeline.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/8/25.
//

import Foundation
import DequeModule
import BitCollections

extension Pairing.ASD {
    struct ScoreStream: Sendable {
        // MARK: - ScoreStream attributes
        
        /// Score segments
        public private(set) var segments: [ScoreSegment]
        
        /// Total on-screen duration
        public private(set) var duration: TimeInterval
        
        /// Stream start timestamp
        public var startTime: TimeInterval {
            segments.first?.startTime ?? 0
        }
        
        /// Timestamp of last score
        public var endTime: TimeInterval {
            segments.last?.endTime ?? startTime
        }
        
        public var count: Int { endIndex - startIndex + 1 }
        
        public var last: Score? { segments.last?.scores.last }
        
        /// Duration of all score segments combined
        
        /// Whether this is empty
        public var isEmpty: Bool { segments.isEmpty || segments.allSatisfy(\.isEmpty) }
        
        private var startIndex: Int { segments.first?.startIndex ?? 0 }
        private var endIndex: Int { segments.last?.endIndex ?? 0 }
        
        // MARK: - Init
        
        public init(atFrame frameIndex: Int, segments: [ScoreSegment] = []) {
            self.segments = segments
            self.duration = 0
            self.recalculateDuration()
        }
        
        // MARK: - Public methods
        
        /// Write new scores to the stream
        /// - Parameters:
        ///   - logits: The score logits to write and the data surrounding the frames
        /// - Throws: `writeFailedOutdatedSegment` if the segment is somehow outdated (this should never happen).
        public mutating func writeScores(from logits: ASDBuffer.LogitData) {
            // callFrame is the frame index of the last logit
            // first frame = callFrame - numLogits + 1
            let offset = logits.callFrame - ASDConfiguration.ASDModel.videoLength + 1
            
            var segmentIndex: Int = max(0, segments.count - 1)
            
            for chunk in logits.hitHistory.chunks.reversed() {
                let startFrame = chunk.lowerBound + offset
                let endFrame = chunk.upperBound + offset
                
                var segmentFound: Bool
                
                (segmentIndex, segmentFound) = findSegmentIndexFromBack(forFrame: startFrame, startingAt: segmentIndex)
                
                if segmentFound {
                    // extend the segment containing the start of the chunk
                    self.duration -= segments[segmentIndex].duration
                    segments[segmentIndex].extend(with: logits.logits, to: endFrame)
                } else {
                    // insert a new segment
                    var segment = ScoreSegment(startIndex: startFrame)
                    segment.extend(with: logits.logits, to: endFrame)
                    self.segments.insert(segment, at: segmentIndex)
                }
                
                // merge any segments that overlap
                while segmentIndex+1 < segments.count && segments[segmentIndex].successfullyAbsorbed(segments[segmentIndex+1]) {
                    duration -= segments.remove(at: segmentIndex+1).duration
                }
                duration += segments[segmentIndex].duration
            }
        }
        
        /// Merge another score stream into this one
        /// - Parameter other: The `ScoreStream` to absorb
        public mutating func absorb(_ other: ScoreStream) {
            // Handle empty streams
            guard !other.segments.isEmpty else {
                return
            }
            guard !segments.isEmpty else {
                self = other
                return
            }
            
            // Merge them together merge sort-style
            var mergedSegments: [ScoreSegment] = []
            mergedSegments.reserveCapacity(segments.count + other.segments.count)
            
            var lhsIndex = 0
            var rhsIndex = 0
            
            func appendOrMerge(_ segment: ScoreSegment) {
                if let lastIndex = mergedSegments.indices.last,
                   mergedSegments[lastIndex].successfullyAbsorbed(segment) {
                    return
                }
                mergedSegments.append(segment)
            }
            
            while lhsIndex < segments.count || rhsIndex < other.segments.count {
                let takeFromLhs: Bool
                
                switch (lhsIndex < segments.count, rhsIndex < other.segments.count) {
                case (true, false):
                    takeFromLhs = true
                case (false, true):
                    takeFromLhs = false
                case (true, true):
                    takeFromLhs = segments[lhsIndex].startsBefore(other.segments[rhsIndex])
                default:
                    preconditionFailure("Both streams exhausted while loop is still running")
                }
                
                if takeFromLhs {
                    appendOrMerge(segments[lhsIndex])
                    lhsIndex += 1
                } else {
                    appendOrMerge(other.segments[rhsIndex])
                    rhsIndex += 1
                }
            }
            
            // Update counters
            self.segments = mergedSegments
            self.recalculateDuration()
        }
        
        /// Find the segment containing a given timestamp
        /// - Parameter time: The timestamp
        /// - Returns: The segment's index and the segment if found
        public func findSegment(forTime time: TimeInterval) -> (index: Int, segment: ScoreSegment)? {
            let index = Self.getFrameIndex(forTime: time)
            return self.findSegment(forIndex: index)
        }
        
        /// Find the segment containing a given frame index
        /// - Parameter frameIndex: The frame index
        /// - Returns: The segment's index and the segment if found
        public func findSegment(forIndex frameIndex: Int) -> (index: Int, segment: ScoreSegment)? {
            var mid: Int
            var low: Int = 0
            var high: Int = segments.count - 1
            
            while low <= high {
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
        public func findSegments(fromTime startTime: TimeInterval, toTime endTime: TimeInterval) -> (startIndex: Int, endIndex: Int, segments: ArraySlice<ScoreSegment>)? {
            let start = Self.getFrameIndex(forTime: startTime)
            let end = Self.getFrameIndex(forTime: endTime)
            return self.findSegments(fromIndex: start, toIndex: end)
        }
        
        /// Find the range of segments that intersect a given frame interval
        /// - Parameters:
        ///   - start: Interval start frame index
        ///   - end: Interval end frame index
        /// - Returns: The indices of the first and last segment and the array slice of segments if found
        public func findSegments(fromIndex start: Int, toIndex end: Int) -> (startIndex: Int, endIndex: Int, segments: ArraySlice<ScoreSegment>)? {
            
            guard start < endIndex else { return nil }
            guard end > startIndex else { return nil }
            guard !segments.isEmpty else { return nil }
            
            guard let low = segments.firstIndex(where: {$0.endIndex > start}),
                  let high = segments.lastIndex(where: {$0.startIndex <= end})
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
        
        /// Merge all overlapping segments and recalculate duration
        private mutating func reduceSegments() {
            guard segments.count > 1 else { return }
            let endIndex = segments.count - 1
            
            for i in (0..<endIndex).reversed() {
                if segments[i].successfullyAbsorbed(segments[i+1]) {
                    segments.remove(at: i+1)
                }
            }
            
            recalculateDuration()
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
        
        private mutating func recalculateDuration() {
            duration = 0.0
            for segment in segments.dropLast() {
                duration += segment.duration
            }
        }
        
        private func findSegmentIndexFromBack(forFrame frameIndex: Int, startingAt maxIndex: Int? = nil) -> (index: Int, found: Bool) {
            var index = maxIndex ?? (segments.count - 1)
            guard index >= 0 && index < segments.count else {
                return (index, false)
            }
            
            while index > 0 && segments[index].startIndex > frameIndex {
                index -= 1
            }
            
            if segments[index].hasFrame(atIndex: frameIndex) {
                // found segment
                return (index, true)
            }
            if segments[index].startIndex <= frameIndex {
                // insert segment after `index`
                return (index+1, false)
            }
            // insert segment at `index`
            return (index, false)
        }
        
        /// Convert timestamp into a frame index
        private static func getFrameIndex(forTime time: TimeInterval) -> Int {
            return Int(round(time * ASDConfiguration.frameRate))
        }
    }
}
