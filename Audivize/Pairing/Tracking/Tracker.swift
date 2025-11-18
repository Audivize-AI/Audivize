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


extension Pairing.Tracking {
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
        private let faceProcessor: FaceProcessor
        
        private var activeTracks: OrderedSet<Track>
        private var pendingTracks: OrderedSet<Track>
        
        private let cameraTransformer: CameraCoordinateTransformer
        
        // MARK: constructors
        init(faceProcessor: FaceProcessor,
             videoSize: CGSize,
             cameraAngle: CGFloat,
             mirrored: Bool = false)
        {
            self.cameraTransformer = .init(
                orientation: .init(angle: cameraAngle, mirrored: mirrored),
                width: videoSize.width,
                height: videoSize.height
            )
            
            self.faceProcessor = faceProcessor
            self.activeTracks = []
            self.pendingTracks = []
        }
        
        // MARK: public methods
        public func update(pixelBuffer: CVPixelBuffer, orientation: CameraOrientation? = nil) -> [UUID: SendableTrack] {
            
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
            self.handleHits(&progress)
            
            // create new tracks for unmatched detections
            for detection in progress.detections {
                do {
                    let track = try Track(detection: detection, transformer: self.cameraTransformer)
                    self.pendingTracks.append(track)
                } catch {
                    print("Failed to create new track: \(error)")
                }
            }
            
            return Dictionary(uniqueKeysWithValues: self.activeTracks.map{ ($0.id, SendableTrack($0)) })
        }
        
        // MARK: private methods
        private func assign(_ progress: inout AssignmentProgress, pixelBuffer: CVPixelBuffer) {
            // Handle active tracks
            self.applyInitialCostFilter(self.meetsMotionCutoff, on: &progress)
            self.faceProcessor.embed(detections: progress.detections, in: pixelBuffer)
            self.applyCostFilter(self.meetsAppearanceCutoff, on: &progress)
            self.assignWithRLAP(&progress)
            
            // Handle teleports
            self.applyInitialCostFilter(self.meetsTeleportCutoff, on: &progress)
            self.handleMisses(&progress, tracks: &self.activeTracks)
            
            // Handle pending tracks
            progress.tracks = self.pendingTracks
            self.applyInitialCostFilter(self.meetsMotionCutoff, on: &progress)
            self.applyCostFilter(self.meetsAppearanceCutoff, on: &progress)
            self.assignWithRLAP(&progress)
            
            // remove unassigned
            for track in progress.tracks {
                assert(track.status.isTerminated)
                self.pendingTracks.remove(track)
            }
        }
        
        @inline(__always)
        private func meetsAppearanceCutoff(_ track: Track, _ detection: Detection, _ costs: Costs) -> Bool {
            costs.appearance = track.cosineDistance(to: detection)
            return costs.appearance <= TrackingConfiguration.maxAppearanceCost
        }
        
        @inline(__always)
        private func meetsTeleportCutoff(_ track: Track, _ detection: Detection, _ costs: Costs) -> Bool {
            costs.appearance = track.cosineDistance(to: detection)
            return costs.appearance <= TrackingConfiguration.maxTeleportCost
        }
        
        @inline(__always)
        private func meetsMotionCutoff(_ track: Track, _ detection: Detection, _ costs: Costs) -> Bool {
            costs.iou = track.iou(with: detection)
            if costs.iou < TrackingConfiguration.minIou {
                return false
            }
//            costs.mahaDist = track.mahaCost(for: detection)
//            if costs.mahaDist > TrackingConfiguration.maxMahaCost {
//                return false
//            }
            costs.confidence = track.confidenceCost(for: detection)
            costs.ocm = track.velocityCost(for: detection)
            return true
        }
        
        /// Looks at all possible (Track, Detection) pairings and determines which ones meet the cost cutoffs.
        /// It then isolates all pairs where 1) both the track and the detection belong to exactly one valid assignment and 2) the track's feature embedding doesn't need to be refreshed.
        /// It then removes those assignments from `progress.potentialAssignments`, `progress.tracks`, and `progress.detections` and puts them in `progress.assignments`.
        private func applyInitialCostFilter(_ costFunction: (Track, Detection, Costs) -> Bool, on progress: inout AssignmentProgress, ) {
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
        private func applyCostFilter(_ costFunction: (Track, Detection, Costs) -> Bool, on progress: inout AssignmentProgress) {
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
                for detection in detections.keys {
                    // index the detection
                    if detectionIndices[detection] == nil {
                        detectionIndices[detection] = numDetections
                        detectionArray.append(detection)
                        numDetections += 1
                    }
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
        
        private func handleHits(_ progress: inout AssignmentProgress) {
            for (track, (detection, costs)) in progress.assignments {
                let wasPending = track.status.isPending
                track.registerHit(with: detection, costs: costs)
                
                if wasPending && track.status.isActive {
                    self.pendingTracks.remove(track)
                    self.activeTracks.append(track)
                }
            }
        }
        
        @inline(__always)
        private func handleMisses(_ progress: inout AssignmentProgress, tracks: inout OrderedSet<Track>) {
            for track in progress.tracks {
                track.registerMiss()
                
                if track.isDeletable {
                    tracks.remove(track)
                }
            }
        }
    }
}
