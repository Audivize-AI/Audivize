////
////  EmbeddingCluster.swift
////  FaceAlignmentTest
////
////  Created by Benjamin Lee on 8/5/25.
////
//
//import Foundation
//import HashTreeCollections
//import Accelerate
//
//extension ASD {
//    final class FaceEmbedding {
//        // MARK: Bin Enums and Structs
//        public enum PitchBin: Int, CaseIterable {
//            case up90 = 0
//            case up = 1
//            case front = 2
//            case down = 3
//            case down90 = 4
//        }
//        
//        public enum YawBin: Int, CaseIterable {
//            case right90 = 0
//            case right = 1
//            case front = 2
//            case left = 3
//            case left90 = 4
//        }
//        
//        public struct Attitude {
//            static let invalid = Attitude(yawBin: .front, pitchBin: .up90, yaw: .nan, pitch: .nan)
//            
//            let yawBin: YawBin
//            let pitchBin: PitchBin
//            let yaw: CGFloat
//            let pitch: CGFloat
//            
//            var binIndex: Int { yawBin.rawValue * PitchBin.allCases.count + pitchBin.rawValue }
//            var isValid: Bool { !yaw.isNaN && !pitch.isNaN }
//            var bin: (yaw: Int, pitch: Int) { (yawBin.rawValue, pitchBin.rawValue) }
//        }
//        
//        // MARK: Private structs
//        private class EmbeddingBin {
//            var embedding: [Float]? = nil
//            var sumWeights: Float = 0
//            
//            var isInitialized: Bool { embedding != nil }
//            
//            /// updates the embedding vector with a new embedding and a weight
//            /// - Parameter embedding: a 512-dimensional embedding unit vector
//            /// - Parameter weight: the weight that determines how much this influences the embedding vector
//            /// - Warning: assumes that `embedding` is already normalized.
//            func update(with embedding: [Float], weight: Float) {
//                if self.embedding == nil {
//                    self.embedding = embedding
//                    self.sumWeights = weight
//                    return
//                }
//                
//                vDSP.add(vDSP.multiply(weight / (sumWeights + weight), embedding),
//                         vDSP.multiply(sumWeights / (sumWeights + weight), self.embedding!),
//                         result: &self.embedding!)
//                vDSP.multiply(sqrt(vDSP.sumOfSquares(self.embedding!)),
//                              self.embedding!,
//                              result: &self.embedding!)
//                self.sumWeights += weight
//            }
//        }
//        
//        // MARK: Public Attributes
//        public var initializedIndices: RangeSet<Int> { embeddings.indices(where: \.isInitialized) }
//        private var embeddings: [EmbeddingBin]
//        
//        private static let recognitionThresholds: [Float] = []
//        
//        private static let yawCenters: [Float] = [
//            -Float(yaw90Threshold + yawMax) / 2,        /// right90
//             -Float(yawThreshold + yaw90Threshold) / 2, /// right
//             0.0,                                       /// front
//             Float(yawThreshold + yaw90Threshold) / 2,  /// left
//             Float(yaw90Threshold + yawMax) / 2,        /// left90
//        ]
//        
//        private static let yawSizes: [Float] = [
//            Float(yawMax - yaw90Threshold),        /// right90
//            Float(yaw90Threshold - yawThreshold),  /// right
//            Float(yawThreshold * 2),               /// front
//            Float(yaw90Threshold - yawThreshold),  /// left
//            Float(yawMax - yaw90Threshold),        /// left90
//        ]
//        
//        private static let pitchCenters: [Float] = [
//            Float(up90Threshold + upMax) / 2,           /// up90
//            Float(up90Threshold + upThreshold) / 2,     /// up
//            Float(upThreshold + downThreshold) / 2,     /// front
//            Float(downThreshold + down90Threshold) / 2, /// down
//            Float(down90Threshold + downMax) / 2,       /// down90
//        ]
//        
//        private static let pitchSizes: [Float] = [
//            Float(upMax - up90Threshold),               /// up90
//            Float(up90Threshold - upThreshold),         /// up
//            Float(upThreshold - downThreshold),         /// front
//            Float(downThreshold - down90Threshold),     /// down
//            Float(down90Threshold - downMax),           /// down90
//        ]
//        
//        private static let binIndices: [(yaw: Int, pitch: Int)] = [
//            (0, 0), (0, 1), (0, 2), (0, 3), (0, 4),
//            (1, 0), (1, 1), (1, 2), (1, 3), (1, 4),
//            (2, 0), (2, 1), (2, 2), (2, 3), (2, 4),
//            (3, 0), (3, 1), (3, 2), (3, 3), (3, 4),
//            (4, 0), (4, 1), (4, 2), (4, 3), (4, 4)
//        ]
//        
//        // MARK: Constructors
//        
//        /// Construct a FaceEmbedding with an embedding vector and a list of landmarks
//        /// - Parameters:
//        ///    - embedding: a 512-dimensional embedding vector
//        ///    - kps: array of 5 landmark points
//        public convenience init(with embedding: [Float],
//                                landmarks kps: [CGPoint]) {
//            assert(embedding.count == 512)
//            assert(kps.count == 5)
//            self.init()
//            
//            let attitude = FaceEmbedding.estimateAttitude(for: kps)
//            let weight = FaceEmbedding.computeWeight(between: attitude, and: attitude.bin)
//            self.embeddings[attitude.binIndex].update(with: embedding, weight: weight)
//        }
//        
//        /// Construct a FaceEmbedding
//        public init() {
//            self.embeddings = Array(repeating: .init(),
//                                    count: PitchBin.allCases.count * YawBin.allCases.count)
//        }
//        
//        // MARK: Methods
//        
//        /// Update FaceEmbedding with a new embedding vector and landmarks
//        /// - Parameters:
//        ///   - embedding: 512-dimensional embedding vector
//        ///   - kps: 5 landmark points
//        public func update(with embedding: [Float], landmarks kps: [CGPoint]) {
//            let attitude = FaceEmbedding.estimateAttitude(for: kps)
//            
//            for (i, e) in embeddings.enumerated() where e.isInitialized {
//                let bin = FaceEmbedding.splitBinIndex(i)
//                let weight = FaceEmbedding.computeWeight(between: attitude, and: bin)
//                e.update(with: embedding, weight: weight)
//            }
//            
//            let index = attitude.binIndex
//            if embeddings[index].isInitialized == false {
//                let weight = FaceEmbedding.computeWeight(between: attitude, and: attitude.bin)
//                embeddings[index].update(with: embedding, weight: weight)
//            }
//        }
//        
//        /// compute the RMSE of the cosine similarities
//        /// - Parameter other: another `FaceEmbedding`
//        public func similarity(to other: FaceEmbedding) -> Float {
//            var similarity: Float = 0.0
//            var count: Int = 0
//            for (e1, e2) in zip(embeddings, other.embeddings) {
//                guard let e1 = e1.embedding, let e2 = e2.embedding else { continue }
//                count += 1
//                let dot = vDSP.dot(e1, e2)
//                similarity += dot * dot
//            }
//            return similarity / Float(count)
//        }
//        
//        private static func estimateAttitude(for kps: [CGPoint]) -> Attitude {
//            let leftX = (kps[0].x + kps[3].x) / 2
//            let rightX = (kps[1].x + kps[4].x) / 2
//            let topY = (kps[0].y + kps[1].y) / 2
//            let bottomY = (kps[3].y + kps[4].y) / 2
//            let midX = (leftX + rightX) / 2
//            let midY = (topY + bottomY) / 2
//            let noseX = kps[2].x
//            let noseY = kps[2].y
//            
//            let height = topY - bottomY
//            let width = rightX - leftX
//            
//            guard width < 0 else {
//                return .invalid
//            }
//            
//            let yaw = atan((noseX - midX) / width)
//            
//            guard abs(yaw) < yawMax else {
//                return .invalid
//            }
//            
//            var yawBin: YawBin
//            
//            if yaw > yawThreshold {
//                yawBin = yaw < yaw90Threshold ? .left : .left90
//            } else if yaw < -yawThreshold {
//                yawBin = yaw > -yaw90Threshold ? .right : .right90
//            } else {
//                yawBin = .front
//            }
//            
//            // expression
//            var yRatio = (noseY - midY) / height
//            let mouthWidth = hypot(kps[4].x - kps[3].x, kps[4].y - kps[3].y)
//            let eyeWidth = hypot(kps[1].x - kps[0].x, kps[1].y - kps[0].y)
//            
//            let smileThreshold = yRatio > 0 ? smileUpThreshold : smileDownThreshold
//            
//            if mouthWidth > eyeWidth * smileThreshold {
//                yRatio += yRatio > 0 ? smileUpOffset : smileDownOffset
//            }
//            
//            // pitch bin
//            let pitch = atan(yRatio)
//            var pitchBin: PitchBin
//            
//            if pitch > upThreshold {
//                pitchBin = pitch < up90Threshold ? .up : .up90
//            } else if pitch < downThreshold {
//                pitchBin = pitch > down90Threshold ? .down : .down90
//            } else {
//                pitchBin = .front
//            }
//            
//            return .init(yawBin: yawBin,
//                         pitchBin: pitchBin,
//                         yaw: yaw,
//                         pitch: pitch
//            )
//        }
//        
//        private static func computeWeight(between attitude: Attitude,
//                                          and bin: (yaw: Int, pitch: Int)) -> Float {
//            guard attitude.isValid else {
//                return 0.0
//            }
//            
//            let width = Float(yawSizes[bin.yaw])
//            let height = Float(pitchSizes[bin.yaw])
//            let centerYaw = Float(yawCenters[bin.yaw])
//            let centerPitch = Float(pitchCenters[bin.pitch])
//            
//            let zPitch = (Float(attitude.pitch) - centerPitch) / height
//            let zYaw = (Float(attitude.yaw) - centerYaw) / width
//            let mahalanobisSquared: Float = (zPitch * zPitch) + (zYaw * zYaw)
//            
//            return exp(-mahalanobisSquared / (2 * binSigma2))
//        }
//        
//        @inline(__always)
//        private static func splitBinIndex(_ index: Int) -> (yaw: Int, pitch: Int) {
//            let yawIndex = index / PitchBin.allCases.count
//            let pitchIndex = index - (yawIndex * PitchBin.allCases.count)
//            return (yawIndex, pitchIndex)
//        }
//    }
//}
