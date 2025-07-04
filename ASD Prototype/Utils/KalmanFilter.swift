//
//  KalmanFilter.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/12/25.
//

import Foundation
import LANumerics
import simd

extension Utils {
    class KalmanFilter {
        /// State vector
        public var x: Matrix<Float>
        
        /// Covariance matrix
        public var P: Matrix<Float>
        
        /// State transition matrix
        public let A: Matrix<Float>
        
        /// Control matrix
        public let B: Matrix<Float>
        
        /// Measurement matrix
        public let H: Matrix<Float>
        
        /// Process noise covariance
        public let Q: Matrix<Float>
        
        /// Measurement noise covariance
        public let R: Matrix<Float>
        
        /// Identity matrix
        public let I: Matrix<Float>
        
        public var initialCovariance: Matrix<Float> {
            1000 * self.Q + self.H.transpose * self.R * self.H
        }
        
        init(x: Vector<Float>, A: Matrix<Float>, B: Matrix<Float>, H: Matrix<Float>, Q: Matrix<Float>, R: Matrix<Float>, P0: Matrix<Float>? = nil) {
            self.I = Matrix<Float>.eye(x.count)
            
            self.x = Matrix<Float>(x)
            
            self.A = A
            self.B = B
            
            self.H = H
            
            self.Q = Q
            self.R = R
            
            self.P = P0 ?? (self.I + H.transpose * R * H - Matrix<Float>.eye(x.count - H.rows))
        }
        
        public func predict() {
            self.x = self.A * self.x
            self.updateCovariancePredict()
        }
        
        public func predict(input u: Vector<Float>) {
            self.x = self.A * self.x + self.B * Matrix<Float>(u)
            self.updateCovariancePredict()
        }
        
        @inline(__always)
        public func updateCovariancePredict() {
            self.P = self.A * self.P * self.A.transpose + self.Q
        }
        
        @inline(__always)
        public func update(measurement z: Vector<Float>) {
            self.update(measurement: Matrix<Float>(z))
        }
        
        public func update(measurement z: Matrix<Float>) {
            let y = z - (self.H * self.x)
            let S = self.H * self.P * self.H.transpose + self.R
            guard let SInv = S.inverse else { return }
            let K = self.P * self.H.transpose * SInv
            self.update(innovation: y, gain: K)
        }
        
        @inline(__always)
        public func update(innovation y: Matrix<Float>, gain K: Matrix<Float>) {
            self.x = self.x + (K * y)
            self.P = (self.I - K * self.H) * self.P
        }
        
        public func step(measurement z: Vector<Float>) {
            self.predict()
            self.update(measurement: z)
        }
        
        public func step(measurement z: Matrix<Float>) {
            self.predict()
            self.update(measurement: z)
        }
        
        public func step(input u: Vector<Float>, measurement z: Vector<Float>) {
            self.predict(input: u)
            self.update(measurement: z)
        }
        
        public func step(input u: Vector<Float>, measurement z: Matrix<Float>) {
            self.predict(input: u)
            self.update(measurement: z)
        }
    }
}
