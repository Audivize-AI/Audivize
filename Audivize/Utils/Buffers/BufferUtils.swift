//
//  BufferUtils.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/27/25.
//

import Foundation

extension Utils {
    @inline(__always)
    static func wrapIndex(_ index: Int, start startIndex: Int, end endIndex: Int, capacity: Int) -> Int {
        let idx = index + (index < 0 ? endIndex : startIndex)
        return (idx >= 0)
            ? idx
            : idx + capacity
    }
    
    @inline(__always)
    static func wrapRange(_ range: Range<Int>, start startIndex: Int, end endIndex: Int, capacity: Int) -> Range<Int> {
        return wrapRange(range.lowerBound, range.upperBound, start: startIndex, end: endIndex, capacity: capacity)
    }
    
    @inline(__always)
    static func wrapClosedRange(_ range: ClosedRange<Int>, start startIndex: Int, end endIndex: Int, capacity: Int) -> ClosedRange<Int> {
        return wrapClosedRange(range.lowerBound, range.upperBound, start: startIndex, end: endIndex, capacity: capacity)
    }
    
    @inline(__always)
    static func wrapRange(_ lower: Int, _ upper: Int, start startIndex: Int, end endIndex: Int, capacity: Int) -> Range<Int> {
        let (lo, hi) = wrapRangeBounds(lower, upper, start: startIndex, end: endIndex, capacity: capacity)
        return lo..<hi
    }
    
    @inline(__always)
    static func wrapClosedRange(_ lower: Int, _ upper: Int, start startIndex: Int, end endIndex: Int, capacity: Int) -> ClosedRange<Int> {
        let (lo, hi) = wrapRangeBounds(lower, upper, start: startIndex, end: endIndex, capacity: capacity)
        return lo...hi
    }
    
    @inline(__always)
    static func wrapRangeBounds(_ lower: Int, _ upper: Int, start startIndex: Int, end endIndex: Int, capacity: Int) -> (lower: Int, upper: Int) {
        var lo: Int
        var hi: Int
        
        if lower < 0 {
            lo = lower + endIndex
            hi = upper + endIndex
        } else {
            lo = lower + startIndex
            hi = upper + startIndex
        }
        
        if lo < 0 { lo += capacity }
        if hi < 0 { hi += capacity }
        return (lo, hi)
    }
    
    @inline(__always)
    static func advance_index(_ index: inout Int, by increment: Int, wrapTo startIndex: Int, wrapAt endIndex: Int) {
        index += increment
        if index >= endIndex {
            index = startIndex
        }
    }
    
    @inline(__always)
    static func advance_index(_ index: inout Int, by increment: Int, modulo modulus: Int) {
        index += increment
        if index >= modulus {
            index = 0
        }
    }
}
