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
        
        // MARK: Precomputed transform factors
        // landmark transform
        private static let width = Float(Global.videoWidth)
        private static let height = Float(Global.videoHeight)
        
        private static let landmarkScale = [[Float]](
            repeating: [width, -width],
            count: 5
        ).flatMap{$0}
        
        private static let landmarkOffset = [[Float]](
            repeating: [0, (height+width)/2],
            count: 5
        ).flatMap{$0}

        // box scale
        private static let boxYScale: Float = width / height
        private static let boxYOffset: Float = (1 - boxYScale) / 2
        
        // MARK: Private attributes
        private let model: VNCoreMLModel
        private let request: VNCoreMLRequest
        
        // MARK: Constructors
        init() {
            print("DEBUG: Loading SCRFD model...")
            let mlModel = try! SCRFD(configuration: MLModelConfiguration())
            self.model = try! VNCoreMLModel(for: mlModel.model)
            print("DEBUG: RETRIEVED SCRFD model.")
            self.request = VNCoreMLRequest(model: self.model)
            self.request.imageCropAndScaleOption = .scaleFit
        }
        
        // MARK: Public methods
        public func detect(in pixelBuffer: CVPixelBuffer) -> [Prediction] {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            let width = Float(CVPixelBufferGetWidth(pixelBuffer))
            let height = Float(CVPixelBufferGetHeight(pixelBuffer))
            precondition(width > height)
            
            
            guard let _ = try? handler.perform([self.request]) else {
                return []
            }
                
            var predictions: [Prediction] = []
            predictions.reserveCapacity(self.request.results!.count)
            
            // This is guarunteed to work. Force unwrapping is safe.
            let results = self.request.results as! [VNCoreMLFeatureValueObservation]
            let confidences = results[2].featureValue.shapedArrayValue(of: Float.self)!
            let coordinates = results[1].featureValue.shapedArrayValue(of: Float.self)!
            let landmarks = results[0].featureValue.shapedArrayValue(of: Float.self)!
            
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
    }
}

