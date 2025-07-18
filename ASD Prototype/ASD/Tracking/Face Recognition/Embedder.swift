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
        private let embedderModel: GhostFaceNet
        
        init() {
            print("DEBUG: Loading GhostFaceNet model...")
            self.embedderModel = try! GhostFaceNet(configuration: MLModelConfiguration())
            print("DEBUG: RETRIEVED GhostFaceNet model.")
        }
        
        /// - Parameters:
        ///   - detections array of face detection objects
        ///   - pixelBuffer image pixelBuffer
        public func embed(faces detections: any Sequence<Detection>,
                          in pixelBuffer: CVPixelBuffer) {            
            for detection in detections {
                let transform = FaceEmbedder.computeAlignTransform(detection.landmarks)
                if let alignedImage = FaceEmbedder.warpImage(pixelBuffer, with: transform) {
                    let input = GhostFaceNetInput(image: alignedImage)
                    detection.embedding = try? self.embedderModel.prediction(input: input)
                        .embeddingShapedArray.scalars
                }
            }
        }
        
        /// - Parameter landmarks aligned landmark points
        /// - Returns the bin indices that the face orientation falls under
        public func computeBin(from landmarks: [Float]) -> [(Int, Int)] {
            return []
        }
    }
}

extension VNCoreMLModel: MLWrapper {}
