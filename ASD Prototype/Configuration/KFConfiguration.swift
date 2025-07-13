//
//  KFConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/12/25.
//

import Foundation

extension ASD.Tracking {
    struct QConfiguration {
        static let covXX:   Float = 0.073745
        static let covAA:   Float = 86.999316
        static let covRR:   Float = 0.000651
        static let covVV:   Float = 0.000467
        static let covVAVA: Float = 13.161883
        
        static let covXV:   Float = 0.000134446
        static let covAVA:  Float = 4.826791828
    }
    
    struct RConfiguration {
        static let covXX:   Float = 0.081101
        static let covAA:   Float = 4.502759
        static let covRR:   Float = 0.000026
    }
}
