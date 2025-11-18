//
//  Attitude.swift
//  Audivize
//
//  Created by Benjamin Lee on 10/30/25.
//

import Foundation

extension Pairing {
    struct Attitude {
        var pitch: Float
        var yaw: Float
        
        static let invalid: Attitude = .init(pitch: .nan, yaw: .nan)
        static let infinity: Attitude = .init(pitch: .infinity, yaw: .infinity)
        static let max: Attitude = .init(pitch: .pi/2, yaw: .pi/2)
    }
}
