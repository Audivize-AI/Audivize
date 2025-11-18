//
//  Score.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/9/25.
//

import Foundation

extension Pairing.ASD {
    enum ScoreClass: Int {
        case inactive = 0
        case active = 1
    }
    
    struct Score: Sendable {
        public static let nan = Self(.nan)
        
        /// Raw logit score
        public var logit: Float
        
        /// Sigmoid probability
        public var probability: Float { 1.0 / (1.0 + exp(-logit)) }
        
        /// Whether the score is greater than 0
        public var isActive: Bool { logit > 0 }
        
        /// Predicted class (active or inactive) and confidence
        public var label: (class: ScoreClass, confidence: Float) {
            (isActive
             ? (.active, probability)
             : (.inactive, 1 - probability))
        }
        
        public init(_ logit: Float = 0) {
            self.logit = logit
        }
        
        public init(logit: Float) {
            self.logit = logit
        }
        
        public init(probability: Float) {
            self.logit = -logf(1.0 / probability - 1.0)
        }
        
        @inline(__always)
        public mutating func update(with logit: Float) {
            guard self.logit.isFinite && logit.isFinite else { return }
            self.logit += logit
        }
        
        @inline(__always)
        public mutating func update(with logit: Float, replaceNan: Bool) {
            if self.logit.isFinite && logit.isFinite {
                self.logit += logit
            } else if replaceNan && logit.isFinite {
                self.logit = logit
            }
        }
    }
}
