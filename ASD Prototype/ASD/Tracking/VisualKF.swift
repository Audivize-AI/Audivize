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
            // check size and aspect ratio
            if self.scale < 1e-2 || self.aspectRatio < 0 {
                return false
            }
            
            // check x bounds
            let halfWidth: Float = self.width / 2
            if self.xPosition <= -halfWidth || self.xPosition >= 1 + halfWidth {
                return false
            }
            
            // check y bounds
            let halfHeight: Float = self.height / 2
            if self.yPosition <= -halfHeight || self.yPosition >= 1 + halfHeight {
                return false
            }
            
            return true
        }
        
        private var lastMeasurement: SIMD4<Float>
        private var lastObservedState: Matrix<Float>
        private var lastObservedCovariance: Matrix<Float>
        private var lastPosition2: SIMD2<Float>?
        private var lastPosition3: SIMD2<Float>?
        private var lastMeasurementTime: UInt = 0
        private var currentTime: UInt = 0
        
        private var lastN: SIMD2<Float> { lastPosition3 ?? lastPosition2 ?? lastMeasurement.lowHalf }
        
        private var computedWidth: Float
        private var computedHeight: Float
        private var velocityDirection: Float = .nan
        
        init(initialObservation observation: CGRect) {
            self.lastMeasurementTime = 0
            self.currentTime = 0
            self.lastObservedState = .zero
            self.lastObservedCovariance = .zero
            self.lastMeasurement = VisualKF.convertRectToVector(observation)
            self.computedWidth = Float(observation.width)
            self.computedHeight = Float(observation.height)
            
            super.init(
                x: VisualKF.convertRectToMeasurement(observation) + [0, 0, 0],
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
                    [ 2.42876101e-06, -1.03839921e-07, -3.54527955e-08, -1.63431818e-06,  4.14275830e-06, -3.99964970e-07, -1.49089451e-07],
                    [-1.03839921e-07,  1.46320604e-06, -5.29957615e-08, -9.39398050e-07, -2.77157719e-08,  2.53089048e-06, -1.42513410e-08],
                    [-3.54527955e-08, -5.29957615e-08,  1.27419106e-07, -2.80467668e-06, -1.95563872e-07, -9.63137237e-08,  8.56312791e-08],
                    [-1.63431818e-06, -9.39398050e-07, -2.80467668e-06,  4.38302354e-04,  1.26355139e-06, -9.36985408e-07,  3.12428428e-08],
                    [ 4.14275830e-06, -2.77157719e-08, -1.95563872e-07,  1.26355139e-06,  8.29982635e-06, -3.73464471e-07, -3.09111784e-07],
                    [-3.99964970e-07,  2.53089048e-06, -9.63137237e-08, -9.36985408e-07, -3.73464471e-07,  5.07608324e-06, -3.00856481e-08],
                    [-1.49089451e-07, -1.42513410e-08,  8.56312791e-08,  3.12428428e-08, -3.09111784e-07, -3.00856481e-08,  1.67404023e-07]
                ]),
                R: Matrix(rows: [
                    [ 3.51575609e-07,  6.43252841e-08,  3.96189101e-08,  1.69858509e-07],
                    [ 6.43252841e-08,  2.16193761e-07,  2.39058574e-09, -1.18532093e-06],
                    [ 3.96189101e-08,  2.39058574e-09,  8.25075609e-08, -8.98603632e-07],
                    [ 1.69858509e-07, -1.18532093e-06, -8.98603632e-07,  2.64845963e-04]
                ]),
                P0: Matrix(diagonal: [1, 1, 1, 1, 0.01, 0.01, 0.001])
            )
            
            self.lastObservedState = self.x
            self.lastObservedCovariance = self.P
        }
        
        public static func convertRectToMeasurement(_ rect: CGRect) -> [Float] {
            return [
                Float(rect.midX),
                Float(rect.midY),
                Float(rect.width * rect.height),
                Float(rect.width / rect.height),
            ]
        }
        
        public static func convertRectToVector(_ rect: CGRect) -> SIMD4<Float> {
            return .init(
                x: Float(rect.midX),
                y: Float(rect.midY),
                z: Float(rect.width * rect.height),
                w: Float(rect.width / rect.height),
            )
        }
        
        @inline(__always)
        public override func predict() {
            self.currentTime += 1
            self.predictNoTimeUpdate()
        }
        
        public func update(measurement: CGRect) {
            let dt = self.currentTime - self.lastMeasurementTime
            let z = VisualKF.convertRectToVector(measurement)
            if dt > 1 {
                self.x = self.lastObservedState
                self.P = self.lastObservedCovariance
                let step = (VisualKF.convertRectToVector(measurement) - self.lastMeasurement) *
                           (1 / Float(self.currentTime - self.lastMeasurementTime))
                var lastPositions: [SIMD2<Float>] = []
                lastPositions.reserveCapacity(Int(dt + 3))
                if let last2 = self.lastPosition2 {
                    if let last3 = self.lastPosition3 {
                        lastPositions.append(last3)
                    }
                    lastPositions.append(last2)
                }
                lastPositions.append(self.lastMeasurement.lowHalf)
                
                for _ in (self.lastMeasurementTime+1)..<self.currentTime {
                    self.lastMeasurement += step
                    self.predictNoTimeUpdate()
                    super.update(measurement: Matrix<Float>(self.lastMeasurement))
                    lastPositions.append(self.lastMeasurement.lowHalf)
                }
                
                self.lastPosition2 = lastPositions[lastPositions.count-1]
                self.lastPosition3 = lastPositions[lastPositions.count-2]
                let last4 = lastPositions[max(lastPositions.count-3, 0)]
                self.velocityDirection = atan2(z.y - last4.y, z.x - last4.x)
                self.predictNoTimeUpdate()
            } else {
                let last3 = self.lastPosition3 ?? self.lastPosition2 ?? self.lastMeasurement.lowHalf
                self.velocityDirection = atan2(z.y - last3.y, z.x - last3.x)
                self.lastPosition3 = self.lastPosition2
                self.lastPosition2 = self.lastMeasurement.lowHalf
            }
            
            self.lastMeasurement = z
            self.lastMeasurementTime = self.currentTime
            
            super.update(measurement: Matrix<Float>(z))
            
            self.recomputeRect()
            self.lastObservedState = self.x
            self.lastObservedCovariance = self.P
        }
        
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
            
            self.lastMeasurementTime = 0
            self.currentTime = 0
            self.velocityDirection = .nan
            self.lastMeasurement = VisualKF.convertRectToVector(rect)
        }
        
        public func deactivate() {
            self.lastPosition3 = nil
            self.lastPosition2 = nil
            self.lastObservedState = .zero
            self.lastObservedCovariance = .zero
            self.lastMeasurementTime = 0
            self.currentTime = 0
            self.growthRate = 0
            self.xVelocity = 0
            self.yVelocity = 0
            self.velocityDirection = .nan
        }
        
        public func velocityCost(to rect: CGRect) -> Float {
            if self.velocityDirection.isNaN { return 0 }
            let thetaIntention = atan2((Float(rect.midY) - lastN.y), (Float(rect.midX) - lastN.x))
            return abs(Utils.wrap(self.velocityDirection - thetaIntention,
                                  from: -Float.pi,
                                  to: Float.pi))
        }
        
        private func predictNoTimeUpdate() {
            self.xPosition += self.xVelocity
            self.yPosition += self.yVelocity
            self.scale += self.growthRate
            
            let halfWidth = self.width / 2
            let halfHeight = self.height / 2
            
            if self.xPosition < -halfWidth {
                self.xPosition = -halfWidth
                self.xVelocity = 0
            } else if self.xPosition > 1 + halfWidth {
                self.xPosition = halfWidth
                self.xVelocity = 0
            }
            
            if self.yPosition < -halfHeight {
                self.yPosition = -halfHeight
                self.yVelocity = 0
            } else if self.yPosition > 1 + halfHeight {
                self.yPosition = halfHeight
                self.yVelocity = 0
            }
            
            self.updateCovariancePredict()
        }
        
        @inline(__always)
        private func recomputeRect() {
            self.computedWidth = sqrt(self.scale * self.aspectRatio)
            self.computedHeight = self.computedWidth / self.aspectRatio
        }
    }
}
