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
        
        init (verbose: Bool = false,
              detectorConfidenceThreshold: Float = detectorConfidenceThreshold,
              embedderRequestLifespan: DispatchTimeInterval = embedderRequestLifespan,
              minReadyEmbedderRequests: Int = minReadyEmbedderRequests) {
            self.detector = FaceDetector(verbose: verbose, confidenceThreshold: detectorConfidenceThreshold)
            self.embedder = FaceEmbedder(verbose: verbose, requestLifespan: embedderRequestLifespan, minReadyRequests: minReadyEmbedderRequests)
        }
        
        public func detect(pixelBuffer: CVPixelBuffer) -> OrderedSet<Detection> {
            let results = self.detector.detect(in: pixelBuffer)
            
            return OrderedSet(results.map {
                let rect = $0.boundingBox
                let box = CGRect(
                    x: rect.minX - rect.width * 0.2,
                    y: 1 - rect.maxY,
                    width: rect.width * 1.4,
                    height: rect.height
                )
                return Detection(rect: box, confidence: Float($0.confidence))
            })
        }
        
        public func embed(pixelBuffer: CVPixelBuffer, faces detections: OrderedSet<Detection>) {
            let results = self.embedder.embed(faces: detections.map{$0.rect}, in: pixelBuffer)
            
            for (i, result) in results.enumerated() {
                detections[i].embedding = result
            }
        }
    }
}

extension CVPixelBuffer: @unchecked @retroactive Sendable {}


