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


extension ASD.Tracking {
    final class FaceDetector {
        private let model: VNCoreMLModel
        private let request: VNCoreMLRequest
        
        init() {
            print("DEBUG: Loading YOLOv11n model...")
            let mlModel = try! YOLOv11n(configuration: MLModelConfiguration())
            self.model = try! VNCoreMLModel(for: mlModel.model)
            print("DEBUG: RETRIEVED YOLOv11n model.")
            self.request = VNCoreMLRequest(model: self.model)
            self.request.imageCropAndScaleOption = .scaleFit
        }
        
        @discardableResult
        func detect(in pixelBuffer: CVPixelBuffer) -> [VNRecognizedObjectObservation] {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            
            do {
                try handler.perform([self.request])
                guard let results = request.results as? [VNRecognizedObjectObservation] else { return [] }
                let filteredResults: [VNRecognizedObjectObservation] = results.filter {
                    $0.confidence > FaceProcessingConfiguration.minDetectionConfidence
                }
                return filteredResults
            } catch {
                print("Failed to perform Vision request: \(error)")
                return []
            }
        }
    }
}
