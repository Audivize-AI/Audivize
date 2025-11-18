//
//  FrameHistoryTests.swift
//  AudivizeTests
//
//  Created by Benjamin Lee on 11/17/25.
//

import XCTest
@testable import Audivize

final class FrameHistoryTests: XCTestCase {
    typealias FrameHistory = Pairing.ASD.FrameHistory
    func testHitStreak() {
        var history = FrameHistory()
        XCTAssertEqual(history.hitStreak, 0)
        
        for _ in 0..<12 {
            history.registerHit()
        }
        XCTAssertEqual(history.hitStreak, 12)
        history.registerMiss()
        XCTAssertEqual(history.hitStreak, 0)
        XCTAssertEqual(history.missStreak, 1)
        history.registerHit()
        XCTAssertEqual(history.hitStreak, 14)
    }
}
