//
//  ASDScoreBuffer.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/7/25.
//

import Foundation

extension ASD {
    /// Stores ASD scores in contiguous, non-overlapping blocks keyed by time.
    /// Blocks are coalesced automatically when they become adjacent.
    /// No NaNs are stored; gaps are implicit (by time).
    struct ASDScoreBuffer: Sendable {
        
        // MARK: - Nested Types
        
        @usableFromInline
        struct Block: Sendable {
            /// Timestamp for the first score in this block (aligned to the frame grid).
            var startTime: TimeInterval
            /// Scores in order; the last score time is `startTime + (count - 1)/fps`.
            var scores: [Score]
            
            @inline(__always)
            var count: Int { scores.count }
            
            @inline(__always)
            func endTime(fps: Int) -> TimeInterval {
                startTime + duration(fps: fps)
            }
            
            @inline(__always)
            func duration(fps: Int) -> TimeInterval {
                count > 0 ? Double(count - 1) / Double(fps) : 0.0
            }
        }
        
        // MARK: - Storage
        
        /// Sorted by time; non-overlapping contiguous blocks only.
        public private(set) var blocks: [Block] = []
        
        /// Number of frames since the most recent ASD inference registered by `registerFrame()`.
        public private(set) var numUnscoredFrames: Int = 0
        
        /// Timestamp of the last call that advanced time (`writeScores` or `skipScores`).
        public private(set) var endTime: TimeInterval
        
        /// Frames per second used to map times to frame indices.
        public let framerate: Int
        
        /// Count of actually stored scores (sum of block lengths).
        public private(set) var scoredCount: Int = 0
        
        /// "Virtual length" of the timeline (what `scores.count` used to be when NaNs were appended).
        /// We keep this to maintain the exact overlap semantics of `VisualSpeaker.updateScores`.
        public private(set) var virtualCount: Int = 0
        
        // MARK: - Init
        init(atTime time: TimeInterval, framerate: Int = Int(ASDConfiguration.frameRate)) {
            self.endTime = TimeInterval(0) / TimeInterval(llround(time * TimeInterval(framerate)))
            self.framerate = framerate
        }
        
        // MARK: - Framerate Validation Helpers

        /// Helper to check if the observed number of frames matches the expected, with tolerance.
        @inline(__always)
        private func shouldWarnFPS(delta: TimeInterval, pendingFrames: Int) -> Bool {
            // No time advanced or no frames expected: don't warn
            if delta <= 0 { return false }
            // Expected frames for the elapsed time
            let expected = Int((delta * Double(framerate)).rounded())
            // Allow a tolerance of +/- 1 frame to account for timer jitter
            return abs(expected - pendingFrames) > 1
        }

        @inline(__always)
        private func fpsExpectation(delta: TimeInterval) -> Int {
            max(Int((delta * Double(framerate)).rounded()), 0)
        }

        // MARK: - Public API
        
        /// Merge the other buffer into `self`, adding overlapping logits and filling gaps by inserting new frames.
        /// Blocks are merged/elided as needed to ensure non-overlapping contiguous storage.
        mutating func mergeWith(_ other: Self) {
            // Preconditions: same fps and both buffers aligned to the same frame grid.
            precondition(self.framerate == other.framerate, "Merging buffers with different framerates is unsupported")

            // Fast path: empty cases
            if other.blocks.isEmpty { return }
            if self.blocks.isEmpty {
                // Adopt other's blocks directly.
                self.blocks = other.blocks
                self.scoredCount = other.blocks.reduce(0) { $0 + $1.count }
                self.endTime = max(self.endTime, other.endTime)
                // Recompute virtualCount to cover the union timeline.
                if let startA = self.virtualStartTime, let startB = other.virtualStartTime {
                    let start = min(startA, startB)
                    virtualCount = framesBetween(start: start, end: endTime) + 1
                } else if let start = other.virtualStartTime {
                    virtualCount = framesBetween(start: start, end: endTime) + 1
                }
                return
            }

            // Ultra-fast path: `other` is entirely after (or exactly contiguous with) our tail.
            @inline(__always)
            func startFrame(of b: Block) -> Int64 { frameIndex(for: b.startTime) }
            @inline(__always)
            func endFrame(of b: Block) -> Int64 { startFrame(of: b) + Int64(b.count) - 1 }

            if let lastSelf = self.blocks.last, let firstOther = other.blocks.first {
                let tailEnd = endFrame(of: lastSelf)
                let headStart = startFrame(of: firstOther)
                if headStart >= tailEnd { // >= allows same-last-frame overlap handling below
                    var firstIndex = 0
                    // If exactly contiguous (tailEnd + 1 == headStart), extend our last block first.
                    if tailEnd + 1 == headStart {
                        var dst = self.blocks[self.blocks.count - 1]
                        let len = firstOther.count
                        dst.scores.reserveCapacity(dst.scores.count + len)
                        var i = 0
                        while i < len {
                            dst.scores.append(firstOther.scores[i])
                            i &+= 1
                        }
                        self.blocks[self.blocks.count - 1] = dst
                        self.scoredCount &+= len
                        firstIndex = 1
                    } else if headStart == tailEnd {
                        // Overlap by exactly one frame: accumulate that single frame, then treat the rest as contiguous.
                        let offset = lastSelf.count - 1
                        self.blocks[self.blocks.count - 1].scores[offset].update(with: firstOther.scores[0].logit, replaceNan: true)
                        if firstOther.count > 1 {
                            var dst = self.blocks[self.blocks.count - 1]
                            let len = firstOther.count - 1
                            dst.scores.reserveCapacity(dst.scores.count + len)
                            var i = 1
                            while i < firstOther.count {
                                dst.scores.append(firstOther.scores[i])
                                i &+= 1
                            }
                            self.blocks[self.blocks.count - 1] = dst
                            self.scoredCount &+= len
                        }
                        firstIndex = 1
                    }

                    // Append remaining other blocks as-is (no insert shifting)
                    if firstIndex < other.blocks.count {
                        self.blocks.reserveCapacity(self.blocks.count + (other.blocks.count - firstIndex))
                        var j = firstIndex
                        while j < other.blocks.count {
                            self.blocks.append(other.blocks[j])
                            self.scoredCount &+= other.blocks[j].count
                            j &+= 1
                        }
                    }

                    // Update endTime and virtualCount to cover the union
                    if other.endTime > self.endTime { self.endTime = other.endTime }
                    if let startA = self.virtualStartTime, let startB = other.virtualStartTime {
                        let start = min(startA, startB)
                        virtualCount = framesBetween(start: start, end: endTime) + 1
                    } else if let start = self.virtualStartTime {
                        virtualCount = framesBetween(start: start, end: endTime) + 1
                    } else if let start = other.virtualStartTime {
                        virtualCount = framesBetween(start: start, end: endTime) + 1
                    }

                    return
                }
            }

            // Helpers to get frame indices for blocks
            // (startFrame(of:) and endFrame(of:) already declared above for this function scope)

            // Lower bound: first index in self.blocks whose startFrame >= target
            @inline(__always)
            func lowerBound(byStartFrame target: Int64) -> Int {
                var lo = 0, hi = self.blocks.count
                while lo < hi {
                    let mid = (lo + hi) >> 1
                    if startFrame(of: self.blocks[mid]) < target {
                        lo = mid + 1
                    } else {
                        hi = mid
                    }
                }
                return lo
            }

            // Merge each block of `other` in one pass, handling gaps and overlaps against self.blocks.
            var oi = 0
            while oi < other.blocks.count {
                let ob = other.blocks[oi]
                var f = startFrame(of: ob)
                let ofEnd = f + Int64(ob.count) - 1
                var opos = 0

                // Find insertion point relative to current self blocks
                var si = lowerBound(byStartFrame: f)

                // Try to extend the previous self block if exactly contiguous on the left.
                if si > 0 {
                    let prevIdx = si - 1
                    let prevEnd = endFrame(of: self.blocks[prevIdx])
                    if prevEnd + 1 == f {
                        // Extend previous block up to just before the next self block (if any) or to the end of the other block.
                        let nextStart = (si < self.blocks.count) ? startFrame(of: self.blocks[si]) : Int64.max
                        let len = Int(min(ofEnd, nextStart - 1) - f + 1)
                        if len > 0 {
                            var dst = self.blocks[prevIdx]
                            dst.scores.reserveCapacity(dst.scores.count + len)
                            var i = 0
                            while i < len {
                                dst.scores.append(ob.scores[opos + i])
                                i &+= 1
                            }
                            self.blocks[prevIdx] = dst
                            self.scoredCount &+= len
                            f &+= Int64(len)
                            opos &+= len
                            // If we became adjacent to the next block, coalesce now.
                            if f == nextStart, si < self.blocks.count {
                                tryCoalesce(prevIdx, si)
                            }
                        }
                    }
                }

                // Main loop: process remaining part of `ob`
                while f <= ofEnd {
                    // If we ran out of self blocks or the next self block starts after our current frame -> GAP: insert new block.
                    if si >= self.blocks.count || startFrame(of: self.blocks[si]) > f {
                        let nextStart = (si < self.blocks.count) ? startFrame(of: self.blocks[si]) : Int64.max
                        let len = Int(min(ofEnd + 1, nextStart) - f)
                        // Insert a new block at `si`
                        var arr: [Score] = []
                        arr.reserveCapacity(len)
                        var i = 0
                        while i < len {
                            arr.append(ob.scores[opos + i])
                            i &+= 1
                        }
                        let newBlock = Block(startTime: timeForFrame(f), scores: arr)
                        self.blocks.insert(newBlock, at: si)
                        self.scoredCount &+= len
                        // Try coalesce with previous if exactly adjacent
                        if si > 0 { tryCoalesce(si - 1, si) }
                        // Advance
                        f &+= Int64(len)
                        opos &+= len
                        si &+= 1
                        continue
                    }

                    // Overlap with self.blocks[si]
                    let sb = self.blocks[si]
                    let sStart = startFrame(of: sb)
                    let sEnd = endFrame(of: sb)
                    // If current frame is still before this block's start (shouldn't happen due to check above), skip.
                    if f < sStart {
                        continue
                    }
                    // overlap length
                    let len64 = min(ofEnd, sEnd) - f + 1
                    let len = Int(len64)
                    if len > 0 {
                        let offsetInSelf = Int(f - sStart)
                        var i = 0
                        // accumulate logits
                        while i < len {
                            self.blocks[si].scores[offsetInSelf + i].update(with: ob.scores[opos + i].logit, replaceNan: true)
                            i &+= 1
                        }
                        f &+= len64
                        opos &+= len
                    }
                    // If we've exhausted this self block, move to next
                    if f > sEnd { si &+= 1 }
                }

                oi &+= 1
            }

            // Update endTime to cover the union.
            if other.endTime > self.endTime { self.endTime = other.endTime }

            // Recompute virtualCount from virtual starts (union of timelines).
            if let startA = self.virtualStartTime, let startB = other.virtualStartTime {
                let start = min(startA, startB)
                virtualCount = framesBetween(start: start, end: endTime) + 1
            } else if let start = self.virtualStartTime {
                virtualCount = framesBetween(start: start, end: endTime) + 1
            } else if let start = other.virtualStartTime {
                virtualCount = framesBetween(start: start, end: endTime) + 1
            }
        }
        
        /// Write logits at a given absolute time, mirroring `VisualSpeaker.updateScores`.
        mutating func writeScores(atTime time: TimeInterval, logits: [Float]) {
            let t = canonicalizeTime(time)
            guard t > endTime else {
                debugPrint("ERROR: ScoreBuffer.writeScores called with a non-increasing time \(t) ≤ \(endTime)")
                return
            }
            guard !logits.isEmpty else {
                // still advance time sanity if desired; aligning to VS behavior we only advance on skip/write
                return
            }

#if DEBUG
            let delta = t - endTime
            if shouldWarnFPS(delta: delta, pendingFrames: numUnscoredFrames) {
                let expected = fpsExpectation(delta: delta)
                debugPrint("WARNING: ScoreBuffer.writeScores frames mismatch: pending=\(numUnscoredFrames) expected≈\(expected) over Δt=\(delta)s @\(framerate)fps")
            }
#endif
            let L = logits.count
            
            // Maintain overlap semantics from VisualSpeaker:
            // numOverlap = clamp(L - numUnscoredFrames, 0...virtualCount)
            let rawOverlap = L - numUnscoredFrames
            let numOverlap = max(min(rawOverlap, virtualCount), 0)
            
            // In the older representation, the last (virtualCount - scoredCount) entries are trailing NaNs.
            // Overlap that would have hit those NaNs should have no effect.
            let trailingBlanks = max(virtualCount - scoredCount, 0)
            let dropFromTail = min(numOverlap, trailingBlanks)
            let overlapStored = numOverlap - dropFromTail
            
            // Apply overlap oldest -> newest with a single forward pass (no temp arrays)
            if overlapStored > 0 && scoredCount > 0 {
                // Global index (over stored frames) where the overlap starts.
                // Stored frames are all scores across blocks in chronological order.
                let firstOverlapIdx = scoredCount - overlapStored
                var globalIdx = 0
                var k = 0 // logits index (oldest -> newest)

                for bi in blocks.indices {
                    // Fast skip whole blocks before the overlap
                    let blockCount = blocks[bi].count
                    let nextGlobal = globalIdx + blockCount
                    if nextGlobal <= firstOverlapIdx {
                        globalIdx = nextGlobal
                        continue
                    }

                    // This block contributes to the overlap: start within the block at:
                    var startInBlock = max(0, firstOverlapIdx - globalIdx)
                    // Apply until the end of the block or until we've consumed all overlap
                    while startInBlock < blockCount && k < overlapStored {
                        blocks[bi].scores[startInBlock].update(with: logits[k])
                        startInBlock &+= 1
                        k &+= 1
                    }

                    globalIdx = nextGlobal
                    if k >= overlapStored { break }
                }
            }

            // 2) Append new scores (the last L - numOverlap logits)
            let newCount = L - numOverlap
            if newCount > 0 {
                let dt = frameDuration
                // First new frame time = t - (newCount - 1)/fps
                let startT = canonicalizeTime(t - Double(newCount - 1) * dt)
                appendContiguously(startTime: startT, logits: logits, startIndex: numOverlap, count: newCount)
                scoredCount += newCount
                virtualCount += newCount
            }
            
            numUnscoredFrames = 0
            endTime = t
            coalesceNeighborsAroundTail()
        }
        
        /// Register a missing video frame (like `VisualSpeaker.addFrame(skip:false)`).
        mutating func registerFrame() {
            numUnscoredFrames &+= 1
        }
        
        /// Advance time and record a run of blanks (like `inactiveUpdate(skip:false)`),
        /// but represented as an implicit gap (no NaNs stored).
        mutating func skipScores(atTime time: TimeInterval) {
            let t = canonicalizeTime(time)
            guard t > endTime else {
                // Be lenient: do nothing if non-increasing.
                debugPrint("WARNING: ScoreBuffer.skipScores called with non-increasing time \(t) ≤ \(endTime)")
                return
            }

#if DEBUG
            let delta = t - endTime
            if shouldWarnFPS(delta: delta, pendingFrames: numUnscoredFrames) {
                let expected = fpsExpectation(delta: delta)
                debugPrint("WARNING: ScoreBuffer.skipScores frames mismatch: pending=\(numUnscoredFrames) expected≈\(expected) over Δt=\(delta)s @\(framerate)fps")
            }
#endif

            // In the old representation, we would have appended (numUnscoredFrames + 1) NaNs.
            virtualCount &+= (numUnscoredFrames + 1)
            numUnscoredFrames = 0
            endTime = t
            // No changes to blocks/scoredCount; the gap is implicit.
        }
        
        /// Pure (non-mutating) merge operator.
        static func |(a: Self, b: Self) -> Self {
            var out = a
            out.mergeWith(b)
            return out
        }
        
        // MARK: - Private Helpers
        
        @inline(__always)
        private var frameDuration: TimeInterval {
            1.0 / TimeInterval(framerate)
        }
        
        /// Frame index with rounding (same spirit as VisualSpeaker.getScoreIndex).
        @inline(__always)
        private func frameIndex(for time: TimeInterval) -> Int64 {
            Int64(llround(time * TimeInterval(framerate)))
        }
        
        @inline(__always)
        private func timeForFrame(_ frame: Int64) -> TimeInterval {
            TimeInterval(frame) / TimeInterval(framerate)
        }
        
        @inline(__always)
        private func framesBetween(start: TimeInterval, end: TimeInterval) -> Int {
            let s = frameIndex(for: start)
            let e = frameIndex(for: end)
            return max(Int(e - s), 0)
        }
        
        /// Clamp times onto the frame grid to avoid drift.
        @inline(__always)
        private func canonicalizeTime(_ t: TimeInterval) -> TimeInterval {
            timeForFrame(frameIndex(for: t))
        }
        
        /// Virtual timeline start time, if any:
        /// endTime - (virtualCount-1)/fps when we have a non-empty virtual timeline.
        public var virtualStartTime: TimeInterval? {
            guard virtualCount > 0 else { return nil }
            return endTime - Double(virtualCount - 1) * frameDuration
        }
        
        /// Append a batch of logits that are known to be consecutive (by time) starting at `startTime`.
        private mutating func appendContiguously(startTime: TimeInterval, logits: [Float]) {
            guard !logits.isEmpty else { return }

            let startF = frameIndex(for: startTime)
            let canonicalStart = timeForFrame(startF)

            // If the last block ends exactly one frame before this start, extend it; else add a new block.
            if let last = blocks.indices.last {
                let lastEndF = frameIndex(for: blocks[last].endTime(fps: framerate))
                if lastEndF + 1 == startF {
                    // Extend last block with reserved capacity and avoid building a temporary array
                    var dst = blocks[last]
                    dst.scores.reserveCapacity(dst.scores.count + logits.count)
                    for v in logits { dst.scores.append(Score(v)) }
                    blocks[last] = dst
                    return
                }
            }

            var arr: [Score] = []
            arr.reserveCapacity(logits.count)
            for v in logits { arr.append(Score(v)) }
            blocks.append(Block(startTime: canonicalStart, scores: arr))
        }

        /// Append a subrange of a logits buffer without allocating a temporary array.
        private mutating func appendContiguously(startTime: TimeInterval, logits: [Float], startIndex: Int, count: Int) {
            if count <= 0 { return }
            let startF = frameIndex(for: startTime)
            let canonicalStart = timeForFrame(startF)
            if let last = blocks.indices.last {
                let lastEndF = frameIndex(for: blocks[last].endTime(fps: framerate))
                if lastEndF + 1 == startF {
                    var dst = blocks[last]
                    dst.scores.reserveCapacity(dst.scores.count + count)
                    var i = 0
                    while i < count {
                        dst.scores.append(Score(logits[startIndex + i]))
                        i &+= 1
                    }
                    blocks[last] = dst
                    return
                }
            }
            var arr: [Score] = []
            arr.reserveCapacity(count)
            var i = 0
            while i < count {
                arr.append(Score(logits[startIndex + i]))
                i &+= 1
            }
            blocks.append(Block(startTime: canonicalStart, scores: arr))
        }
        
        /// Merge a single score at an exact frame time.
        private mutating func mergeOne(at time: TimeInterval, score: Score) {
            let f = frameIndex(for: time)
            let canonicalT = timeForFrame(f)
            
            // Binary search for the block that could contain `f` or where it should be inserted.
            var lo = 0, hi = blocks.count
            while lo < hi {
                let mid = (lo + hi) >> 1
                let b = blocks[mid]
                let startF = frameIndex(for: b.startTime)
                let endF = startF + Int64(b.count) - 1
                if f < startF {
                    hi = mid
                } else if f > endF {
                    lo = mid + 1
                } else {
                    // Inside block `mid`
                    let idx = Int(f - startF)
                    var s = blocks[mid].scores[idx]
                    s.update(with: score.logit)
                    blocks[mid].scores[idx] = s
                    return
                }
            }
            // Not inside any block; `lo` is the insertion index.
            let insertAt = lo
            
            // Try to append to previous block if contiguous.
            if insertAt > 0 {
                let prevIdx = insertAt - 1
                let prevEndF = frameIndex(for: blocks[prevIdx].endTime(fps: framerate))
                if prevEndF + 1 == f {
                    blocks[prevIdx].scores.append(score)
                    // If now contiguous with the next block, coalesce.
                    if insertAt < blocks.count {
                        tryCoalesce(prevIdx, insertAt)
                    }
                    scoredCount &+= 1
                    return
                }
            }
            
            // Try to prepend to next block if contiguous.
            if insertAt < blocks.count {
                let nextStartF = frameIndex(for: blocks[insertAt].startTime)
                if f + 1 == nextStartF {
                    blocks[insertAt].startTime = canonicalT
                    blocks[insertAt].scores.insert(score, at: 0)
                    scoredCount &+= 1
                    return
                }
            }
            
            // Otherwise, insert a new single-score block.
            blocks.insert(Block(startTime: canonicalT, scores: [score]), at: insertAt)
            scoredCount &+= 1
        }
        
        /// Attempt to coalesce neighboring blocks if they have become adjacent.
        private mutating func tryCoalesce(_ left: Int, _ right: Int) {
            guard left >= 0, right < blocks.count, left < right else { return }
            let leftEndF = frameIndex(for: blocks[left].endTime(fps: framerate))
            let rightStartF = frameIndex(for: blocks[right].startTime)
            if leftEndF + 1 == rightStartF {
                // Merge right into left
                blocks[left].scores.append(contentsOf: blocks[right].scores)
                blocks.remove(at: right)
            }
        }
        
        /// Coalesce only near the tail (fast path after appends).
        private mutating func coalesceNeighborsAroundTail() {
            guard blocks.count >= 2 else { return }
            tryCoalesce(blocks.count - 2, blocks.count - 1)
        }
        
        /// Full coalesce sweep (used after large merges).
        private mutating func coalesceNeighborsAroundAll() {
            guard blocks.count >= 2 else { return }
            var i = 0
            while i + 1 < blocks.count {
                let mergedCount = blocks.count
                tryCoalesce(i, i + 1)
                if blocks.count < mergedCount {
                    // Stay on same i because current right moved into left.
                } else {
                    i += 1
                }
            }
        }
    }
}
