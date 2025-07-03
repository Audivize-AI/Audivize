//
//  KalmanFilter.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/12/25.
//

import Foundation
import LANumerics
import simd

extension ASD.Tracking {
    class VisualKF : KalmanFilter {
        // State: (x, y, s, r, vx, vy, s')
        // Measurement: (x, y, w, h)
        
        @inline(__always)
        public var xPosition: Float {
            get {
                return x[0]
            }
            set {
                x[0] = newValue
            }
        }
        
        @inline(__always)
        public var yPosition: Float {
            get {
                return x[1]
            }
            set {
                x[1] = newValue
            }
        }
        
        @inline(__always)
        public var scale: Float {
            get {
                return x[2]
            }
            set {
                x[2] = newValue
            }
        }
        
        @inline(__always)
        public var aspectRatio: Float {
            get {
                return x[3]
            }
            set {
                x[3] = newValue
            }
        }
        
        @inline(__always)
        public var xVelocity: Float {
            get {
                return x[4]
            }
            set {
                x[4] = newValue
            }
        }
        
        @inline(__always)
        public var yVelocity: Float {
            get {
                return x[5]
            }
            set {
                x[5] = newValue
            }
        }
        
        @inline(__always)
        public var growthRate: Float {
            get {
                return x[6]
            }
            set {
                x[6] = newValue
            }
        }
        
        public var width: Float {
            get {
                return sqrt(self.scale * self.aspectRatio)
            }
            set {
                self.scale = newValue * newValue / self.aspectRatio
            }
        }
        
        public var height: Float {
            get {
                return sqrt(self.scale / self.aspectRatio)
            }
            set {
                self.scale = newValue * newValue * self.aspectRatio
            }
        }
        
        public var rect: CGRect {
            get {
                let width = self.width
                let height = self.height
                return CGRect(
                    x: CGFloat(self.xPosition - width / 2),
                    y: CGFloat(self.yPosition - height / 2),
                    width: CGFloat(width),
                    height: CGFloat(height)
                )
            }
            set {
                let width = Float(newValue.width)
                let height = Float(newValue.height)
                
                self.scale = width * height
                self.aspectRatio = width / height
                self.xPosition = Float(newValue.midX)
                self.yPosition = Float(newValue.midY)
            }
        }
        
        public var velocityDirection: Float {
            if let last = lastPosition3 ?? lastPosition2 {
                let deltaPosition = self.lastMeasurement.lowHalf - last
                return atan2f(deltaPosition.y, deltaPosition.x)
            }
            return .infinity
        }
        
        private var lastMeasurement: SIMD4<Float>
        private var lastObservedState: Matrix<Float>
        private var lastObservedCovariance: Matrix<Float>
        private var lastMeasurementTime: UInt = 0
        private var lastPosition2: SIMD2<Float>?
        private var lastPosition3: SIMD2<Float>?
        private var currentTime: UInt = 0
        
        private var lastN: SIMD2<Float>? { lastPosition3 ?? lastPosition2 }
        
        init(initialObservation: CGRect) {
            self.lastMeasurementTime = 0
            self.lastObservedState = Matrix<Float>.zero
            self.lastObservedCovariance = Matrix<Float>.zero
            self.lastMeasurement = VisualKF.convertRectToVector(initialObservation)
            
            super.init(
                x: VisualKF.convertRectToMeasurement(initialObservation) + [0, 0, 0],
                A: Matrix(rows: [
                    [1, 0, 0, 0, 1, 0, 0],
                    [0, 1, 0, 0, 0, 1, 0],
                    [0, 0, 1, 0, 0, 0, 1],
                    [0, 0, 0, 1, 0, 0, 0],
                    [0, 0, 0, 0, 1, 0, 0],
                    [0, 0, 0, 0, 0, 1, 0],
                    [0, 0, 0, 0, 0, 0, 1]
                ]),
                B: Matrix.zero,
                H: Matrix(rows: 4, columns: 7, diagonal: [Float](repeating: 1, count: 4)),
                Q: Matrix(rows: [
                    [ 1.28268929e-06, -1.50126387e-07, -4.22737386e-08, -4.36372168e-07,  7.61219594e-05, -4.97359920e-06, -5.06409531e-07],
                    [-1.50126387e-07,  2.18705147e-06, -7.56191483e-08, -2.95182877e-07, -9.74383535e-06,  1.24688022e-04, -4.26979849e-06],
                    [-4.22737386e-08, -7.56191483e-08,  7.84852302e-08, -1.94331423e-06, -2.54116645e-06, -5.44480058e-06,  2.69219956e-06],
                    [-4.36372168e-07, -2.95182877e-07, -1.94331423e-06,  4.38327846e-04, -2.40331927e-05,  4.01711922e-05,  1.21027027e-06],
                    [ 7.61219594e-05, -9.74383535e-06, -2.54116645e-06, -2.40331927e-05,  4.56885702e-03, -3.41518437e-04, -3.13712091e-05],
                    [-4.97359920e-06,  1.24688022e-04, -5.44480058e-06,  4.01711922e-05, -3.41518437e-04,  7.49469293e-03, -2.64343444e-04],
                    [-5.06409531e-07, -4.26979849e-06,  2.69219956e-06,  1.21027027e-06, -3.13712091e-05, -2.64343444e-04,  1.58519051e-04]
                ]),
                R: Matrix(rows: [
                    [ 2.68798854e-07,  6.93498964e-08,  1.41375159e-09, -1.32603707e-06],
                    [ 6.93498964e-08,  4.22660920e-07,  5.52960627e-08, -2.87047903e-07],
                    [ 1.41375159e-09,  5.52960627e-08,  1.00707611e-07, -1.23742312e-06],
                    [-1.32603707e-06, -2.87047903e-07, -1.23742312e-06,  2.64800784e-04]
                ])
            )
            
            self.lastObservedState = self.x
            self.lastObservedCovariance = self.P
        }
        
        /* OLD Q
         [1, 0, 0, 0, 0, 0, 0],
         [0, 1, 0, 0, 0, 0, 0],
         [0, 0, 1, 0, 0, 0, 0],
         [0, 0, 0, 1, 0, 0, 0],
         [0, 0, 0, 0, 0.01, 0, 0],
         [0, 0, 0, 0, 0, 0.01, 0],
         [0, 0, 0, 0, 0, 0, 0.001],
         */
        
        static func convertRectToMeasurement(_ rect: CGRect) -> [Float] {
            return [
                Float(rect.midX),
                Float(rect.midY),
                Float(rect.width * rect.height),
                Float(rect.width / rect.height),
            ]
        }
        
        static func convertRectToVector(_ rect: CGRect) -> SIMD4<Float> {
            return .init(
                x: Float(rect.midX),
                y: Float(rect.midY),
                z: Float(rect.width * rect.height),
                w: Float(rect.width / rect.height),
            )
        }
        
        override func predict() {
            self.xPosition += self.xVelocity
            self.yPosition += self.yVelocity
            self.scale += self.growthRate
            self.updateCovariancePredict()
        }
        
        func update(measurement: CGRect) {
            self.currentTime += 1
            let dt = self.currentTime - self.lastMeasurementTime
            if dt != 1 {
                self.x = self.lastObservedState
                self.P = self.lastObservedCovariance
                let step = (VisualKF.convertRectToVector(measurement) - self.lastMeasurement) * (1 / Float(self.currentTime - self.lastMeasurementTime))
                for i in (self.lastMeasurementTime+1)..<self.currentTime {
                    self.lastMeasurement += step
                    self.predict()
                    super.update(measurement: Matrix<Float>(self.lastMeasurement))
                    if i == self.currentTime - 2 {
                        self.lastPosition2 = self.lastMeasurement.lowHalf
                    } else if i == self.currentTime - 3 {
                        self.lastPosition3 = self.lastMeasurement.lowHalf
                    }
                }
                self.predict()
            } else {
                self.lastPosition3 = self.lastPosition2
                self.lastPosition2 = self.lastMeasurement.lowHalf
            }
            
            self.lastMeasurement = VisualKF.convertRectToVector(measurement)
            super.update(measurement: Matrix<Float>(self.lastMeasurement))
            
            self.lastObservedState = self.x
            self.lastObservedCovariance = self.P
            self.lastMeasurementTime = self.currentTime
        }
        
        public func deactivate() {
            self.lastPosition3 = nil
            self.lastPosition2 = nil
            self.lastMeasurementTime = 0
            self.currentTime = 0
            self.growthRate = 0
            self.xVelocity = 0
            self.yVelocity = 0
        }
        
        public func velocityCost(to rect: CGRect) -> Float {
            if let last = self.lastN {
                let thetaTrack = atan2f(self.lastMeasurement.y - last.y,
                                        self.lastMeasurement.x - last.x)
                let thetaIntention = atan2f(Float(rect.midY) - last.y,
                                       Float(rect.midX) - last.x)
                return abs(thetaTrack - thetaIntention)
            }
            return .infinity
        }
    }
    
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
        public var Q: Matrix<Float>
        
        /// Measurement noise covariance
        public var R: Matrix<Float>
        
        /// Identity matrix
        public let I: Matrix<Float>
        
        init(x: Vector<Float>, A: Matrix<Float>, B: Matrix<Float>, H: Matrix<Float>, Q: Matrix<Float>, R: Matrix<Float>, P0: Matrix<Float>? = nil) {
            self.I = Matrix<Float>.eye(x.count)
            
            self.x = Matrix<Float>(x)
            
            self.A = A
            self.B = B
            
            self.H = H
            
            self.Q = Q
            self.R = R
            
            self.P = P0 ?? 1000 * Q + H.transpose * R * H
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
