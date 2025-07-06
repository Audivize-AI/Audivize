//
//  TrackingConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/1/25.
//

import Foundation

extension ASD.Tracking {
    final class TrackConfiguration {
        public let confirmationThreshold: Int
        public let activationThreshold: Int
        public let deactivationThreshold: Int
        public let iterationsPerEmbeddingUpdate: Int
        public let deletionThreshold: Int
        public let embeddingAlpha: Float
        public let embeddingConfidenceThreshold: Float
        public let velocityDamping: Float
        public let growthDamping: Float
        
        init(confirmationThreshold: Int             = 15,
             activationThreshold: Int               = 2,
             deactivationThreshold: Int             = 8,
             deletionThreshold: Int                 = 10 * 30,
             iterationsPerEmbeddingUpdate: Int      = 1,
             embeddingAlpha: Float                  = 0.2,
             embeddingConfidenceThreshold: Float    = 0.7,
             velocityDamping: Float                 = 0.5,
             growthDamping: Float                   = 0.1,
             dt: Float                              = 1.0 / 30.0)
        {
            self.confirmationThreshold = confirmationThreshold
            self.activationThreshold = activationThreshold
            self.deactivationThreshold = deactivationThreshold
            self.deletionThreshold = deletionThreshold
            self.iterationsPerEmbeddingUpdate = iterationsPerEmbeddingUpdate
            self.embeddingAlpha = embeddingAlpha
            self.embeddingConfidenceThreshold = embeddingConfidenceThreshold
            self.velocityDamping = pow(velocityDamping, dt)
            self.growthDamping = pow(growthDamping, dt)
        }
    }
    
    final class CostConfiguration {
        public let ocmWeight: Float
        public let confidenceWeight: Float
        public let appearanceWeight: Float
        public let minIou: Float
        public let maxAppearanceCost: Float
        public let maxReIDCost: Float
        
        init(appearanceWeight: Float    = 1.0,
             confidenceWeight: Float    = 1.0,
             ocmWeight: Float           = 0.2,
             minIou: Float              = 0.2,
             maxAppearanceCost: Float   = 0.5,
             maxReIDCost: Float         = 0.3)
        {
            self.appearanceWeight = appearanceWeight
            self.confidenceWeight = confidenceWeight
            self.ocmWeight = ocmWeight
            self.minIou = minIou
            self.maxAppearanceCost = maxAppearanceCost
            self.maxReIDCost = maxReIDCost
        }
    }
}
