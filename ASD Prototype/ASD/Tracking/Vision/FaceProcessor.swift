//
//  FaceExtraction.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/19/25.
//

import Vision
import CoreML
import Foundation
import OrderedCollections


extension ASD.Tracking {
    final class FaceProcessor {
        // MARK: private properties
        
        private let detector: FaceDetector
        private let embedder: FaceEmbedder
        
        // MARK: public methods
        
        init() {
            self.detector = FaceDetector()
            self.embedder = FaceEmbedder()
        }
        
        public func detect(pixelBuffer: CVPixelBuffer, transformer: CameraCoordinateTransformer) -> OrderedSet<Detection> {
            let results = self.detector.detect(in: pixelBuffer)
            
            return OrderedSet(results.map {
                let rect = $0.boundingBox
                let box = CGRect(
                    x: rect.minX,
                    y: 1 - rect.maxY,
                    width: rect.width,
                    height: rect.height
                )
//                print("det: \(box.string)")
                return Detection(rect: box, confidence: Float($0.confidence), transformer: transformer)
            })
        }
        
        public func embed(pixelBuffer: CVPixelBuffer, faces detections: OrderedSet<Detection>) {
            let results = self.embedder.embed(faces: detections.map{ $0.rect },
                                              in: pixelBuffer)
            for (det, result) in zip(detections, results) {
                det.embedding = result
            }
        }
    }
}

extension CVPixelBuffer: @unchecked @retroactive Sendable {}
