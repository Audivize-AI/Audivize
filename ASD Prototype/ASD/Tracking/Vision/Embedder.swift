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
        private let model: VNCoreMLModel
        private var requests: [VNCoreMLRequest]
        private var expirations: [DispatchTime]
        
        init() {
            self.requests = []
            self.expirations = []
            self.requests.reserveCapacity(FaceProcessingConfiguration.minReadyEmbedderRequests * 2)
            self.expirations.reserveCapacity(FaceProcessingConfiguration.minReadyEmbedderRequests)
           
            let mlModel = try! MobileFaceNet(configuration: MLModelConfiguration())
            self.model = try! VNCoreMLModel(for: mlModel.model)
            
            for _ in 0..<FaceProcessingConfiguration.minReadyEmbedderRequests {
                let r = VNCoreMLRequest(model: self.model)
                r.imageCropAndScaleOption = .scaleFill
                self.requests.append(r)
            }
        }
        
        /// - Parameters:
        ///   - rects normalized detection bounding boxes
        ///   - pixelBuffer image pixelBuffer
        /// - Returns: array of embedding vectors
        /// - Warning: assumes that `self.canEmbed(rect)` is true for all `rect`s in `rects`
        @discardableResult
        public func embed(faces rects: [CGRect], in pixelBuffer: CVPixelBuffer) -> [MLMultiArray] {
            self.refreshRequests(num: rects.count)
            
            let bufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            
            for (request, rect) in zip(requests, rects) {
                let size = max(rect.width * bufferWidth,
                               rect.height * bufferHeight)
                
                let width = size / bufferWidth
                let height = size / bufferHeight
                let halfWidth = width / 2
                let halfHeight = height / 2
                
                request.regionOfInterest = CGRect(
                    x: rect.midX - halfWidth,
                    y: 1 - (rect.midY + halfHeight),
                    width: width,
                    height: height
                ).intersection(.one)
            }
            
            let usedRequests = Array(self.requests[0..<rects.count])
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            
            do {
                try handler.perform(usedRequests)
                return usedRequests.map {
                    let result = $0.results?.first as? VNCoreMLFeatureValueObservation
                    return result!.featureValue.multiArrayValue!
                }
            } catch {
                print ("Error embedding faces: \(error)")
                return []
            }
        }
        
        @inline(__always)
        private func refreshRequests(num: Int) {
            let expirationTime = DispatchTime.now() + FaceProcessingConfiguration.embedderRequestLifespan
            
            // if we are adding more requests then the other requests are also about to get used
            
            let numToAdd = num - self.requests.count
            if numToAdd <= 0 {
                /// The first `minReadyRequests` requests don't have an expiration clock. Only refresh the clocks for those that come after them.
                let numToRefresh = num - FaceProcessingConfiguration.minReadyEmbedderRequests
                if numToRefresh > 0 {
                    for i in (0..<numToRefresh) {
                        self.expirations[i] = expirationTime
                    }
                }
                self.removeExpiredRequests()
            } else {
                self.addRequests(num: numToAdd, expirationTime: expirationTime)
            }
        }
        
        @inline(__always)
        private func addRequests(num: Int, expirationTime: DispatchTime) {
            // if we are adding requests, then we must also be using all the existing ones.
            for i in self.expirations.indices {
                self.expirations[i] = expirationTime
            }
            
            for _ in 0..<num {
                let r = VNCoreMLRequest(model: self.model)
                r.imageCropAndScaleOption = .scaleFit
                self.requests.append(r)
                self.expirations.append(expirationTime)
            }
        }
        
        @inline(__always)
        private func removeExpiredRequests() {
            let now = DispatchTime.now()
            while (self.expirations.last ?? now) < now {
                self.expirations.removeLast()
            }
        }
    }
}
