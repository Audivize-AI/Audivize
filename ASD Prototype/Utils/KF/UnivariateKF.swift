//
//  UnivariateKF.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/5/25.
//

import Foundation

class UnivariateKF {
    public var x: Float /// State
    public var P: Float /// Variance
    public var Q: Float /// Process noise variance
    public var R: Float /// Measurement noise variance
    
    public init (x: Float, Q: Float, R: Float, P: Float = 1) {
        self.x = x
        self.P = P
        self.Q = Q
        self.R = R
    }
    
    public func predict(input u: Float = 0) {
        self.x += u
        self.P += Q
    }
    
    public func update(measurement z: Float) {
        let K = P / (P + R)
        self.x += K * (z - x)
        self.P -= K * P
    }
    
    public func step(input u: Float = 0, measurement z: Float) {
        self.predict(input: u)
        self.update(measurement: z)
    }
}
