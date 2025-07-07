//
//  DetectionConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/1/25.
//

import Foundation

extension ASD.Tracking {
    struct FaceProcessingConfiguration {
        static let minDetectionConfidence: Float = 0.6
        static let embedderRequestLifespan: DispatchTimeInterval = .seconds(5)
        static let minReadyEmbedderRequests: Int = 8        
    }
}
