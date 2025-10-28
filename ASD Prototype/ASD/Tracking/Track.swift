//
//  Track.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/17/25.
//

import Foundation
import Accelerate
import Atomics

extension ASD.Tracking {
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
            case inactive   /// track is not actively in use but has been initialized
            case pending    /// track has not been confirmed
            
            var isActive: Bool { return self == .active }
            var isInactive: Bool { return self == .inactive }
            var isPending: Bool { return self == .pending }
            var isConfirmed: Bool { return self != .pending }
            
            var stringValue: String {
                switch self {
                case .active:
                    return "active"
                case .inactive:
                    return "inactive"
                case .pending:
                    return "pending"
                }
            }
        }
        
        // MARK: public properties
        public static let iteration = ManagedAtomic<UInt>(0)
        
        public let id = UUID()
        public var name: String? = nil
        public private(set) var hits: Int = 1
        public private(set) var rect: CGRect = .zero
        public private(set) var costs: Costs = Costs()
        public private(set) var status: Status = .pending
        public private(set) var embedding: [Float]
        public private(set) var isPermanent: Bool = false
        public private(set) var expectedConfidence: Float = 0.0
        public private(set) var landmarks: [CGPoint] = []
        public var averageAppearanceCost: Float {
            return self.appearanceCostKF.x
        }
        
        // MARK: public computed properties
        public var isDeletable: Bool {
            return (self.status.isPending && self.hits <= 0) || (self.isPermanent == false && self.hits <= -TrackingConfiguration.deletionThreshold)
        }
        
        public var needsEmbeddingUpdate: Bool {
            return self.status.isPending || (self.status.isActive && self.iterationsUntilEmbeddingUpdate <= 0)
        }
        
        public var stringValue: String {
            return "Track \(self.id)"
        }
        
        public var shortString: String {
            return String(self.id.uuidString.prefix(4))
        }
        
        public var iteration: UInt {
            return Track.iteration.load(ordering: .relaxed) &+ UInt(self.id.uuid.0)
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
        /// - Parameter trackConfiguration: trackConfiguration of parent tracker
        /// - Parameter costConfiguration: costConfiguration of parent tracker
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
        
        /// Permanent track constructor
        /// - Parameter id: Track ID
        /// - Parameter embedding: Facial feature embedding
        /// - Parameter trackConfiguration: trackConfiguration of parent tracker
        /// - Parameter costConfiguration: costConfiguration of parent tracker
        /// - Parameter detection: the detection associated with this track (if left blank then the track will initialize as inactive)
        /// - Throws `embeddingDimensionMismatch` when `embedding` does not have the right shape, namely (1,128) or (128,)
        public init(id: UUID,
                    embedding: [Float],
                    transformer: CameraCoordinateTransformer,
                    detection: Detection? = nil) throws {
            self.cameraTransformer = transformer
            self.embedding = vDSP.unitVector(embedding)
            
            if let det = detection {
                self.rect = det.rect
                self.kalmanFilter = VisualKF(initialObservation: det.kfRect)
            } else {
                self.rect = CGRect.zero
                self.kalmanFilter = VisualKF(initialObservation: CGRect.zero)
            }
            
            self.appearanceCostKF = UnivariateKF(
                x: TrackingConfiguration.maxAppearanceCost / 2, // conservative estimate
                Q: TrackingConfiguration.appearanceCostVariance,
                R: TrackingConfiguration.appearanceCostMeasurementVariance
            )
            
            self.iterationsUntilEmbeddingUpdate = TrackingConfiguration.iterationsPerEmbeddingUpdate
            self.isPermanent = true
            if let detection = detection {
                self.expectedConfidence = detection.confidence
                self.lastConfidence = detection.confidence
                self.status = .active
                self.updateEmbedding(detection: detection, appearanceCost: self.cosineDistance(to: detection))
            } else {
                self.status = .inactive
                self.expectedConfidence = 0
            }
        }
        
        // MARK: public static methods
        
        static func == (lhs: Track, rhs: Track) -> Bool {
            return lhs.id == rhs.id // Compare properties
        }
        
        static func nextIteration() -> Void {
            Track.iteration.wrappingIncrement(ordering: .relaxed)
        }
        
        // MARK: public methods
        
        /// Prevent the track from being deleted
        public func retain() {
            self.isPermanent = true
            if self.status.isPending {
                self.status = .active
                self.hits = 0
            }
        }
        
        /// Allow the track to be deleted
        public func release() {
            self.isPermanent = false
        }
        
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
            // register hit
            var wasKfActivated = false
            
            self.landmarks = stride(from: 0, to: 10, by: 2).map { i in
                CGPoint(
                    x: CGFloat(detection.landmarks[i]),
                    y: CGFloat(detection.landmarks[i + 1])
                )
            }
            
            if !self.status.isActive {
                if self.hits < 0 {
                    self.hits = 1
                    self.lastConfidence = detection.confidence
                    self.kalmanFilter.activate(detection.kfRect)
                    wasKfActivated = true
                }
                else if detection.isFullFace {
                    self.hits += 1
                }
                
                // check if the track is ready for activation
                let threshold = (
                    self.status.isPending
                        ? TrackingConfiguration.confirmationThreshold
                        : TrackingConfiguration.activationThreshold
                )
                
                // activate
                if self.hits >= threshold {
                    self.hits = 0
                    if status.isInactive {
                        self.kalmanFilter.activate(detection.kfRect)
                        self.rect = detection.rect
                        wasKfActivated = true
                    }
                    self.status = .active
                    
                    var minDist: Float = 0.4
                    
                    for (name, emb) in ASD.Faces.faces {
                        let dist = 1 - vDSP.dot(emb, self.embedding)
                        if dist < minDist {
                            self.name = name
                            minDist = dist
                        }
                    }
                }
            } else {
                self.hits = 0
            }
            
            if self.kalmanFilter.isValid == false {
                self.kalmanFilter.activate(detection.kfRect)
                self.rect = detection.rect
                wasKfActivated = true
            } else if wasKfActivated == false {
                // update state
                self.kalmanFilter.update(measurement: detection.kfRect)
                self.rect = detection.rect // self.cameraTransformer.toTrackCoordinates(self.kalmanFilter.rect)
            }
            //print("\(self.shortString): valid = \(self.kalmanFilter.isValid), kf rect = \(self.kalmanFilter.rect), rect = \(self.rect), detection: \(detection.rect)")
            
            // update confidence
            self.lastConfidence2 = self.lastConfidence
            self.lastConfidence = detection.confidence
            
            if let lastConfidence2 = self.lastConfidence2, let lastConfidence = self.lastConfidence {
                self.expectedConfidence = lastConfidence - (lastConfidence2 - lastConfidence)
            }
            
            /*  If the appearance cost was calculated then the detection's embedding must   *
             *  have also been computed. This is because the embedding is necessary to      *
             *  compute the appearance cost. Also, don't update embedding when inactive.    */
            if self.status.isInactive == false && costs.hasAppearance && detection.isFullFace {
                self.updateEmbedding(detection: detection, appearanceCost: costs.appearance)
            }
            
            self.costs = costs
        }
        
        /// Registers that this track was not assigned a detection
        func registerMiss() {
            if self.status.isActive {
                self.hits -= 1
                if self.hits <= -TrackingConfiguration.deactivationThreshold || !self.kalmanFilter.isValid {
                    self.status = .inactive
                    self.kalmanFilter.deactivate()
                    self.hits = 0
//                    print("\(self.id): \(self.embedding)")
                } else {
                    self.kalmanFilter.xVelocity *= TrackingConfiguration.velocityDamping
                    self.kalmanFilter.yVelocity *= TrackingConfiguration.velocityDamping
                    self.kalmanFilter.growthRate *= TrackingConfiguration.growthDamping
                }
            } else if self.status.isInactive {
                self.hits -= 1
            } else {
                self.hits = 0
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
    }
}
