//
//  VisualKF.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/3/25.
//

import Foundation
import LANumerics
import simd

extension ASD.Tracking {
    class VisualKF : Utils.KalmanFilter {
        private static let xBound: Float = Float(CaptureConfiguration.videoWidth) / 2.0
        private static let yBound: Float = Float(CaptureConfiguration.videoHeight) / 2.0
        
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
                let scale = sqrt(newValue / self.x[2])
                self.computedWidth *= scale
                self.computedHeight *= scale
                x[2] = newValue
            }
        }
        
        @inline(__always)
        public var aspectRatio: Float {
            get {
                return x[3]
            }
            set {
                let scale = sqrt(newValue / x[3])
                self.computedWidth *= scale
                self.computedHeight /= scale
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
                return self.computedWidth
            }
            set {
                self.computedWidth = newValue
                self.computedHeight = newValue / self.aspectRatio
                self.scale = newValue * self.computedHeight
            }
        }
        
        public var height: Float {
            get {
                return self.computedHeight
            }
            set {
                self.computedHeight = newValue
                self.computedWidth = newValue * self.aspectRatio
                self.scale = newValue * self.computedWidth
            }
        }
        
        public var rect: CGRect {
            get {
                return .init(
                    x: CGFloat(self.xPosition - self.computedWidth / 2),
                    y: CGFloat(self.yPosition - self.computedHeight / 2),
                    width: CGFloat(self.computedWidth),
                    height: CGFloat(self.computedHeight)
                )
            }
            set {
                self.computedWidth = Float(newValue.width)
                self.computedHeight = Float(newValue.height)
                
                self.x[0] = Float(newValue.midX)                        // x
                self.x[1] = Float(newValue.midY)                        // y
                self.x[2] = self.computedWidth * self.computedHeight    // s
                self.x[3] = self.computedWidth / self.computedHeight    // r
            }
        }
        
        public var isValid: Bool {
            return self.width.isNaN == false && self.height.isNaN == false
        }
        
        private var lastMeasurement: SIMD4<Float>
        private var lastObservedState: Matrix<Float>
        private var lastObservedCovariance: Matrix<Float>
        private var lastPosition2: SIMD2<Float>?
        private var lastPosition3: SIMD2<Float>?
        private var numMisses: UInt = 0
        
        private var computedWidth: Float
        private var computedHeight: Float
        private var velocityDirection: Float = .nan
        
        /// - Parameter observation initial observation
        init(initialObservation observation: CGRect) {
            self.lastObservedState = .zero
            self.lastObservedCovariance = .zero
            self.lastMeasurement = VisualKF.rectToSIMD4(observation)
            self.computedWidth = Float(observation.width)
            self.computedHeight = Float(observation.height)
            
            super.init(
                x: VisualKF.rectToVector(observation) + [0, 0, 0],
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
                Q: Matrix<Float>.eye(7),
                R: Matrix<Float>.eye(4),
                P0: Matrix(diagonal: [1, 1, 1, 1, 0.01, 0.01, 0.001])
            )
            
            self.lastObservedState = self.x
            self.lastObservedCovariance = self.P
        }
        
        /// Predict step
        public override func predict() {
            // predict step
            self.numMisses += 1
            self.xPosition += self.xVelocity
            self.yPosition += self.yVelocity
            self.scale += self.growthRate
            
            let xBound = VisualKF.xBound + self.width / 2
            let yBound = VisualKF.yBound + self.height / 2
            
            // constrain x position
            if self.xPosition < -xBound {
                self.xPosition = -xBound
                self.xVelocity = 0
            } else if self.xPosition > xBound {
                self.xPosition = xBound
                self.xVelocity = 0
            }
            
            // constrain y position
            if self.yPosition < -yBound {
                self.yPosition = -yBound
                self.yVelocity = 0
            } else if self.yPosition > yBound {
                self.yPosition = yBound
                self.yVelocity = 0
            }
            
            // register predict
            self.recomputeQ()
            self.updateCovariancePredict()
        }
        
        /// Update step
        /// - Parameter rect observation
        public func update(measurement: CGRect) {
            let z = VisualKF.rectToSIMD4(measurement)
            let numMisses = self.numMisses
            if self.numMisses > 1 {
                // rollback to the state after the last measurement
                self.x = self.lastObservedState
                self.P = self.lastObservedCovariance
                
                // prepare to store virtual trajectory
                let step = (z - self.lastMeasurement) * (1 / Float(numMisses))
                var lastPositions: [SIMD2<Float>] = []
                lastPositions.reserveCapacity(Int(numMisses + 3))
                if let last2 = self.lastPosition2 {
                    if let last3 = self.lastPosition3 {
                        lastPositions.append(last3)
                    }
                    lastPositions.append(last2)
                }
                lastPositions.append(self.lastMeasurement.lowHalf)
                
                // Observation-centric Re-Update
                for _ in 1..<self.numMisses {
                    self.lastMeasurement += step
                    self.predict()
                    self.recomputeR(from: self.lastMeasurement)
                    super.update(measurement: Matrix<Float>(self.lastMeasurement))
                    lastPositions.append(self.lastMeasurement.lowHalf)
                }
                
                // update last 3 positions and velocity direction
                self.lastPosition2 = lastPositions[lastPositions.count-1]
                self.lastPosition3 = lastPositions[lastPositions.count-2]
                let last4 = lastPositions[max(lastPositions.count-3, 0)]
                self.velocityDirection = atan2(z.y - last4.y, z.x - last4.x)
                
                // final predict step
                self.predict()
            } else {
                // update last 3 positions and velocity direction
                let last3 = self.lastPosition3 ?? self.lastPosition2 ?? self.lastMeasurement.lowHalf
                self.velocityDirection = atan2(z.y - last3.y, z.x - last3.x)
                self.lastPosition3 = self.lastPosition2
                self.lastPosition2 = self.lastMeasurement.lowHalf
            }
            
            // update step
            self.recomputeR(from: z)
            super.update(measurement: Matrix<Float>(z))
            self.recomputeRect()
            
            // register update
            self.lastObservedState = self.x
            self.lastObservedCovariance = self.P
            self.lastMeasurement = z
            self.numMisses = 0
        }
        
        /// Reset the Kalman filter with an initial measurement
        /// - Parameter rect initial measurement
        public func activate(_ rect: CGRect) {
            self.lastPosition3 = nil
            self.lastPosition2 = nil
            
            self.rect = rect
            self.growthRate = 0
            self.xVelocity = 0
            self.yVelocity = 0
            self.P = Matrix<Float>.init(diagonal: [1, 1, 1, 1, 0.01, 0.01, 0.001])
            
            self.lastObservedState = self.x
            self.lastObservedCovariance = self.P
            
            self.numMisses = 0
            self.velocityDirection = .nan
            self.lastMeasurement = VisualKF.rectToSIMD4(rect)
        }
        
        /// Reset the Kalman filter
        public func deactivate() {
            self.lastPosition3 = nil
            self.lastPosition2 = nil
            self.lastObservedState = .zero
            self.lastObservedCovariance = .zero
            self.numMisses = 0
            self.growthRate = 0
            self.xVelocity = 0
            self.yVelocity = 0
            self.velocityDirection = .nan
        }
        
        /// OCM Cost
        /// - Parameter rect observation
        /// - Returns the Observation Centric Momentum (OCM) cost
        public func velocityCost(to rect: CGRect) -> Float {
            if self.velocityDirection.isNaN { return 0 }
            let last = lastPosition3 ?? lastPosition2 ?? lastMeasurement.lowHalf
            let thetaIntention = atan2((Float(rect.midY) - last.y), (Float(rect.midX) - last.x))
            return abs(Utils.wrap(self.velocityDirection - thetaIntention,
                                  from: -Float.pi,
                                  to: Float.pi))
        }
        
        // MARK: private static helpers
        private static func rectToVector(_ rect: CGRect) -> [Float] {
            return [
                Float(rect.midX),
                Float(rect.midY),
                Float(rect.width * rect.height),
                Float(rect.width / rect.height),
            ]
        }
        
        private static func rectToSIMD4(_ rect: CGRect) -> SIMD4<Float> {
            return .init(
                x: Float(rect.midX),
                y: Float(rect.midY),
                z: Float(rect.width * rect.height),
                w: Float(rect.width / rect.height),
            )
        }
        
        // MARK: private instance helpers
        
        @inline(__always)
        private func recomputeRect() {
            self.computedWidth = sqrt(self.scale * self.aspectRatio)
            self.computedHeight = self.computedWidth / self.aspectRatio
        }
        
        @inline(__always)
        private func recomputeR(from measurement: SIMD4<Float>) {
            let xx = RConfiguration.covXX * self.height
            let AA = RConfiguration.covAA * self.height
            let rr = RConfiguration.covRR * self.height
            self.R[0, 0] = xx
            self.R[1, 1] = xx
            self.R[2, 2] = AA
            self.R[3, 3] = rr
        }
        
        @inline(__always)
        private func recomputeQ() {
            let xx = QConfiguration.covXX * self.height
            let AA = QConfiguration.covAA * self.height
            let rr = QConfiguration.covRR * self.height
            let vv = QConfiguration.covVV * self.height
            let vAvA = QConfiguration.covVAVA * self.height
            let xv = QConfiguration.covXV * self.height
            let AvA = QConfiguration.covAVA * self.height
            self.Q[0, 0] = xx
            self.Q[1, 1] = xx
            self.Q[2, 2] = AA
            self.Q[3, 3] = rr
            self.Q[4, 4] = vv
            self.Q[5, 5] = vv
            self.Q[6, 6] = vAvA
            self.Q[0, 4] = xv
            self.Q[4, 0] = xv
            self.Q[1, 5] = xv
            self.Q[5, 1] = xv
            self.Q[2, 6] = AvA
            self.Q[6, 2] = AvA
        }
    }
}
