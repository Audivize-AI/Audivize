//
//  FaceExtraction.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/19/25.
//

import Vision
@preconcurrency import CoreML
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
            
            return OrderedSet(results.map { pred in
                Detection(rect: pred.boundingBox,
                          confidence: pred.confidence,
                          transformer: transformer,
                          landmarks: pred.landmarks)
            })
        }
        
        public func embed(detections: any Sequence<Detection>, in pixelBuffer: CVPixelBuffer) {
            self.embedder.embed(detections: detections, in: pixelBuffer)
        }
    }
}

extension CVPixelBuffer: @unchecked @retroactive Sendable {}
