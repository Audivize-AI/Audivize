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
        private static let xBound: Float = Float(Global.videoWidth) / 2.0
        private static let yBound: Float = Float(Global.videoHeight) / 2.0
        
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
            return true
        }
        
//        public override var Q: Matrix<Float> {
//            get {
//                let size = sqrt(self.scale)
//                let std = 0.05 * size
//                let stdv = 0.00625 * size
//                return .init(diagonal: [std, std, std, 0.01, stdv, stdv, stdv])
//            }
//            set {}
//        }
        
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
                    [ 2.76384024e+01,  1.26272631e+01, -2.44306029e+02,  2.78650185e-03,  5.52874948e+01,  2.49260963e+01, -4.64828803e+02],
                    [ 1.26272631e+01,  9.71305095e+00, -1.09689915e+00,  5.22651143e-04,  2.52692561e+01,  1.92320866e+01,  1.51291018e+01],
                    [-2.44306029e+02, -1.09689915e+00,  2.03852928e+05,  8.27847482e-02, -4.89478381e+02, -1.29774689e+01,  4.07625823e+05],
                    [ 2.78650185e-03,  5.22651143e-04,  8.27847482e-02,  4.28270662e-04,  5.56470927e-03,  9.79662559e-04,  1.70162934e-01],
                    [ 5.52874948e+01,  2.52692561e+01, -4.89478381e+02,  5.56470927e-03,  1.10601809e+02,  4.98815834e+01, -9.31638176e+02],
                    [ 2.49260963e+01,  1.92320866e+01, -1.29774689e+01,  9.79662559e-04,  4.98815834e+01,  3.81011931e+01,  8.33570472e+00],
                    [-4.64828803e+02,  1.51291018e+01,  4.07625823e+05,  1.70162934e-01, -9.31638176e+02,  8.33570471e+00,  8.15230385e+05]
                ]),
                R: Matrix(rows: [
                    [ 5.39921154e+02,  3.41849660e+02,  5.24069050e+03, -1.43657096e-02],
                    [ 3.41849660e+02,  2.17244846e+02,  3.18265486e+03, -9.72325702e-03],
                    [ 5.24069050e+03,  3.18265486e+03,  5.25004162e+05, -4.25884516e+00],
                    [-1.43657096e-02, -9.72325702e-03, -4.25884516e+00,  2.72160113e-04]
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
                    self.recomputeR(from: self.lastMeasurement)
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
            self.recomputeR(from: z)
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
            
            let xBound = VisualKF.xBound + self.width / 2
            let yBound = VisualKF.yBound + self.height / 2
            
            if self.xPosition < -xBound {
                self.xPosition = -xBound
                self.xVelocity = 0
            } else if self.xPosition > xBound {
                self.xPosition = xBound
                self.xVelocity = 0
            }
            
            if self.yPosition < -yBound {
                self.yPosition = -yBound
                self.yVelocity = 0
            } else if self.yPosition > yBound {
                self.yPosition = yBound
                self.yVelocity = 0
            }
            
            self.updateCovariancePredict()
        }
        
        @inline(__always)
        private func recomputeRect() {
            self.computedWidth = sqrt(self.scale * self.aspectRatio)
            self.computedHeight = self.computedWidth / self.aspectRatio
        }
        
        @inline(__always)
        private func recomputeR(from measurement: SIMD4<Float>) {
//            let std = 0.05 * sqrt(measurement.z)
//            self.R = .init(diagonal: [std, std, std, 0.1])
        }
    }
}
