//
//  Track.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/17/25.
//

import Foundation
import Accelerate
import Atomics

extension Pairing.Tracking {
    final class Track:
        Identifiable,
        Hashable,
        Equatable
    {
        // MARK: public enums
        enum TrackInitializationError: Error {
            case missingEmbedding
            case embeddingDimensionMismatch
        }
        
        enum Status {
            case active     /// track is actively in use
            case pending    /// track has not been confirmed
            case terminated /// track is awaiting termination
            
            var isActive: Bool { return self == .active }
            var isPending: Bool { return self == .pending }
            var isAlive: Bool { return self != .terminated }
            var isTerminated: Bool { return self == .terminated }
            
            var stringValue: String {
                switch self {
                case .active:
                    return "active"
                case .pending:
                    return "pending"
                case .terminated:
                    return "terminated"
                }
            }
        }
        
        // MARK: public properties
        public let id = UUID()
        public var name: String? = nil
        public private(set) var rect: CGRect
        public private(set) var embedding: [Float]
        public private(set) var expectedConfidence: Float
        public private(set) var stateTransitionCounter: Int = 1
        public private(set) var costs: Costs = Costs()
        public private(set) var status: Status = .pending
        
        // MARK: public computed properties
        public var averageAppearanceCost: Float { return self.appearanceCostKF.x }
        public var isDeletable: Bool { return self.status.isTerminated }
        public var stringValue: String { return "Track \(self.id)" }
        public var shortString: String { return String(self.id.uuidString.prefix(4)) }
        public var needsEmbeddingUpdate: Bool {
            return self.status.isPending || (self.status.isActive && self.iterationsUntilEmbeddingUpdate <= 0)
        }
        
        // MARK: private properties        
        private let cameraTransformer: CameraCoordinateTransformer
        private let kalmanFilter: VisualKF
        
        private var iterationsUntilEmbeddingUpdate: Int
        private var lastConfidence: Float?
        private var lastConfidence2: Float?
         
        private var appearanceCostKF: UnivariateKF
        
        // MARK: constructors
        
        /// Track constructor
        /// - Parameter detection: `Detection` object that was assigned to this track
        /// - Parameter transformer: coordinate transformer
        /// - Throws: `TrackInitializationError.missingEmbedding` when `detection`'s embedding is `nil`
        public init(detection: Detection,
                    transformer: CameraCoordinateTransformer) throws {
            guard let embedding = detection.embedding else {
                throw TrackInitializationError.missingEmbedding
            }
            
            self.embedding = vDSP.unitVector(embedding)
            self.iterationsUntilEmbeddingUpdate = TrackingConfiguration.iterationsPerEmbeddingUpdate
            
            self.appearanceCostKF = UnivariateKF(
                x: TrackingConfiguration.maxAppearanceCost / 2, // conservative estimate
                Q: TrackingConfiguration.appearanceCostVariance,
                R: TrackingConfiguration.appearanceCostMeasurementVariance
            )
            
            self.kalmanFilter = VisualKF(initialObservation: detection.kfRect)
            self.cameraTransformer = transformer
            self.rect = detection.rect
            
            self.lastConfidence = detection.confidence
            self.expectedConfidence = detection.confidence
        }
        
        deinit {
            debugPrint("Track deinit: \(self.id)")
        }
        
        // MARK: public static methods
        
        static func == (lhs: Track, rhs: Track) -> Bool {
            return lhs.id == rhs.id // Compare properties
        }
        
        // MARK: public methods
        
        /// Run the Kalman filter's prediction step and record that another iteration has started.
        @inline(__always)
        func predict() {
            self.kalmanFilter.predict()
            self.rect = self.cameraTransformer.toTrackCoordinates(self.kalmanFilter.rect)
            self.iterationsUntilEmbeddingUpdate -= 1
        }
        
        /// Registers that this track was assigned a detection
        /// - Parameter detection: `Detection` object that was assigned to this track
        /// - Parameter costs: `Costs` object associated with the assignment.
        func registerHit(with detection: Detection, costs: Costs) {
            guard status.isAlive else { return }
            
            if self.status.isPending {
                if detection.isFullFace { self.stateTransitionCounter += 1 }
                
                // activate
                if self.stateTransitionCounter >= TrackingConfiguration.confirmationThreshold {
                    self.stateTransitionCounter = 0
                    self.status = .active
                    self.assignName()
                }
            } else {
                // reset miss counter
                self.stateTransitionCounter = 0
            }
            
            if self.kalmanFilter.isValid { // update state
                self.kalmanFilter.update(measurement: detection.kfRect)
                self.rect = cameraTransformer.toTrackCoordinates(kalmanFilter.rect)
            } else { // fix invalid KF
                self.kalmanFilter.activate(detection.kfRect)
                self.rect = detection.rect
            }
           
            // update confidence
            self.lastConfidence2 = self.lastConfidence
            self.lastConfidence = detection.confidence
            
            if let lastConfidence2 = self.lastConfidence2, let lastConfidence = self.lastConfidence {
                self.expectedConfidence = lastConfidence - (lastConfidence2 - lastConfidence)
            }
            
            // update appearance cost if needed
            if costs.hasAppearance && detection.isFullFace {
                self.updateEmbedding(detection: detection, appearanceCost: costs.appearance)
            }
            
            self.costs = costs
        }
        
        /// Registers that this track was not assigned a detection
        func registerMiss() {
            guard status.isAlive else { return }
            
            if self.status.isActive {
                self.stateTransitionCounter += 1
                
                // terminate track
                if self.stateTransitionCounter >= TrackingConfiguration.deactivationThreshold || !self.kalmanFilter.isValid {
                    self.status = .terminated
                } else {
                    self.kalmanFilter.xVelocity *= TrackingConfiguration.velocityDamping
                    self.kalmanFilter.yVelocity *= TrackingConfiguration.velocityDamping
                    self.kalmanFilter.growthRate *= TrackingConfiguration.growthDamping
                }
            } else {
                self.status = .terminated
            }
        }
        
        /// Returns cosine distance between the feature embedding vectors
        /// - Parameter detection: `Detection` object whose appearance is being compared
        /// - Returns: cosine distance between this track's embedding vector and `detection`'s embedding vector
        @inline(__always)
        func cosineDistance(to detection: Detection) -> Float {
            if let detectionEmbedding = detection.embedding {
                return self.cosineDistance(to: detectionEmbedding)
            }
            return 2.0
        }
        
        /// Returns cosine distance between the feature embedding vectors
        /// - Parameter embedding: embedding to compare
        /// - Returns: cosine distance between this track's embedding vector and the provided `embedding` vector
        @inline(__always)
        func cosineDistance(to embedding: [Float]) -> Float {
            let dot = vDSP.dot(self.embedding, embedding)
            let denominator = sqrt(vDSP.sumOfSquares(self.embedding) * vDSP.sumOfSquares(embedding))
            if denominator != 0 {
                return 1.0 - dot / denominator
            }
            // return the maximum value of cosine distance
            return 2.0
        }
        
        /// Returns intersection over union
        /// - Parameter detection: `Detection` object that was assigned to this track
        /// - Returns: intersection over union of the track's rect with `detection`'s rect
        @inline(__always)
        func iou(with detection: Detection) -> Float {
            return Utils.iou(self.kalmanFilter.rect, detection.kfRect)
        }
        
        @inline(__always)
        func confidenceCost(for detection: Detection) -> Float {
            return abs(self.expectedConfidence - detection.confidence)
        }
        
        @inline(__always)
        func velocityCost(for detection: Detection) -> Float {
            return self.kalmanFilter.velocityCost(to: detection.kfRect)
        }
        
        @inline(__always)
        func mahaCost(for detection: Detection) -> Float {
            return sqrt(self.kalmanFilter.mahalanobisDistance(to: detection.kfRect))
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        /// Updates the embedding
        /// - Parameter detection: detection object that was assigned to this track
        /// - Parameter appearanceCost: appearance cost of the assignment
        func updateEmbedding(detection: Detection, appearanceCost: Float) {
            // confidence cutoff
            let conf = detection.confidence
                               
            let minConf = TrackingConfiguration.embeddingConfidenceThreshold
            if conf < minConf {
                return
            }
            
            guard var newEmbedding = detection.embedding else {
                return
            }
            
            // normalize the new embedding
            vDSP.unitVector(newEmbedding, result: &newEmbedding)
            
            var alpha = TrackingConfiguration.embeddingAlpha
            alpha *= (conf - minConf) / (1.0 - minConf)
            alpha *= exp(-appearanceCost / (self.averageAppearanceCost + 1e-10))
            self.appearanceCostKF.step(measurement: appearanceCost)
            vDSP.add(self.embedding,
                     vDSP.multiply(alpha, vDSP.subtract(newEmbedding, self.embedding)),
                     result: &self.embedding)
            
            // renormalize
            vDSP.unitVector(embedding, result: &embedding)
            
            self.iterationsUntilEmbeddingUpdate = TrackingConfiguration.iterationsPerEmbeddingUpdate
        }
        
        private func assignName() {
            var minDist: Float = 0.5
            
            for (name, emb) in Pairing.Faces.faces {
                let dist = 1 - vDSP.dot(emb, self.embedding)
                if dist < minDist {
                    self.name = name
                    minDist = dist
                }
            }
        }
    }
}
