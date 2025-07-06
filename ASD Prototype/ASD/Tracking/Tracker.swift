//
//  Tracker.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/21/25.
//

import Foundation
import OrderedCollections
import CoreMedia
import ImageIO
import LANumerics
import CoreML


extension ASD.Tracking {
    final class Tracker {
        // MARK: structs and enums
        enum TrackerError: Error {
            case rlapInvalidCostMatrix
            case rlapInfeasibleCostMatrix
            case rlapUnknownError
        }
        
        private struct AssignmentProgress {
            var tracks: OrderedSet<Track>
            var detections: OrderedSet<Detection>
            var assignments: OrderedDictionary<Track, (Detection, Costs)> = [:]
            var potentialAssignments: OrderedDictionary<Track, [Detection : Costs]> = [:]
            
            var isComplete: Bool {
                return self.detections.isEmpty || self.tracks.isEmpty
            }
            
            init(tracks: OrderedSet<Track>, detections: OrderedSet<Detection>) {
                self.tracks = tracks
                self.detections = detections
                self.assignments.reserveCapacity(tracks.count)
                self.potentialAssignments.reserveCapacity(tracks.count)
            }
        }
        
        // MARK: private properties
        private let mergeTracks: (ASD.MergeRequest) -> Void
        private let faceProcessor: FaceProcessor
        
        private var activeTracks: OrderedSet<Track>
        private var pendingTracks: OrderedSet<Track>
        private var inactiveTracks: OrderedSet<Track>
        
        private var costConfiguration: CostConfiguration
        private var trackConfiguration: TrackConfiguration
        
        private var screenWidth: Int = 0
        private var screenHeight: Int = 0
        
        private let cameraTransformer: CameraCoordinateTransformer
        
        // MARK: constructors
        init(faceProcessor: FaceProcessor,
             videoSize: CGSize,
             cameraAngle: CGFloat,
             mirrored: Bool = false,
             costConfiguration: CostConfiguration = .init(),
             trackConfiguration: TrackConfiguration = .init(),
             mergeCallback mergeTracks: @escaping (ASD.MergeRequest) -> Void = { _ in })
        {
            self.cameraTransformer = .init(orientation: .init(angle: cameraAngle, mirrored: mirrored),
                                           width: videoSize.width,
                                           height: videoSize.height)
            
            self.faceProcessor = faceProcessor
            self.activeTracks = []
            self.inactiveTracks = []
            self.pendingTracks = []
            self.costConfiguration = costConfiguration
            self.trackConfiguration = trackConfiguration
            self.mergeTracks = mergeTracks
        }
        
        // MARK: public methods
        
        public func update(pixelBuffer: CVPixelBuffer, orientation: CameraOrientation? = nil) -> [SendableTrack] {
            if let orientation = orientation {
                self.cameraTransformer.orientation = orientation
            }
            
            // predict track motion
            for track in self.activeTracks {
                track.predict()
            }
            for track in self.pendingTracks {
                track.predict()
            }
            
            // assign tracks to detections
            var progress = AssignmentProgress(
                tracks: self.activeTracks,
                detections: self.faceProcessor.detect(
                    pixelBuffer: pixelBuffer,
                    transformer: self.cameraTransformer
                )
            )
            self.assign(&progress, pixelBuffer: pixelBuffer)
            
            // update tracks with detections
            self.registerHits(&progress)
            
            // create new tracks for unmatched detections
            for detection in progress.detections {
                do {
                    let track = try Track(detection: detection,
                                          transformer: self.cameraTransformer,
                                          trackConfiguration: self.trackConfiguration,
                                          costConfiguration: self.costConfiguration)
                    self.pendingTracks.append(track)
                } catch {
                    print("Failed to create new track: \(error)")
                }
            }
            
            return self.activeTracks.map(SendableTrack.init) + self.pendingTracks.map(SendableTrack.init)
        }
        
        
        /// Add a permanent track to the tracker
        /// - Parameters:
        ///   - id: the track's ID
        ///   - embedding: the track's facial feature embedding
        ///   - detection: the detection associated with the track. Will initialize the track as inactive if not provided.
        /// - Throws: when the embedding vector's shape is mismatched from the desired shape
        public func addTrack(id: UUID, embedding: MLMultiArray, detection: Detection? = nil) throws {
            let track = try Track(id: id,
                                  embedding: embedding,
                                  transformer: self.cameraTransformer,
                                  trackConfiguration: self.trackConfiguration,
                                  costConfiguration: self.costConfiguration,
                                  detection: detection)
            if track.status.isActive {
                self.activeTracks.append(track)
            } else {
                self.inactiveTracks.append(track)
            }
        }
        
        /// Add a permanent track to the tracker
        /// - Parameters:
        ///   - track: the track being added
        /// - Throws: when the track's status is pending
        public func addTrack(_ track: Track) throws {
            switch track.status {
            case .active:
                self.activeTracks.append(track)
            case .inactive:
                self.inactiveTracks.append(track)
            default:
                self.activeTracks.append(track)
                track.retain()
            }
        }
        
        /// Add a permanent track to the tracker
        /// - Parameters:
        ///   - track: the track being removed
        /// - Returns: true if the track was removed, false if not
        public func removeTrack(_ track: Track) -> Bool {
            track.release()
            if self.activeTracks.remove(track) == nil {
                if self.inactiveTracks.remove(track) == nil {
                    return false
                }
            }
            return true
        }
        
        /// Add a permanent track to the tracker
        /// - Parameters:
        ///   - track: the track being removed
        /// - Throws: when the track's status is pending
        public func removeTrack(withID id: UUID) -> Bool {
            if let track = (self.activeTracks.elements + self.inactiveTracks.elements).first(where: { $0.id == id }) {
                return self.removeTrack(track)
            }
            return false
        }
        
        // MARK: private methods
        private func assign(_ progress: inout AssignmentProgress, pixelBuffer: CVPixelBuffer) {
            // assign active tracks
            self.applyInitialCostFilter(&progress, costFunction: self.meetsMotionCostCutoff)
            self.faceProcessor.embed(pixelBuffer: pixelBuffer, faces: progress.detections)
            self.applyCostFilter(&progress, costFunction: self.meetsAppearanceCostCutoff)
            self.assignWithRLAP(&progress)
            self.applyInitialCostFilter(&progress, costFunction: self.meetsReIDCostCutoff)
            self.registerMisses(&progress, tracks: &self.activeTracks, trackStatus: .active)
            
            // assign inactive tracks
            progress.tracks = self.inactiveTracks
            self.applyInitialCostFilter(&progress, costFunction: self.meetsReIDCostCutoff)
            self.assignWithRLAP(&progress)
            self.registerMisses(&progress, tracks: &self.inactiveTracks, trackStatus: .inactive)
            
            // assign pending tracks
            progress.tracks = self.pendingTracks
            self.applyInitialCostFilter(&progress, costFunction: self.meetsMotionCostCutoff)
            self.applyCostFilter(&progress, costFunction: self.meetsAppearanceCostCutoff)
            self.assignWithRLAP(&progress)
            for track in progress.tracks {
                self.pendingTracks.remove(track)
            }
            
//            print("active:\t\(self.activeTracks.map{$0.id.uuidString.prefix(4)})")
//            print("inactive:\t\(self.inactiveTracks.map{$0.id.uuidString.prefix(4)})")
//            print("pending:\t\(self.pendingTracks.map{$0.id.uuidString.prefix(4)})")
//            print("\n-----------------------------------------------------------------\n")
        }
        
        @inline(__always)
        private func meetsAppearanceCostCutoff(_ track: Track, _ detection: Detection, _ costs: Costs) -> Bool {
            costs.appearance = track.cosineDistance(to: detection)
            return costs.appearance <= self.costConfiguration.maxAppearanceCost
        }
        
        @inline(__always)
        private func meetsReIDCostCutoff(_ track: Track, _ detection: Detection, _ costs: Costs) -> Bool {
            costs.appearance = track.cosineDistance(to: detection)
            return costs.appearance <= self.costConfiguration.maxReIDCost
        }
        
        @inline(__always)
        private func meetsMotionCostCutoff(_ track: Track, _ detection: Detection, _ costs: Costs) -> Bool {
            costs.iou = track.iou(with: detection)
            if costs.iou < self.costConfiguration.minIou {
                return false
            }
            costs.confidence = track.confidenceCost(for: detection)
            costs.ocm = track.velocityCost(for: detection)
            return true
        }
        
        @inline(__always)
        private func heuristicCost(costs: Costs) -> Float {
            if costs.iou == Float.infinity {
                return costs.appearance
            }
            if costs.appearance == Float.infinity {
                return (1 - costs.iou +
                        costs.ocm        * self.costConfiguration.ocmWeight +
                        costs.confidence * self.costConfiguration.confidenceWeight)
            }
            return (1 - costs.iou +
                    costs.appearance * self.costConfiguration.appearanceWeight +
                    costs.ocm        * self.costConfiguration.ocmWeight +
                    costs.confidence * self.costConfiguration.confidenceWeight)
        }
        
        /// Looks at all possible (Track, Detection) pairings and determines which ones meet the cost cutoffs.
        /// It then isolates all pairs where 1) both the track and the detection belong to exactly one valid assignment and 2) the track's feature embedding doesn't need to be refreshed.
        /// It then removes those assignments from `progress.potentialAssignments`, `progress.tracks`, and `progress.detections` and puts them in `progress.assignments`.
        private func applyInitialCostFilter(_ progress: inout AssignmentProgress, costFunction: (Track, Detection, Costs) -> Bool) {
            if progress.isComplete { return }
            
            var newAssignments: [Track : (Detection, Int)] = [:]
            var detectionCounts: [Int] = [Int](repeating: 0, count: progress.detections.count)
            progress.potentialAssignments.reserveCapacity(progress.tracks.count)
            
            // build potential assignments
            for track in progress.tracks {
                var assignmentIndex: Int = -1
                var trackAssignments: [Detection: Costs] = [:]
                
                for (i, detection) in progress.detections.enumerated() {
                    // ensure that any potential assignments meets the cost cutoff
                    let costs = Costs()
                    if costFunction(track, detection, costs) {
                        trackAssignments[detection] = costs
                        
                        // determine if it's possible for this to be a unique assignment for both the track and the detection
                        detectionCounts[i] += 1
                        if detectionCounts[i] == 1 {
                            assignmentIndex = i
                        }
                    }
                }
                
                // add assignments
                if trackAssignments.isEmpty == false {
                    // add assignment if exactly one currently uncontested detection is found and we don't need to re-verify the embedding
                    if assignmentIndex != -1 && trackAssignments.count == 1 && !track.needsEmbeddingUpdate {
                        newAssignments[track] = (progress.detections[assignmentIndex], assignmentIndex)
                    }
                    progress.potentialAssignments[track] = trackAssignments
                }
            }
            
            // update assignments and remove assigned tracks and detections
            for (track, (detection, index)) in newAssignments where detectionCounts[index] == 1 {
                if let costs = progress.potentialAssignments[track]?[detection] {
                    progress.assignments[track] = (detection, costs)
                    progress.tracks.remove(track)
                    progress.detections.remove(detection)
                    progress.potentialAssignments[track] = nil // actual assignments are no longer just "potential"
                }
            }
        }
        
        /// Looks at the remaining `potentialAssignments` and filters out any that exceed the maximum appearance cost.
        /// It then isolates all pairs where 1) both the track and the detection belong to exactly one valid potential assignment and 2) the track's feature embedding doesn't need to be refreshed.
        /// It then removes those assignments from `progress.potentialAssignments`, `progress.tracks`, and `progress.detections` and puts them in `progress.assignments`.
        private func applyCostFilter(_ progress: inout AssignmentProgress, costFunction: (Track, Detection, Costs) -> Bool) {
            if progress.isComplete { return }
            
            var newAssignments: [Track : (Detection, Costs)] = [:]
            var detectionCounts: [Detection: Int] = [:]
            
            // apply cost filter to remove invalid potential assignments
            for track in Array(progress.potentialAssignments.keys) {
                guard var trackAssignments = progress.potentialAssignments[track] else { continue }
                var assignment: (Detection, Costs)?
                for (detection, costs) in trackAssignments {
                    // remove assignments that exceed the maximum cost
                    if costFunction(track, detection, costs) {
                        detectionCounts[detection, default: 0] += 1 // passes cost filter
                        assignment = (detection, costs)
                    } else {
                        trackAssignments[detection] = nil // fails cost filter
                    }
                }
                
                if trackAssignments.isEmpty {
                    progress.potentialAssignments[track] = nil
                } else {
                    progress.potentialAssignments[track] = trackAssignments
                    // determine if this assignment can be unique to both the track and the detection
                    if trackAssignments.count == 1 && detectionCounts[assignment!.0] == 1 {
                        newAssignments[track] = assignment
                    }
                }
            }
            
            // update assignments and remove assigned tracks and detections
            for (track, assignment) in newAssignments where detectionCounts[assignment.0] == 1 {
                progress.assignments[track] = assignment
                progress.tracks.remove(track)
                progress.detections.remove(assignment.0)
                progress.potentialAssignments[track] = nil
            }
        }
        
        private func assignWithRLAP(_ progress: inout AssignmentProgress) {
            if progress.isComplete { return }
            
            // Make the minimum bijection from Detections <-> indices
            // Also compute the total costs.
            var detectionIndices: [Detection: Int] = [:]
            var detectionArray: [Detection] = []
            var numDetections = 0
            
            for (_, detections) in progress.potentialAssignments {
                for (detection, costs) in detections {
                    // index the detection
                    if detectionIndices[detection] == nil {
                        detectionIndices[detection] = numDetections
                        detectionArray.append(detection)
                        numDetections += 1
                    }
                    
                    // compute total cost
                    costs.total = heuristicCost(costs: costs)
                }
            }
            
            // Build the cost matrix
            let numTracks: Int = progress.potentialAssignments.count
            var costMatrix = [Float](repeating: Float.infinity, count: numTracks * numDetections)
            for (row, (_, detections)) in progress.potentialAssignments.enumerated() {
                for (detection, costs) in detections {
                    if let col = detectionIndices[detection] {
                        costMatrix[row * numDetections + col] = costs.total
                    }
                }
            }
            
            // get (row, column) assignments
            var rows: [Int] = []
            var cols: [Int] = []
            let exitCode = solveRLAP(dims: (numTracks, numDetections),
                                     cost: costMatrix,
                                     rows: &rows,
                                     cols: &cols)
            
            if exitCode != 0 {
                print("WARNING: Solver returned non-zero exit code \(exitCode)")
            }
            
            // add assignments
            let tracks = Array(progress.potentialAssignments.keys)
            
            for (row, col) in zip(rows, cols) {
                let track = tracks[row]
                let detection = detectionArray[col]
                if let costs = progress.potentialAssignments[track]?[detection] {
                    progress.assignments[track] = (detection, costs)
                } else {
                    print(#function, "Warning: costs not found for track \(track.id.uuidString) and detection \(detection.id.uuidString)")
                }
                
                // the assigned tracks no longer need to be assigned
                progress.tracks.remove(track)
                progress.detections.remove(detection)
            }
            
            progress.potentialAssignments.removeAll()
        }
        
        private func registerHits(_ progress: inout AssignmentProgress) {
            for (track, (detection, costs)) in progress.assignments {
                let oldStatus = track.status
                track.registerHit(with: detection, costs: costs)
                
                if track.status != oldStatus {
                    switch oldStatus {
                    case .inactive:
                        self.inactiveTracks.remove(track)
                    case .pending:
                        self.pendingTracks.remove(track)
                    default:
                        break
                    }
                    
                    if track.status == .active {
                        self.activeTracks.append(track)
                    } else {
                        print("Warning: track wants to be moved to inactive/pending after hit")
                    }
                }
            }
        }
        
        private func registerMisses(_ progress: inout AssignmentProgress, tracks: inout OrderedSet<Track>, trackStatus: Track.Status) {
            for track in progress.tracks {
                if track.status != trackStatus {
                    print("Warning: track \(track) has status \(track.status), expected \(trackStatus)")
                }
                
                track.registerMiss()
                
                if track.status != trackStatus || track.isDeletable {
                    tracks.remove(track)
                    if track.isDeletable == false {
                        self.inactiveTracks.append(track)
                    } else if track.status == .inactive {
                        self.mergeInactiveTrack(track, tracks: tracks.elements + self.activeTracks.elements)
                    } else {
                        print("#warning: track wants to be moved to active/pending after miss")
                    }
                }
            }
        }
        
        @discardableResult
        private func mergeInactiveTrack(_ track: Track, tracks: [Track]) -> Bool {
            var bestMatch: Track?
            var minCost: Float = self.costConfiguration.maxReIDCost.nextUp
            
            for other in tracks {
                if other == track {
                    continue
                }
                
                let cost = Utils.ML.cosineDistance(from: track.embedding, to: other.embedding)
                if cost < minCost {
                    bestMatch = other
                    minCost = cost
                }
            }
            
            if let targetID = bestMatch?.id {
                self.mergeTracks(.init(from: track.id, into: targetID))
                //print("merged \(track.id) into \(bestMatch!.id)")
                return true
            }
            //print("deleted inactive track \(track.id)")
            return false
        }
    }
}
