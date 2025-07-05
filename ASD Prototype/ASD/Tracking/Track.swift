//
//  Track.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/17/25.
//

import CoreML
import Foundation
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
        
        public let id = UUID()
        
        public private(set) var hits: Int = 1
        public private(set) var rect: CGRect = .zero
        public private(set) var costs: Costs = Costs()
        public private(set) var status: Status = .pending
        public private(set) var embedding: MLMultiArray
        public private(set) var averageAppearanceCost: Float
        public private(set) var isPermanent: Bool = false
        public private(set) var expectedConfidence: Float = 0.0
        
        // MARK: public computed properties
        public var isDeletable: Bool {
            return (self.status.isPending && self.hits <= 0) || (self.isPermanent == false && self.hits <= -self.configuration.deletionThreshold)
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
        
        // MARK: private properties
        
        nonisolated(unsafe) private static var numTracks: Int = 0
        
        private let configuration: TrackConfiguration
        private let cameraTransformer: CameraCoordinateTransformer
        private let kalmanFilter: VisualKF
        
        private var iterationsUntilEmbeddingUpdate: Int
        private var lastConfidence: Float?
        private var lastConfidence2: Float?
        
        // MARK: constructors
        
        /// Track constructor
        /// - Parameter detection: `Detection` object that was assigned to this track
        /// - Parameter trackConfiguration: trackConfiguration of parent tracker
        /// - Parameter costConfiguration: costConfiguration of parent tracker
        /// - Throws: `TrackInitializationError.missingEmbedding` when `detection`'s embedding is `nil`
        public init(detection: Detection,
                    transformer: CameraCoordinateTransformer,
                    trackConfiguration: TrackConfiguration,
                    costConfiguration: CostConfiguration) throws {
            guard let embedding = detection.embedding else {
                throw TrackInitializationError.missingEmbedding
            }
            self.embedding = embedding
            self.averageAppearanceCost = costConfiguration.maxAppearanceCost / 2 // conservative estimate
            self.iterationsUntilEmbeddingUpdate = trackConfiguration.iterationsPerEmbeddingUpdate
            self.configuration = trackConfiguration
            self.lastConfidence = detection.confidence
            self.expectedConfidence = detection.confidence
            self.cameraTransformer = transformer
            self.kalmanFilter = VisualKF(initialObservation: detection.kfRect)
            self.rect = detection.rect
            Track.numTracks += 1
            print("Track \(self.id) initialized. Total tracks: \(Track.numTracks)")
        }
        
        /// Permanent track constructor
        /// - Parameter id: Track ID
        /// - Parameter embedding: Facial feature embedding
        /// - Parameter trackConfiguration: trackConfiguration of parent tracker
        /// - Parameter costConfiguration: costConfiguration of parent tracker
        /// - Parameter detection: the detection associated with this track (if left blank then the track will initialize as inactive)
        /// - Throws `embeddingDimensionMismatch` when `embedding` does not have the right shape, namely (1,128) or (128,)
        public init(id: UUID,
                    embedding: MLMultiArray,
                    transformer: CameraCoordinateTransformer,
                    trackConfiguration: TrackConfiguration,
                    costConfiguration: CostConfiguration,
                    detection: Detection? = nil) throws {
            if embedding.shape.last != 128 || embedding.count != 128 {
                throw TrackInitializationError.embeddingDimensionMismatch
            }
            self.cameraTransformer = transformer
            self.embedding = embedding
            
            if let det = detection {
                self.rect = det.rect
                self.kalmanFilter = VisualKF(initialObservation: det.kfRect)
            } else {
                self.rect = CGRect.zero
                self.kalmanFilter = VisualKF(initialObservation: CGRect.zero)
            }
            
            self.averageAppearanceCost = costConfiguration.maxAppearanceCost / 2
            self.iterationsUntilEmbeddingUpdate = trackConfiguration.iterationsPerEmbeddingUpdate
            self.configuration = trackConfiguration
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
            Track.numTracks += 1
            print("Track \(self.id) initialized. Total tracks: \(Track.numTracks)")
        }
        
        deinit {
            Track.numTracks -= 1
            print("Track \(self.id) deinitialized. Total tracks: \(Track.numTracks)")
        }
        
        
        // MARK: public static methods
        
        static func == (lhs: Track, rhs: Track) -> Bool {
            return lhs.id == rhs.id // Compare properties
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
            
            if !self.status.isActive {
                if self.hits < 0 {
                    self.hits = 1
                } else {
                    self.hits += 1
                }
                
                // check if the track is ready for activation
                let threshold = (
                    self.status.isPending ?
                    self.configuration.confirmationThreshold :
                    self.configuration.activationThreshold
                )
                
                if self.hits >= threshold {
                    self.hits = 0
                    if status.isInactive {
                        self.kalmanFilter.activate(detection.kfRect)
                        self.rect = detection.rect
                        self.status = .active
                    } else {
                        // update state
                        self.kalmanFilter.update(measurement: detection.kfRect)
                    }
                    self.status = .active
                }
            } else {
                self.hits = 0
                // update state
                self.kalmanFilter.update(measurement: detection.kfRect)
                self.rect = self.cameraTransformer.toTrackCoordinates(self.kalmanFilter.rect)
            }
            
            // update confidence
            self.lastConfidence2 = self.lastConfidence
            self.lastConfidence = detection.confidence
            
            if let lastConfidence2 = self.lastConfidence2, let lastConfidence = self.lastConfidence {
                self.expectedConfidence = lastConfidence - (lastConfidence2 - lastConfidence)
            }
            
            /*  If the appearance cost was calculated then the detection's embedding must   *
             *  have also been computed. This is because the embedding is necessary to      *
             *  compute the appearance cost. Also, don't update embedding when inactive.    */
            if self.status.isInactive == false && costs.hasAppearance {
                self.updateEmbedding(detection: detection, appearanceCost: costs.appearance)
            }
            
            self.costs = costs
        }
        
        /// Registers that this track was not assigned a detection
        func registerMiss() {
            if self.status.isActive {
                self.hits -= 1
                if self.hits <= -self.configuration.deactivationThreshold || !self.kalmanFilter.isValid {
                    print("deactivating track: \(self.id.uuidString.prefix(4))")
                    self.status = .inactive
                    self.kalmanFilter.deactivate()
                    self.hits = 0
                } else {
//                    self.kalmanFilter.xVelocity *= self.configuration.velocityDamping
//                    self.kalmanFilter.yVelocity *= self.configuration.velocityDamping
//                    self.kalmanFilter.growthRate *= self.configuration.growthDamping
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
                return Utils.ML.cosineDistance(from: self.embedding, to: detectionEmbedding)
            }
            // return the maximum value of cosine distance
            return 2.0
        }
        
        /// Returns intersection over union
        /// - Parameter detection: `Detection` object that was assigned to this track
        /// - Returns: intersection over union of the track's rect with `detection`'s rect
        @inline(__always)
        func iou(with detection: Detection) -> Float {
            print("x: \(self.kalmanFilter.rect.midX), y: \(self.kalmanFilter.rect.midY), Area: \(self.kalmanFilter.scale), Aspect ratio: \(self.kalmanFilter.aspectRatio)")
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
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        /// Updates the embedding
        /// - Parameter detection: detection object that was assigned to this track
        /// - Parameter appearanceCost: appearance cost of the assignment
        func updateEmbedding(detection: Detection, appearanceCost: Float) {
            if detection.confidence < self.configuration.embeddingConfidenceThreshold {
                return
            }
            guard let newEmbedding = detection.embedding else {
                return
            }
            
            let alphaF = self.configuration.embeddingAlpha
            let sDet = detection.confidence
            let sigma = self.configuration.embeddingConfidenceThreshold
            
            var alpha = alphaF + (1 - alphaF) * (1 - (sDet - sigma) / (1 - sigma))
            alpha *= exp(-appearanceCost / (self.averageAppearanceCost + 1e-10))
            
            self.averageAppearanceCost += (appearanceCost - self.averageAppearanceCost) * alpha
            Utils.ML.updateEMA(ema: self.embedding, with: newEmbedding, alpha: alpha)
            self.iterationsUntilEmbeddingUpdate = self.configuration.iterationsPerEmbeddingUpdate
        }
    }
}
