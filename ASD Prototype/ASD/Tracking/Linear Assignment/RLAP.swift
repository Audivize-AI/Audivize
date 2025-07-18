//
//  LAP.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/17/25.
//

import Foundation
import RLAP

extension ASD.Tracking {
    @usableFromInline
    @discardableResult
    static func solveRLAP(
        dims: (Int, Int),
        cost: [Float],
        rows: inout [Int],
        cols: inout [Int],
        maximize: Bool = false
    ) -> Int {
        rows = [Int](repeating: 0, count: dims.0)
        cols = [Int](repeating: 0, count: dims.1)
        
        // Some very safe code the definitely won't cause segfaults :)
        return solve_rlapf(
            dims.0,
            dims.1,
            cost.withUnsafeBufferPointer { $0.baseAddress! },
            maximize,
            rows.withUnsafeMutableBufferPointer { $0.baseAddress! },
            cols.withUnsafeMutableBufferPointer { $0.baseAddress! }
        )
    }
    
    @usableFromInline
    @discardableResult
    static func solveRLAP(
        dims: (Int, Int),
        cost: [Double],
        rows: inout [Int],
        cols: inout [Int],
        maximize: Bool = false
    ) -> Int {
        rows = [Int](repeating: 0, count: dims.0)
        cols = [Int](repeating: 0, count: dims.1)
        
        // Some very safe code the definitely won't cause segfaults :)
        return solve_rlap(
            dims.0,
            dims.1,
            cost.withUnsafeBufferPointer { $0.baseAddress! },
            maximize,
            rows.withUnsafeMutableBufferPointer { $0.baseAddress! },
            cols.withUnsafeMutableBufferPointer { $0.baseAddress! }
        )
    }
}
