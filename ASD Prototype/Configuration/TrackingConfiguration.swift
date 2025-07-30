//
//  TrackingConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/1/25.
//

import Foundation

extension ASD.Tracking {
    struct TrackingConfiguration {
        // activation, confirmation, and deletion
        static let confirmationThreshold: Int                   = 30
        static let activationThreshold: Int                     = 5
        static let deactivationThreshold: Int                   = 20
        static let deletionThreshold: Int                       = 10 * 30
        
        // embedding updates
        static let iterationsPerEmbeddingUpdate: Int            = 5
        static let embeddingConfidenceThreshold: Float          = 0.5
        static let embeddingAlpha: Float                        = 1 - pow(0.333, embeddingDt)
        static let appearanceCostVariance: Float                = 0.006 * embeddingDt
        static let appearanceCostMeasurementVariance: Float     = 0.006
        
        // missed track updates
        static let velocityDamping: Float                       = pow(0.5, dt)
        static let growthDamping: Float                         = pow(0.7, dt)
        
        // gating thresholds
        static let minIou: Float            = 0.2
        static let maxAppearanceCost: Float = 1.2
        static let maxTeleportCost: Float   = 0.4
        static let maxReIDCost: Float       = 0.4
        
        // weights
        static let ocmWeight: Float         = 0.2
        static let confidenceWeight: Float  = 1.0
        static let appearanceWeight: Float  = 1.0
        
        // private computation helpers
        fileprivate static let fps: Float = 30
        fileprivate static let dt: Float = 1 / fps
        fileprivate static let embeddingDt: Float = Float(iterationsPerEmbeddingUpdate) / fps
    }
}
