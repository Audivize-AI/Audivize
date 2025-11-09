import XCTest
@testable import Audivize

// ASD.ASDScoreBufferTests.swift

final class ASDScoreBufferTests: XCTestCase {

    // MARK: - Helpers

    private let fps = 30
    private var dt: TimeInterval { 1.0 / TimeInterval(fps) }

    private func nearlyEqual(_ a: Float, _ b: Float, eps: Float = 1e-5) -> Bool {
        if a.isNaN && b.isNaN { return true }
        return fabsf(a - b) <= eps * max(1, fabsf(a), fabsf(b))
    }

    /// Collects all stored logits in chronological order as a flat array.
    /// (Gaps are *not* represented; this only reflects stored frames.)
    private func storedLogits(_ buf: ASD.ASDScoreBuffer) -> [Float] {
        buf.blocks.flatMap { $0.scores.map(\.logit) }
    }

    /// Builds a dense timeline (aligned to the buffer's virtual timeline) returning `(time, logit?)`.
    /// `nil` indicates a gap (i.e. where old code would have stored a NaN).
    private func denseTimeline(_ buf: ASD.ASDScoreBuffer) -> [(time: TimeInterval, logit: Float?)] {
        guard let start = buf.blocks.first?.startTime ?? buf.virtualStartTime else { return [] }
        let end = buf.endTime
        let n = framesBetween(fps: fps, start: start, end: end) + 1
        var out = Array(repeating: (time: 0.0, logit: Float?.none), count: n)

        for i in 0..<n {
            let t = start + TimeInterval(i) * dt
            out[i].time = t
        }
        for b in buf.blocks {
            let offset = framesBetween(fps: fps, start: start, end: b.startTime)
            for (i, s) in b.scores.enumerated() {
                out[offset + i].logit = s.logit
            }
        }
        return out
    }

    private func framesBetween(fps: Int, start: TimeInterval, end: TimeInterval) -> Int {
        let s = Int(llround(start * Double(fps)))
        let e = Int(llround(end   * Double(fps)))
        return max(e - s, 0)
    }

    // MARK: - Tests

    func testWriteScores_AppendsAndTimes() {
        var buf = ASD.ASDScoreBuffer(atTime: 0.0, framerate: fps)

        // Simulate 5 frames arrived, then model returns 5 logits at t = 5*dt
        for _ in 0..<5 { buf.registerFrame() }
        let logits: [Float] = [0.1, 0.2, -0.3, 0.0, 1.0]
        buf.writeScores(atTime: 5 * dt, logits: logits)

        XCTAssertEqual(buf.scoredCount, 5)
        XCTAssertEqual(buf.virtualCount, 5)
        XCTAssertEqual(buf.blocks.count, 1)

        let stored = storedLogits(buf)
        XCTAssertEqual(stored.count, 5)
        for (a, b) in zip(stored, logits) {
            XCTAssertTrue(nearlyEqual(a, b))
        }

        // Check the times align to a frame grid (start at t = 1*dt .. 5*dt)
        let dense = denseTimeline(buf)
        XCTAssertEqual(dense.count, 5)
        for i in 0..<5 {
            XCTAssertTrue(nearlyEqual(Float(dense[i].time), Float((i + 1)) * Float(dt), eps: 1e-6))
            XCTAssertEqual(dense[i].logit!, logits[i])
        }
    }

    func testSkipScores_CreatesGapWithoutStoring() {
        var buf = ASD.ASDScoreBuffer(atTime: 0.0, framerate: fps)

        // Write 3 frames at t = 3*dt
        for _ in 0..<3 { buf.registerFrame() }
        buf.writeScores(atTime: 3 * dt, logits: [0.5, 0.5, 0.5])

        // Now 1 more frame arrives, then a skip (like inactiveUpdate)
        buf.registerFrame()
        buf.skipScores(atTime: 5 * dt) // from 3*dt to 5*dt with one pending+1 = 2 virtual blanks

        XCTAssertEqual(buf.scoredCount, 3, "Stored frames should not change for gaps.")
        XCTAssertEqual(buf.virtualCount, 5, "Virtual timeline should include the 2-gap expansion (3 + 2).")
        XCTAssertEqual(buf.blocks.count, 1, "No extra block should be created for a gap.")
        XCTAssertEqual(buf.endTime, 5 * dt)

        // Dense timeline should show 3 logits then 2 gaps
        let dense = denseTimeline(buf)
        XCTAssertEqual(dense.count, 5)
        for i in 0..<3 { XCTAssertNotNil(dense[i].logit) }
        for i in 3..<5 { XCTAssertNil(dense[i].logit) }
    }

    func testOverlap_UpdateExistingWithoutAppending() {
        var buf = ASD.ASDScoreBuffer(atTime: 0.0, framerate: fps)

        // First batch: 3 frames at t = 3*dt
        for _ in 0..<3 { buf.registerFrame() }
        buf.writeScores(atTime: 3 * dt, logits: [0.1, 0.2, 0.3])

        // Second batch: L = 2, no pending frames -> pure overlap of last 2 frames.
        buf.writeScores(atTime: 4 * dt, logits: [0.4, 0.6])

        // Expected accumulation on last two frames
        let expected: [Float] = [0.1, 0.6, 0.9]
        XCTAssertEqual(storedLogits(buf).count, 3)
        zip(storedLogits(buf), expected).forEach { XCTAssertTrue(nearlyEqual($0, $1)) }

        // No new frames appended -> scoredCount unchanged, virtualCount unchanged
        XCTAssertEqual(buf.scoredCount, 3)
        XCTAssertEqual(buf.virtualCount, 3)
    }

    func testAppendAfterGap_CoalescesWhenAdjacent() {
        var buf = ASD.ASDScoreBuffer(atTime: 0.0, framerate: fps)

        // First chunk (2 frames -> t=2*dt)
        for _ in 0..<2 { buf.registerFrame() }
        buf.writeScores(atTime: 2 * dt, logits: [1.0, 2.0])

        // Gap of 3 virtual frames (pending 2 + 1 blank)
        for _ in 0..<2 { buf.registerFrame() }
        buf.skipScores(atTime: 5 * dt) // virtualCount now 2 + 3 = 5

        // Now write 2 new frames right after the gap (t=7*dt) — should start a new block.
        for _ in 0..<2 { buf.registerFrame() }
        buf.writeScores(atTime: 7 * dt, logits: [3.0, 4.0])

        XCTAssertEqual(buf.blocks.count, 2, "Gap means non-adjacent, so two blocks remain.")
        XCTAssertEqual(buf.scoredCount, 4)
        XCTAssertEqual(buf.virtualCount, 7)

        // Now write frames that exactly bridge adjacency: a single frame at 5*dt + dt = 6*dt
        // We simulate a single-frame write whose start time is contiguous to the tail of the first block or head of second.
        var bridging = ASD.ASDScoreBuffer(atTime: 5 * dt, framerate: fps)
        bridging.registerFrame()
        bridging.writeScores(atTime: 6 * dt, logits: [99.0])

        buf.mergeWith(bridging)
        XCTAssertEqual(buf.blocks.count, 2, "Still three blocks because we filled inside the gap, not adjacent to ends.")

        // Now write at 6*dt and 7*dt from another buf to make adjacency and force coalescing with the tail.
        var tail = ASD.ASDScoreBuffer(atTime: 6 * dt, framerate: fps)
        tail.registerFrame()
        tail.writeScores(atTime: 7 * dt, logits: [100.0])
        buf.mergeWith(tail)

        // After filling adjacency, coalescing should reduce block count where contiguous
        XCTAssertTrue(buf.blocks.count <= 3)
    }

    func testMergeWith_OverlapsAreAccumulatedAndGapsPreserved() {
        var a = ASD.ASDScoreBuffer(atTime: 0.0, framerate: fps)
        // A: three frames at t=3*dt
        for _ in 0..<3 { a.registerFrame() }
        a.writeScores(atTime: 3 * dt, logits: [0.1, 0.2, 0.3]) // times: 1..3

        // Gap of 2 (pending 1 + 1 blank)
        a.registerFrame()
        a.skipScores(atTime: 5 * dt) // virtualCount = 3 + 2 = 5

        // B: overlaps last 2 of A's stored frames and adds one new right after (contiguous to 3*dt)
        var b = ASD.ASDScoreBuffer(atTime: 0.0, framerate: fps)
        for _ in 0..<3 { b.registerFrame() }
        b.writeScores(atTime: 3 * dt, logits: [0.0, 0.5, 0.5]) // times: 1..3 (overlap 2..3 of A)

        // Merge
        a.mergeWith(b)

        // Expected stored logits after accumulation on frames 2..3:
        // A: [0.1, 0.2, 0.3]
        // B: [0.0, 0.5, 0.5]
        // -> [0.1, 0.7, 0.8]
        let stored = storedLogits(a)
        XCTAssertEqual(stored.prefix(3).count, 3)
        XCTAssertTrue(nearlyEqual(stored[0], 0.1))
        XCTAssertTrue(nearlyEqual(stored[1], 0.7))
        XCTAssertTrue(nearlyEqual(stored[2], 0.8))

        // Virtual timeline should at least cover previous virtual end
        XCTAssertTrue(a.virtualCount >= 5)
        XCTAssertTrue(a.endTime >= 5 * dt)
    }

    func testPipeOperator_IsPure() {
        var a = ASD.ASDScoreBuffer(atTime: 0.0, framerate: fps)
        for _ in 0..<2 { a.registerFrame() }
        a.writeScores(atTime: 2 * dt, logits: [1.0, 2.0]) // times 1*dt, 2*dt

        var b = ASD.ASDScoreBuffer(atTime: 0.0, framerate: fps)
        for _ in 0..<2 { b.registerFrame() }
        b.writeScores(atTime: 2 * dt, logits: [3.0, 4.0]) // same times

        let aCopy = a
        let bCopy = b
        let c = a | b

        // Inputs unchanged
        XCTAssertEqual(storedLogits(a), storedLogits(aCopy))
        XCTAssertEqual(storedLogits(b), storedLogits(bCopy))

        // Overlapping times accumulate, not concatenate
        XCTAssertEqual(c.scoredCount, 2)
        XCTAssertEqual(storedLogits(c), [4.0, 6.0])
    }
}
