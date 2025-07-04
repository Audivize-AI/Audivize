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
        private let confidenceThreshold: Float
        private let request: VNCoreMLRequest
        
        init(verbose: Bool = false,
             confidenceThreshold: Float = detectorConfidenceThreshold)
        {
            if verbose {
                print("Loading Face Detector model...")
            }
            
            do {
                let mlModel = try YOLOv11n(configuration: MLModelConfiguration())
                self.model = try VNCoreMLModel(for: mlModel.model)
            } catch {
                fatalError("Failed to load Face Detector model: \(error.localizedDescription)")
            }
            
            if verbose {
                print("Loaded Face Detector model\n")
            }
            
            self.request = VNCoreMLRequest(model: self.model)
            self.request.imageCropAndScaleOption = .scaleFit
            self.confidenceThreshold = confidenceThreshold
        }
        
        @discardableResult
        func detect(in pixelBuffer: CVPixelBuffer) -> [VNRecognizedObjectObservation] {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            
            do {
                try handler.perform([self.request])
                guard let results = request.results as? [VNRecognizedObjectObservation] else { return [] }
                let filteredResults: [VNRecognizedObjectObservation] = results.filter {
                    $0.confidence > self.confidenceThreshold
                }
                print("Face detections: \(results.count).\t Filtered face detections: \(filteredResults.count)")
                return filteredResults
            } catch {
                print("Failed to perform Vision request: \(error)")
                return []
            }
        }
    }
}
