//
//  FaceRecognitionConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/18/25.
//

import Foundation

extension Pairing.Tracking.Detection {
    // yaw thresholds
    static let yawThreshold: Float = 0.245
    static let yaw90Threshold: Float = 0.733
    static let yawMax: Float = 1.40
    
    // pitch thresholds
    static let upMax: Float = 0.9
    static let upThreshold: Float = 0.245
    static let up90Threshold: Float = 0.337
    static let downThreshold: Float = -0.149
    static let down90Threshold: Float = -0.245
    static let downMax: Float = -0.30
    
    // expression thresholds
    static let smileUpThreshold: Float = 0.875
    static let smileDownThreshold: Float = 0.800
    
    // expression offsets
    static let smileUpOffset: Float = 0.05
    static let smileDownOffset: Float = 0.10
    
    // weighting
    static let binSigma2: Float = pow(0.5, 2)
}
