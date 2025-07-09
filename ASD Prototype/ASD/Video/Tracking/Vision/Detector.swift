//
//  Detector.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/21/25.
//

import Foundation
@preconcurrency import Vision
import CoreML
import ImageIO


extension ASD.Tracking {
    final class FaceDetector {
        private static let model: VNCoreMLModel = {
            print("Loading Detector Model...")
            let mlModel = try? YOLOv11n(configuration: MLModelConfiguration())
            let vnModel = try? VNCoreMLModel(for: mlModel!.model)
            print("Loaded Detector model\n")
            return vnModel!
        }()
        
        private var request: VNCoreMLRequest
        private let confidenceThreshold: Float
        
        init(verbose: Bool = false, confidenceThreshold: Float = 0.5) {
            self.request = VNCoreMLRequest(model: FaceDetector.model)
            self.request.imageCropAndScaleOption = .scaleFit
            self.confidenceThreshold = confidenceThreshold
        }
        
        @discardableResult
        func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [VNRecognizedObjectObservation] {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            
            do {
                try handler.perform([self.request])
                guard let results = request.results as? [VNRecognizedObjectObservation] else { return [] }
                return results.filter {$0.confidence > self.confidenceThreshold}
            } catch {
                print("Failed to perform Vision request: \(error)")
                return []
            }
        }
    }
}
