//
//  EstimateTransform.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/17/25.
//

import Foundation


extension ASD.Tracking {
    enum Alignment {
        /// Reference points for alignment
        fileprivate static let sz: Float = 224
        fileprivate static let sc: Float = 1.75
        fileprivate static let hx: Float = sz * (2 - sc) / 4
        private static let dst: [Float] = [
            hx + sc * 38.2946, sz - sc * 51.6963, // left eye
            hx + sc * 73.5318, sz - sc * 51.5014, // right eye
            hx + sc * 56.0252, sz - sc * 71.7366, // nose
            hx + sc * 41.5493, sz - sc * 92.3655, // left mouth
            hx + sc * 70.7299, sz - sc * 92.2041, // right mouth
        ]
        
        private static let (dxMean, dyMean) = { () -> (Float, Float) in
            var sumDx:    Float = 0
            var sumDy:    Float = 0
            let N2 = dst.count
            
            for i in stride(from: 0, to: N2, by: 2) {
                let dx = dst[i]
                let dy = dst[i+1]
                sumDx    += dx
                sumDy    += dy
            }
            
            let invM = 2.0 / Float(N2)
            return (sumDx * invM, sumDy * invM)
        }()
        
        /// Author: OpenAI o4-mini-high
        /// - Parameters:
        ///   - src source points
        static func computeAlignTransform(_ src: [Float]) -> CGAffineTransform {
            precondition(src.count == dst.count)
            precondition((src.count & 1) == 0)
            let N2 = src.count
            let M = N2 >> 1
            let invM = 1.0 / Float(M)
            
            // accumulators for sums, sums of squares, and cross‐products
            var sum_sx:    Float = 0
            var sum_sy:    Float = 0
            var sum_sx2:   Float = 0
            var sum_sy2:   Float = 0
            var sum_dx_sx: Float = 0
            var sum_dy_sy: Float = 0
            var sum_dx_sy: Float = 0
            var sum_dy_sx: Float = 0
            
            // one loop over 2*M floats
            for i in stride(from: 0, to: N2, by: 2) {
                let sx = src[i]
                let sy = src[i+1]
                let dx = dst[i]
                let dy = dst[i+1]
                
                sum_sx    += sx
                sum_sy    += sy
                sum_sx2   += sx*sx
                sum_sy2   += sy*sy
                sum_dx_sx += dx*sx
                sum_dy_sy += dy*sy
                sum_dx_sy += dx*sy
                sum_dy_sx += dy*sx
            }
            
            // means
            let sxMean = sum_sx * invM
            let syMean = sum_sy * invM
            
            // variances of src (demeaned)
            let varX = sum_sx2 * invM - sxMean*sxMean
            let varY = sum_sy2 * invM - syMean*syMean
            
            // cross‐covariances (demeaned)
            let sxx = sum_dx_sx * invM - dxMean*sxMean
            let syy = sum_dy_sy * invM - dyMean*syMean
            let sxy = sum_dx_sy * invM - dxMean*syMean
            let syx = sum_dy_sx * invM - dyMean*sxMean
            
            // closed-form rotation (Umeyama Eqn. 40)
            let scale       = 1 / (varX + varY)
            let cosScaled   = (sxx + syy) * scale   // cosθ * scale
            let sinScaled    = (syx - sxy) * scale   // sinθ * scale
            
            // translation (Umeyama)
            let tx = CGFloat(dxMean - (cosScaled*sxMean - sinScaled*syMean))
            let ty = CGFloat(dyMean - (sinScaled*sxMean + cosScaled*syMean))
            let a = CGFloat(cosScaled)
            let b = CGFloat(sinScaled)
            let c = -b
            let d = a
            
            return CGAffineTransform(a: a, b: b,
                                     c: c, d: d,
                                     tx: tx, ty: ty)
        }
    }
}
