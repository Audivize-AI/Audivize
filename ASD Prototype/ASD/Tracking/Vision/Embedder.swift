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

extension ASD.Tracking {
    final class FaceEmbedder {
        private let embedderModel: MobileFaceNetV2
        
        init() {
            print("DEBUG: Loading GhostFaceNet model...")
            self.embedderModel = try! MobileFaceNetV2(configuration: MLModelConfiguration())
            print("DEBUG: RETRIEVED GhostFaceNet model.")
        }
        
        /// - Parameters:
        ///   - detections array of face detection objects
        ///   - pixelBuffer image pixelBuffer
        public func embed(faces detections: any Sequence<Detection>,
                          in pixelBuffer: CVPixelBuffer) {            
            for detection in detections {
                let transform = Alignment.computeAlignTransform(detection.landmarks)
                if let alignedImage = Alignment.warpImage(pixelBuffer,
                                                          with: transform,
                                                          size: (224, 224)) {
                    let input = MobileFaceNetV2Input(input_image: alignedImage)
                    let start = Date()
                    detection.embedding = try? self.embedderModel.prediction(input: input)
                        .var_854ShapedArray.scalars
                    let end = Date()
                    print("DEBUG: Embedding time: \(end.timeIntervalSince(start)) seconds.")
                }
            }
        }
    }
}

extension VNCoreMLModel: MLWrapper {}
