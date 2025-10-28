//
//  FaceRecognitionConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/18/25.
//

import Foundation

    extension ASD.FaceEmbedding {
        // yaw thresholds
        static let yawThreshold: CGFloat = 0.245
        static let yaw90Threshold: CGFloat = 0.733
        static let yawMax: CGFloat = 1.40
        
        // pitch thresholds
        static let upMax: CGFloat = 0.9
        static let upThreshold: CGFloat = 0.245
        static let up90Threshold: CGFloat = 0.337
        static let downThreshold: CGFloat = -0.149
        static let down90Threshold: CGFloat = -0.245
        static let downMax: CGFloat = -0.30
        
        // expression thresholds
        static let smileUpThreshold: CGFloat = 0.875
        static let smileDownThreshold: CGFloat = 0.800
        
        // expression offsets
        static let smileUpOffset: CGFloat = 0.05
        static let smileDownOffset: CGFloat = 0.10
        
        // weighting
        static let binSigma2: Float = pow(0.5, 2)
    }
