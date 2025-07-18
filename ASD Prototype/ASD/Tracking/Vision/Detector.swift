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


extension ASD.Tracking {
    final class FaceDetector {
        struct Prediction {
            public let confidence: Float
            public let boundingBox: CGRect
            public let landmarks: [Float]
        }
        
        private let model: VNCoreMLModel
        private let request: VNCoreMLRequest
        
        init() {
            print("DEBUG: Loading SCRFD model...")
            let mlModel = try! SCRFD(configuration: MLModelConfiguration())
            self.model = try! VNCoreMLModel(for: mlModel.model)
            print("DEBUG: RETRIEVED SCRFD model.")
            self.request = VNCoreMLRequest(model: self.model)
            self.request.imageCropAndScaleOption = .scaleFit
        }
        
        func detect(in pixelBuffer: CVPixelBuffer) -> [Prediction] {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            let width = Float(CVPixelBufferGetWidth(pixelBuffer))
            let height = Float(CVPixelBufferGetHeight(pixelBuffer))
            precondition(width > height)
            

            do {
                try handler.perform([self.request])
                var predictions: [Prediction] = []
                
                // landmark scale
                let xScale: Float = width
                let yScale: Float = -width
                let xOffset: Float = 0.0
                let yOffset: Float = (height + width) / 2
                let landmarkScale = [[Float]](repeating: [xScale, yScale], count: 5).flatMap{$0}
                let landmarkOffset = [[Float]](repeating: [xOffset, yOffset], count: 5).flatMap {$0}

                // box scale
                let boxYScale: Float = width / height
                let boxYOffset: Float = (1 - boxYScale) / 2
                
                // This is guarunteed to work. Force unwrapping is safe.
                let results = self.request.results as! [VNCoreMLFeatureValueObservation]
                let confidences = results[2].featureValue.shapedArrayValue(of: Float.self)!
                let coordinates = results[1].featureValue.shapedArrayValue(of: Float.self)!
                let landmarks = results[0].featureValue.shapedArrayValue(of: Float.self)!
                
                // transform landmarks and boxes
                for (confidence, (box, kps)) in zip(confidences, zip(coordinates, landmarks)) {
                    let box = box.scalars
                    let bbox = CGRect(x: CGFloat(box[0]),
                                      y: CGFloat(box[1] * boxYScale + boxYOffset),
                                      width: CGFloat(box[2]),
                                      height: CGFloat(box[3] * boxYScale))
                    
                    let points = vDSP.add(vDSP.multiply(kps.scalars, landmarkScale), landmarkOffset)
                    let score = confidence.scalar!
                    
                    predictions.append(.init(confidence: score,
                                             boundingBox: bbox,
                                             landmarks: points))
                }
                return predictions
            } catch {
                print("Detector error:", error)
                return []
            }
        }
    }
}

