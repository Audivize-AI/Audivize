//
//  Embedder.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/21/25.
//

import Foundation
import Vision
import CoreML
import ImageIO
import Accelerate


extension ASD.Tracking {
    final class FaceEmbedder {
        // MARK: Precomputed static attributes
        
        /// Landmark reference points for a 112x112 image (Umayama destination points)
        private static let dst: [Float] = [
            38.2946, 51.6963, /// Left eye center
            73.5318, 51.5014, /// Right eye center
            56.0252, 71.7366, /// Nose
            41.5493, 92.3655, /// Left mouth corner
            70.7299, 92.2041  /// Right mouth corner
        ]
        
        /// 1 / (number of reference points)
        private static let invDstCount = 2.0 / Float(dst.count)
        
        /// Center of the reference points
        private static let (dxMean, dyMean) = { () -> (Float, Float) in
            var center = stride(from: 0, to: dst.count, by: 2)
                .reduce(into: SIMD2<Float>(0, 0)) { res, i in
                    res += SIMD2<Float>(dst[i], dst[i+1])
                } * invDstCount
            return (center.x, center.y)
        }()
        
        /// Input image size
        private static let imageSize = (width: 112, height: 112)
        
        // MARK: Private Attributes
        private let embedderModel: GhostFaceNet /// EmbeddingModel
        
        // MARK: Constructors
        init() {
            print("DEBUG: Loading GhostFaceNet model...")
            self.embedderModel = try! GhostFaceNet(configuration: MLModelConfiguration())
            print("DEBUG: RETRIEVED GhostFaceNet model.")
        }
        
        // MARK: Public Methods
        /// - Parameters:
        ///   - detections array of face detection objects
        ///   - pixelBuffer image pixelBuffer
        public func embed(faces detections: any Sequence<Detection>,
                          in pixelBuffer: CVPixelBuffer) {
            for detection in detections {
                let transform = FaceEmbedder.computeAlignmentTransform(detection.landmarks)
                
                if let alignedImage = FaceEmbedder.align(image: pixelBuffer, with: transform) {
                    let input = GhostFaceNetInput(image: alignedImage)
                    detection.embedding = try? self.embedderModel.prediction(input: input)
                        .embeddingShapedArray.scalars
                    
                    // check if the full face is in frame
                    if detection.embedding == nil { continue }
                    let inverseTransform = invertAffine(transform)
                    
                    let corners = [
                        CGPoint(x: 0, y: 0).applying(inverseTransform).applying(transform),
                        CGPoint(x: 112, y: 0).applying(inverseTransform).applying(transform),
                        CGPoint(x: 112, y: 112).applying(inverseTransform).applying(transform),
                        CGPoint(x: 0, y: 112).applying(inverseTransform).applying(transform)
                    ]
                    var minX: CGFloat = .greatestFiniteMagnitude
                    var minY: CGFloat = .greatestFiniteMagnitude
                    var maxX: CGFloat = -.greatestFiniteMagnitude
                    var maxY: CGFloat = -.greatestFiniteMagnitude
                    
                    for corner in corners {
                        minX = min(minX, corner.x)
                        minY = min(minY, corner.y)
                        maxX = max(maxX, corner.x)
                        maxY = max(maxY, corner.y)
                    }
                    print(corners)
                
                    if minX < 0 || minY < 0 || maxX > Global.videoWidth || maxY > Global.videoHeight {
//                        detection.isFullFace = false
                    }
                }
            }
        }
        
        func invertAffine(_ T: CGAffineTransform) -> CGAffineTransform {
            let r00 = T.a, r01 = T.c, tx = T.tx
            let r10 = T.b, r11 = T.d, ty = T.ty
            
            // 1) determinant of the 2×2 linear part
            let det = r00*r11 - r01*r10
            guard det != 0 else { return T }
            let invDet = 1.0 / det
            
            // 2) inverse of R = [[r00,r01],[r10,r11]]
            let i00 =  r11 * invDet
            let i01 = -r01 * invDet
            let i10 = -r10 * invDet
            let i11 =  r00 * invDet
            
            // 3) inverse translation = -R⁻¹ * t
            let itx = -(i00*tx + i01*ty)
            let ity = -(i10*tx + i11*ty)
            
            // 4) pack back into row-major 3×3
            return .init(
                a: i00, b: i10, c: i01, d: i11, tx: itx, ty: ity
            )
        }
        
        // MARK: Private static helpers
        
        /// Author: OpenAI o4-mini-high
        /// Estimate affine transform with Umayama Algorithm
        /// - Parameters:
        ///   - src source points
        private static func computeAlignmentTransform(_ src: [Float]) -> CGAffineTransform {
            precondition(src.count == dst.count)
            precondition((src.count & 1) == 0)
            
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
            for i in stride(from: 0, to: dst.count, by: 2) {
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
            let sxMean = sum_sx * invDstCount
            let syMean = sum_sy * invDstCount
            
            // variances of src (demeaned)
            let varX = sum_sx2 * invDstCount - sxMean*sxMean
            let varY = sum_sy2 * invDstCount - syMean*syMean
            
            // cross‐covariances (demeaned)
            let sxx = sum_dx_sx * invDstCount - dxMean*sxMean
            let syy = sum_dy_sy * invDstCount - dyMean*syMean
            let sxy = sum_dx_sy * invDstCount - dxMean*syMean
            let syx = sum_dy_sx * invDstCount - dyMean*sxMean
            
            // closed-form rotation (Umeyama Eqn. 40)
            let scale       = 1 / (varX + varY)
            let cosScaled   = (sxx + syy) * scale   // cosθ * scale
            let sinScaled   = (syx - sxy) * scale   // sinθ * scale
            
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
        
        /// Author: Gemini 2.5 Pro
        /// Applies an affine transform to an image
        /// - Parameters:
        ///   - pixelBuffer input pixelBuffer
        ///   - transform the transform being applied
        ///   - size output image size
        /// - Returns a CVPixelBuffer containing the transformed image.
        private static func align(image pixelBuffer: CVPixelBuffer,
                                  with transform: CGAffineTransform) -> CVPixelBuffer? {
            // 1. Verify the input pixel buffer format is supported by this vImage function.
            let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
            guard pixelFormat == kCVPixelFormatType_32BGRA || pixelFormat == kCVPixelFormatType_32ARGB else {
                print("Error: Unsupported pixel format \(pixelFormat). Only 32BGRA and 32ARGB are supported.")
                return nil
            }
            
            // 2. Lock the base address of the input buffer for reading.
            guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
                print("Error: Failed to lock input pixel buffer.")
                return nil
            }
            // Ensure the buffer is unlocked even if the function fails.
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            
            // 3. Create a vImage_Buffer from the input CVPixelBuffer.
            guard let srcBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                print("Error: Could not get base address of input pixel buffer.")
                return nil
            }
            var srcBuffer = vImage_Buffer(
                data: srcBaseAddress,
                height: vImagePixelCount(CVPixelBufferGetHeight(pixelBuffer)),
                width: vImagePixelCount(CVPixelBufferGetWidth(pixelBuffer)),
                rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer)
            )
            
            // 4. Create the destination CVPixelBuffer.
            var dstPixelBuffer: CVPixelBuffer?
            let attributes: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                imageSize.width,
                imageSize.height,
                pixelFormat, // Use the same pixel format as the input
                attributes as CFDictionary,
                &dstPixelBuffer
            )
            
            guard status == kCVReturnSuccess, let finalPixelBuffer = dstPixelBuffer else {
                print("Error: Failed to create output CVPixelBuffer. Status: \(status)")
                return nil
            }
            
            // 5. Lock the base address of the destination buffer for writing.
            guard CVPixelBufferLockBaseAddress(finalPixelBuffer, []) == kCVReturnSuccess else {
                print("Error: Failed to lock destination pixel buffer.")
                return nil
            }
            defer { CVPixelBufferUnlockBaseAddress(finalPixelBuffer, []) }
            
            // 6. Create a vImage_Buffer for the destination.
            guard let dstBaseAddress = CVPixelBufferGetBaseAddress(finalPixelBuffer) else {
                print("Error: Could not get base address of destination pixel buffer.")
                return nil
            }
            var dstBuffer = vImage_Buffer(
                data: dstBaseAddress,
                height: vImagePixelCount(CVPixelBufferGetHeight(finalPixelBuffer)),
                width: vImagePixelCount(CVPixelBufferGetWidth(finalPixelBuffer)),
                rowBytes: CVPixelBufferGetBytesPerRow(finalPixelBuffer)
            )
            
            // 7. Convert the CGAffineTransform to the vImage_AffineTransform struct.
            var vImageTransform = vImage_AffineTransform(
                a: Float(transform.a),
                b: Float(transform.b),
                c: Float(transform.c),
                d: Float(transform.d),
                tx: Float(transform.tx),
                ty: Float(transform.ty)
            )
            
            // 8. Perform the affine warp operation.
            // A background color of transparent black is used for pixels outside the source image.
            var backgroundColor: [Pixel_8] = [0, 0, 0, 0]
            let error = vImageAffineWarp_ARGB8888(
                &srcBuffer,
                &dstBuffer,
                nil,
                &vImageTransform,
                &backgroundColor,
                vImage_Flags(kvImageBackgroundColorFill)
            )
            
            guard error == kvImageNoError else {
                print("Error: vImageAffineWarp failed with error code: \(error)")
                return nil
            }
            
            return finalPixelBuffer
        }
    }
}
