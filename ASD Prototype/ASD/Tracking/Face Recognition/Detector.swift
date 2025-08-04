//
//  Detector.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/21/25.
//

import Foundation
import Vision
import CoreML
import ImageIO
import Accelerate
import Metal
import MetalPerformanceShaders

extension ASD.Tracking {
    final class FaceDetector {
        struct Prediction {
            public let confidence: Float
            public let boundingBox: CGRect
            public let landmarks: [Float]
        }
        
        // MARK: Precomputed transform factors
        // landmark transform
        private static let width = Float(CaptureConfiguration.videoWidth)
        private static let height = Float(CaptureConfiguration.videoHeight)
        
        private static let modelInputSize: (width: Int, height: Int) = (512, 288)
        private static let modelHWRatio = Float(modelInputSize.height) / Float(modelInputSize.width)
        
        private static let landmarkScale = [[Float]](
            repeating: [width, -width * modelHWRatio],
            count: 5
        ).flatMap{$0}
        
        private static let landmarkOffset = [[Float]](
            repeating: [0, (height + width * modelHWRatio) / 2],
            count: 5
        ).flatMap{$0}

        // box scale
        private static let boxYScale: Float = width / height * modelHWRatio
        private static let boxYOffset: Float = (1 - boxYScale) / 2
        
        // MARK: Private attributes
        private let model: SCRFD_512x288
        
        // MARK: Constructors
        init() {
            print("DEBUG: Loading SCRFD model...")
            self.model = try! SCRFD_512x288(configuration: MLModelConfiguration())
            print("DEBUG: RETRIEVED SCRFD model.")
        }
        
        // MARK: Public methods
        public func detect(in pixelBuffer: CVPixelBuffer) -> [Prediction] {
            let width = Float(CVPixelBufferGetWidth(pixelBuffer))
            let height = Float(CVPixelBufferGetHeight(pixelBuffer))
            precondition(width > height)
            
//            let start = Date()
            guard let resized = self.scaleFit(pixelBuffer: pixelBuffer, toSize: FaceDetector.modelInputSize),
                  let results = try? self.model.prediction(image: resized) else {
                return []
            }
            
//            let end = Date()
//            print("Detection Time: \(1000 * end.timeIntervalSince(start)) seconds")
                
            let confidences = results.confidenceShapedArray
            var predictions: [Prediction] = []
            predictions.reserveCapacity(confidences.count)
            
            // do nothing if no faces are detected.
            if let onlyConfidence = confidences.scalar, onlyConfidence < 0.0 {
                print("no faces found")
                return []
            }
            
            let coordinates = results.coordinatesShapedArray
            let landmarks = results.landmarksShapedArray
            
            // transform landmarks and boxes
            for (confidence, (box, kps)) in zip(confidences, zip(coordinates, landmarks)) {
                let box = box.scalars
                let bbox = CGRect(x: CGFloat(box[0]),
                                  y: CGFloat(box[1] * FaceDetector.boxYScale + FaceDetector.boxYOffset),
                                  width: CGFloat(box[2]),
                                  height: CGFloat(box[3] * FaceDetector.boxYScale))
                
                let points = vDSP.add(vDSP.multiply(kps.scalars, FaceDetector.landmarkScale),
                                      FaceDetector.landmarkOffset)
                
                let score = confidence.scalar!
                
                predictions.append(.init(confidence: score,
                                         boundingBox: bbox,
                                         landmarks: points))
            }
            return predictions
        }
        
        /// Scales a CVPixelBuffer to a new size using the vImage framework.
        ///
        /// - Parameters:
        ///   - pixelBuffer: The input CVPixelBuffer to scale. The format is expected to be 32BGRA.
        ///   - toSize: The target CGSize for the output pixel buffer.
        /// - Returns: A new, scaled CVPixelBuffer of the specified size, or nil if the scaling operation fails.
        /// - Throws: An error if any of the vImage operations fail.
        func scaleFit(pixelBuffer: CVPixelBuffer, toSize size: (width: Int, height: Int)) -> CVPixelBuffer? {
            
            // 1. Lock the base address of the source pixel buffer.
            // This ensures that the pixel data is not modified by another process during the operation.
            guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
                print("Error: Could not lock source pixel buffer base address.")
                return nil
            }
            
            // Defer unlocking the buffer to ensure it's always released.
            defer {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            }

            // 2. Get the source buffer's properties.
            guard let sourceBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                print("Error: Could not get source pixel buffer base address.")
                return nil
            }
            let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
            let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
            let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            
            // 3. Create a vImage_Buffer for the source pixel buffer.
            // This structure describes the memory layout of the image data.
            var sourceBuffer = vImage_Buffer(data: sourceBaseAddress,
                                             height: vImagePixelCount(sourceHeight),
                                             width: vImagePixelCount(sourceWidth),
                                             rowBytes: sourceBytesPerRow)

            // 4. Create the destination pixel buffer.
            let destPixelBufferOptions: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            var destPixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                             size.width,
                                             size.height,
                                             kCVPixelFormatType_32BGRA,
                                             destPixelBufferOptions as CFDictionary,
                                             &destPixelBuffer)

            guard status == kCVReturnSuccess, let unwrappedDestPixelBuffer = destPixelBuffer else {
                print("Error: Could not create destination pixel buffer. Status: \(status)")
                return nil
            }
            
            // 5. Lock the base address of the destination pixel buffer.
            guard CVPixelBufferLockBaseAddress(unwrappedDestPixelBuffer, []) == kCVReturnSuccess else {
                print("Error: Could not lock destination pixel buffer base address.")
                return nil
            }
            
            // Defer unlocking the destination buffer.
            defer {
                CVPixelBufferUnlockBaseAddress(unwrappedDestPixelBuffer, [])
            }
            
            // 6. Get the destination buffer's properties and create a vImage_Buffer.
            guard let destBaseAddress = CVPixelBufferGetBaseAddress(unwrappedDestPixelBuffer) else {
                print("Error: Could not get destination pixel buffer base address.")
                return nil
            }
            let destBytesPerRow = CVPixelBufferGetBytesPerRow(unwrappedDestPixelBuffer)
            
            var destBuffer = vImage_Buffer(data: destBaseAddress,
                                           height: vImagePixelCount(size.height),
                                           width: vImagePixelCount(size.width),
                                           rowBytes: destBytesPerRow)

            // 7. Perform the scaling operation.
            // vImageScale_ARGB8888 is highly optimized for this pixel format.
            // kvImageHighQualityResampling provides better quality than the default.
            let scaleError = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))

            guard scaleError == kvImageNoError else {
                print("Error: vImageScale failed with error code: \(scaleError)")
                return nil
            }

            // 8. Return the new, scaled pixel buffer.
            return unwrappedDestPixelBuffer
        }
    }
}

protocol SCRFDOutput {
    var confidence: MLMultiArray { get }
    var confidenceShapedArray: MLShapedArray<Float> { get }
    var coordinates: MLMultiArray { get }
    var coordinatesShapedArray: MLShapedArray<Float> { get }
    var landmarks: MLMultiArray { get }
    var landmarksShapedArray: MLShapedArray<Float> { get }
}

protocol SCRFD {
    associatedtype Output: SCRFDOutput
    func prediction(image: CVPixelBuffer) throws -> Output
}

extension SCRFD_512x288Output: SCRFDOutput {}
extension SCRFD_512x384Output: SCRFDOutput {}

extension SCRFD_512x288: SCRFD {
    typealias Output = SCRFD_512x288Output
}

extension SCRFD_512x384: SCRFD {
    typealias Output = SCRFD_512x384Output
}
