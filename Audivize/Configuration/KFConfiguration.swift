//
//  KFConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/12/25.
//

import Foundation

extension ASD.Tracking {
    struct PConfiguration {
        static let P0: [[Float]] = [
            [0.14,    0,   0,    0, 0.01,    0,  0],
            [   0, 0.14,   0,    0,    0, 0.01,  0],
            [   0,    0, 130,    0,    0,    0, 42],
            [   0,    0,   0, 7e-4,    0,    0,  0],
            [0.01,    0,   0,    0, 7e-3,    0,  0],
            [   0, 0.01,   0,    0,    0, 7e-3,  0],
            [   0,    0,  42,    0,    0,    0, 49]
        ]
    }
    
    struct QConfiguration {
        static let covXX:   Float = 0.073745    // coord-coord
        static let covAA:   Float = 0.001281   // area-area
        static let covRR:   Float = 0.000651    // ratio-ratio
        static let covVV:   Float = 0.000467    // velocity-velocity
        static let covVAVA: Float = 0.000009   // growth-growth
//        static let covVRVR: Float = 13.161883   // stretch-stretch
        
        static let covXV:   Float = 0.000134446 // coord-velocity
        static let covAVA:  Float = 0.000004516 // area-growth
//        static let covRVR:  Float = 4.826791828 // area-growth
    }
    
    struct RConfiguration {
        static let covXX:   Float = 0.081101
        static let covAA:   Float = 0.000061
        static let covRR:   Float = 0.000026
    }
}
