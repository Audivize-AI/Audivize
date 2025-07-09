//
//  Embedder.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/21/25.
//

import Foundation
@preconcurrency import Vision
import CoreML
import ImageIO

extension ASD.Tracking {
    final class FaceEmbedder {
        private static let model: VNCoreMLModel = {
            print("Loading Embedder Model...")
            let mlModel = try? MobileFaceNet(configuration: MLModelConfiguration())
            let vnModel = try? VNCoreMLModel(for: mlModel!.model)
            print("Loaded Embedder model\n")
            return vnModel!
        }()
        
        private let minReadyRequests: Int
        private var requests: [VNCoreMLRequest]
        private var expirations: [DispatchTime]
        private let requestLifespan: DispatchTimeInterval
        
        init(verbose: Bool = false, requestLifespan: DispatchTimeInterval = .seconds(5), minReadyRequests: Int = 8) {
            self.requestLifespan = requestLifespan
            self.minReadyRequests = minReadyRequests
            self.requests = []
            self.expirations = []
            self.requests.reserveCapacity(minReadyRequests * 2)
            self.expirations.reserveCapacity(minReadyRequests)
            
            for _ in 0..<minReadyRequests {
                let r = VNCoreMLRequest(model: FaceEmbedder.model)
                r.imageCropAndScaleOption = .scaleFill
                self.requests.append(r)
            }
        }
        
        @discardableResult
        func embed(faces rects: [CGRect], in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [MLMultiArray] {
            self.refreshRequests(num: rects.count)
            
            let maxRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            for (request, rect) in zip(requests, rects) {
                
                request.regionOfInterest = rect.intersection(maxRect)
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
            let expirationTime = DispatchTime.now() + self.requestLifespan
            
            // if we are adding more requests then the other requests are also about to get used
            
            let numToAdd = num - self.requests.count
            if numToAdd <= 0 {
                /// The first `minReadyRequests` requests don't have an expiration clock. Only refresh the clocks for those that come after them.
                let numToRefresh = num - self.minReadyRequests
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
                let r = VNCoreMLRequest(model: FaceEmbedder.model)
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
