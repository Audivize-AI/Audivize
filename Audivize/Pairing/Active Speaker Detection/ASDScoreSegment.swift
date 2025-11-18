//
//  ScoreSegment.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/8/25.
//

import Foundation
import DequeModule


extension Pairing.ASD {
    struct ScoreSegment: Sendable, Sequence, MutableCollection {
        typealias Element = Score
        
        enum ScoreSegmentError: Error {
            case mergeFailedNoAdjacentScores
            case intersectionFailedNoIntersection
        }
        
        /// Scores
        public private(set) var scores: ContiguousArray<Score>
        
        /// Segment start frame index
        public private(set) var startIndex: Int
        
        /// Segment end frame index (i.e., the index after the last element's index)
        public var endIndex: Int { startIndex + scores.count }
        
        /// Number of scores in the segment
        public var count: Int { scores.count }
        
        /// First score in the segment
        public var first: Score? { scores.first }
        
        /// Whether the segment is empty
        public var isEmpty: Bool { scores.isEmpty }
        
        /// Start timestamp
        public var startTime: TimeInterval {
            Double(startIndex) / ASDConfiguration.frameRate
        }
        
        /// End timestamp
        public var endTime: TimeInterval {
            (scores.count > 1) ? Double(endIndex - 1) / ASDConfiguration.frameRate : startTime
        }
        
        /// Segment duration
        public var duration: TimeInterval {
            (scores.count > 1) ? Double(scores.count - 1) / ASDConfiguration.frameRate : 0.0
        }
        
        // MARK: - Init
        public init(startIndex: Int, scores: ContiguousArray<Score> = []) {
            self.startIndex = startIndex
            self.scores = scores
        }
        
        public init(startIndex: Int, scores: Array<Score>) {
            self.startIndex = startIndex
            self.scores = ContiguousArray(scores)
        }
        
        // MARK: - Indexing
        
        public subscript(_ index: Int) -> Element {
            get { scores[index - startIndex] }
            set { scores[index - startIndex] = newValue }
        }
        
        public subscript(_ range: Range<Int>) -> ArraySlice<Element> {
            scores[(range.lowerBound - startIndex)..<(range.upperBound - startIndex)]
        }
        
        public subscript(_ range: ClosedRange<Int>) -> ArraySlice<Element> {
            scores[(range.lowerBound - startIndex)...(range.upperBound - startIndex)]
        }
    
        /// Get the next index
        public func index(after i: Int) -> Int {
            return i + 1
        }
        
        // MARK: - Timestamping
        
        /// Check if a timestamp falls in the score segment
        public func hasTime(_ time: TimeInterval) -> Bool {
            let index = getLocalIndex(forTime: time)
            return 0 <= index && index < self.count
        }
        
        /// Get the local index for a timestamp at a given frame rate
        public func getLocalIndex(forTime time: TimeInterval) -> Int {
            return Self.getFrameIndex(forTime: time) - self.startIndex
        }
        
        /// Get the aligned index for a timestamp at a given frame rate
        public static func getFrameIndex(forTime time: TimeInterval) -> Int {
            return Int(round(time * ASDConfiguration.frameRate))
        }
        
        // MARK: - Inserting and removing elements
        
        /// Append a new score
        public mutating func append(_ newElement: Element) {
            self.scores.append(newElement)
        }
        
        /// Append an array of new scores
        public mutating func append(contentsOf newElements: [Element]) {
            self.scores.append(contentsOf: newElements)
        }
        
        /// Append a new logit
        public mutating func append(_ newElement: Float) {
            self.scores.append(Score(newElement))
        }
        
        /// Append an array of new logits
        public mutating func append(contentsOf newElements: [Float]) {
            self.scores.append(contentsOf: newElements.map { Score($0) })
        }
        
        /// Extend the score segment by a certain length with new logits
        /// - Parameters:
        ///   - logits: Score logits
        ///   - count: Number of score by which to extend the score segment
        /// - Precondition: `count <= logits.count`
        public mutating func extend(with logits: any RandomAccessCollection<Float>, by count: Int) {
            
            let numOverlapping = logits.count - count
            let overlapStart = Swift.max(scores.count - numOverlapping, 0)
            
            guard overlapStart <= scores.count else {
                debugPrint("overlap out of bounds: \(overlapStart) > \(scores.count)")
                return
            }
            
            // update overlapping scores
            for i in overlapStart..<scores.count {
                scores[i].update(with: logits[_offset: i - overlapStart])
            }
            
            // add trailing scores
            guard count > 0 else { return }
            scores.append(contentsOf: logits.suffix(count).map { Score($0) })
        }
        
        /// Extend the score segment to a certain index with new logits
        /// - Parameters:
        ///   - logits: Score logits
        ///   - index: New end index
        /// - Precondition: `0 <= count <= logits.count`
        public mutating func extend(with logits: any RandomAccessCollection<Float>, to index: Int) {
            let count = index - endIndex
            extend(with: logits, by: count)
        }
        
        /// Move the front of the score buffer back by `count` frames
        public mutating func extendFront(by count: Int) {
            guard count > 0 else { return }
            self.startIndex -= count
            self.scores.insert(contentsOf: Array(repeating: Score(0), count: count), at: 0)
        }
        
        /// Remove the first score
        public mutating func removeFirst() -> Element? {
            self.startIndex += 1
            return self.scores.removeFirst()
        }
        
        /// Remove the first `k` scores
        public mutating func removeFirst(_ k: Int) {
            self.startIndex += k
            self.scores.removeFirst(k)
        }
        
        /// Remove the last score
        public mutating func removeLast() -> Element? {
            return self.scores.removeLast()
        }
        
        /// Remove the last `k` scores
        public mutating func removeLast(_ k: Int) {
            self.scores.removeLast(k)
        }
        
        // MARK: - Ordering checks
        
        /// Check if this score segment starts before another one
        public func startsBefore(_ other: ScoreSegment) -> Bool {
            return self.startIndex < other.startIndex
        }
        
        /// Check if this score segment starts after another one
        public func startsAfter(_ other: ScoreSegment) -> Bool {
            return self.startIndex > other.startIndex
        }
        
        /// Check if this score segment ends before another one
        public func endsBefore(_ other: ScoreSegment) -> Bool {
            return self.endIndex < other.endIndex
        }
        
        /// Check if this score segment ends after another one
        public func endsAfter(_ other: ScoreSegment) -> Bool {
            return self.endIndex > other.endIndex
        }
        
        /// Check if this entire score segment precedes another one
        public func precedes(_ other: ScoreSegment) -> Bool {
            return self.endIndex <= other.startIndex
        }
        
        /// Check if this entire score segment supercedes another one
        public func supercedes(_ other: ScoreSegment) -> Bool {
            return other.endIndex <= self.startIndex
        }
        
        /// Check if this score segment precedes or left-overlaps another one
        /// i.e., no scores come after the last score in the other segment.
        public func isLeftAligned(with other: ScoreSegment) -> Bool {
            return self.startIndex <= other.startIndex && self.endIndex <= other.endIndex
        }
        
        /// Check if this score segment supercedes or right-overlaps another one
        /// i.e., no scores come before the first score in the other segment.
        public func isRightAligned(with other: ScoreSegment) -> Bool {
            return self.startIndex >= other.startIndex && self.endIndex >= other.endIndex
        }
        
        /// Check if this score segment completely envelops another one
        public func envelops(_ other: ScoreSegment) -> Bool {
            return self.startIndex <= other.startIndex && self.endIndex >= other.endIndex
        }
        
        /// Check if this score segment is completely enveloped by another one
        public func isEnveloped(by other: ScoreSegment) -> Bool {
            return self.startIndex >= other.startIndex && self.endIndex <= other.endIndex
        }
        
        /// Check if this score segment intersects another one
        public func intersects(with other: ScoreSegment) -> Bool {
            return self.startIndex < other.endIndex && other.startIndex < self.endIndex
        }
        
        public func hasFrame(atIndex frameIndex: Int) -> Bool {
            return self.startIndex <= frameIndex && frameIndex < self.endIndex
        }
        
        // MARK: - Combining score segments
        
        /// Attempt to absorb another segment into this one. Will succeed iff they overlap.
        /// - Parameter other: The other score segment
        /// - Returns: `true` if successful, `false` if not
        public mutating func successfullyAbsorbed(_ other: ScoreSegment) -> Bool {
            let intersectionStart = Swift.max(self.startIndex, other.startIndex)
            let intersectionEnd = Swift.min(self.endIndex, other.endIndex)
            
            // check if merge is possible
            guard intersectionStart <= intersectionEnd else {
                return false
            }
            
            // update intersecting scores
            if intersectionStart < intersectionEnd {
                for i in intersectionStart..<intersectionEnd {
                    self[i].update(with: other[i].logit)
                }
            }
            
            // add other scores
            let intersectionCount = intersectionEnd - intersectionStart
            let unionCount = self.count + other.count - intersectionCount
            
            self.scores.reserveCapacity(unionCount)
            
            if self.startsAfter(other) {
                self.scores.insert(contentsOf: other.scores.prefix(intersectionStart-other.startIndex), at: 0)
                self.startIndex = other.startIndex
            }
            
            if self.endsBefore(other) {
                self.scores.append(contentsOf: other.scores.suffix(other.endIndex - intersectionEnd))
            }
            
            return true
        }
        
        /// Attempt to reduce this score buffer to its intersection with another one and update all the scores.
        /// - Parameter other: The other score segment
        /// - Returns: `true` if successful, `false` if not
        public mutating func successfullyKeptIntersection(with other: ScoreSegment) -> Bool {
            let intersectionStart = Swift.max(self.startIndex, other.startIndex)
            let intersectionEnd = Swift.min(self.endIndex, other.endIndex)
            
            // Ensure segments intersect
            guard intersectionStart != intersectionEnd else {
                self.scores.removeAll()
                self.startIndex = intersectionStart
                return true
            }
            guard intersectionStart < intersectionEnd else {
                return false
            }
            
            // update intersecting scores
            if intersectionStart < intersectionEnd {
                for i in intersectionStart..<intersectionEnd {
                    self[i].update(with: other[i].logit)
                }
            }
            
            // Trim scores
            if self.startsBefore(other) {
                self.scores.removeFirst(intersectionStart-self.startIndex)
                self.startIndex = other.startIndex
            }
            
            if self.endsAfter(other) {
                self.scores.removeLast(other.endIndex - intersectionEnd)
            }
            
            return true
        }
        
        /// Merge another segment into this one
        /// - Parameter other: The other score segment
        /// - Throws: `ScoreSegmentError.mergeFailedNoAdjacentScores` if unsuccessful (no intersection and non-adjacent)
        public mutating func absorb(_ other: ScoreSegment) throws {
            guard self.successfullyAbsorbed(other) else {
                throw ScoreSegmentError.mergeFailedNoAdjacentScores
            }
        }
        
        /// Reduce this score segment to its intersection with another one, updating all the overlapping scores
        /// - Parameter other: The other score segment
        /// - Throws: `ScoreSegmentError.intersectionFailedNoIntersection` if unsuccessful (no intersection)
        public mutating func keepIntersection(with other: ScoreSegment) throws {
            guard self.successfullyKeptIntersection(with: other) else {
                throw ScoreSegmentError.intersectionFailedNoIntersection
            }
        }
        
        /// - Returns: A copy of this score segment merged with another one, unless the merge failed
        public func union(with other: ScoreSegment) -> Self? {
            var result = self
            if result.successfullyAbsorbed(other) {
                return result
            }
            return nil
        }
        
        /// - Returns: A copy of this score segment's intersection with another one, unless the intersection failed
        public func intersection(with other: ScoreSegment) -> Self? {
            var result = self
            if result.successfullyKeptIntersection(with: other) {
                return result
            }
            return nil
        }
        
        // MARK: - Operators
        
        /// - Returns: The union of two score segments
        public static func | (lhs: ScoreSegment, rhs: ScoreSegment) -> Self? {
            lhs.union(with: rhs)
        }
        
        /// - Returns: The intersection of two score segments
        public static func & (lhs: ScoreSegment, rhs: ScoreSegment) -> Self? {
            return lhs.intersection(with: rhs)
        }
        
        /// Check if `lhs` precedes `rhs`
        public static func < (lhs: ScoreSegment, rhs: ScoreSegment) -> Bool {
            return lhs.precedes(rhs)
        }
        
        /// Check if `lhs` left-overlaps or precedes `rhs`
        public static func <= (lhs: ScoreSegment, rhs: ScoreSegment) -> Bool {
            return lhs.isLeftAligned(with: rhs)
        }
        
        /// Check if `lhs` supercedes `rhs`
        public static func > (lhs: ScoreSegment, rhs: ScoreSegment) -> Bool {
            return lhs.supercedes(rhs)
        }
        
        /// Check if `lhs` right-overlaps or supercedes `rhs`
        public static func >= (lhs: ScoreSegment, rhs: ScoreSegment) -> Bool {
            return lhs.isRightAligned(with: rhs)
        }
        
        /// Check if `lhs` precedes `rhs`
        public static func < (lhs: ScoreSegment, rhs: Int) -> Bool {
            return lhs.endIndex < rhs
        }
        
        /// Check if `lhs` left-overlaps or precedes `rhs`
        public static func <= (lhs: ScoreSegment, rhs: Int) -> Bool {
            return lhs.endIndex <= rhs
        }
        
        /// Check if `lhs` supercedes `rhs`
        public static func > (lhs: ScoreSegment, rhs: Int) -> Bool {
            return lhs.startIndex > rhs
        }
        
        /// Check if `lhs` right-overlaps or supercedes `rhs`
        public static func >= (lhs: ScoreSegment, rhs: Int) -> Bool {
            return lhs.startIndex >= rhs
        }
    }
}
