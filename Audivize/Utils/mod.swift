//
//  mod.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/29/25.
//

import Foundation

extension Utils {
    @inline(__always)
    static func mod(_ a: Int, _ b: Int) -> Int {
        let floorAOverB = (a - b + 1) / b
        return a - floorAOverB * b
    }
    
    @inline(__always)
    static func wrap(_ x: Int, from a: Int, to b: Int) -> Int {
        return mod(x - a, b - a) + a
    }
    
    @inline(__always)
    static func mod(_ a: Float, _ b: Float) -> Float {
        return a - floor(a / b) * b
    }
    
    @inline(__always)
    static func wrap(_ x: Float, from a: Float, to b: Float) -> Float {
        return mod(x - a, b - a) + a
    }
    
    @inline(__always)
    static func mod(_ a: Double, _ b: Double) -> Double {
        return a - floor(a / b) * b
    }
    
    @inline(__always)
    static func wrap(_ x: Double, from a: Double, to b: Double) -> Double {
        return mod(x - a, b - a) + a
    }
}


extension UUID {
    /// Returns an Int hue in 0..<360 derived from this UUID
    func hueFromUUID() -> Int {
        // Use the first 8 bytes of the UUID as a UInt64
        let u = uuid
        let bytes: [UInt8] = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7]
        var value: UInt64 = 0
        for (i, b) in bytes.enumerated() {
            value |= UInt64(b) << (8 * i)
        }
        // Reduce to 0..<360
        return Int(value % 360)
    }
}
