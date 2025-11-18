//
//  VideoBufferPool.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/6/25.
//

import Foundation
import OrderedCollections

extension Pairing.ASD {
    /// A pool of `ASDBuffers` for active speaker detection and scheduling
    class ASDManager: @unchecked Sendable {
        enum VideoManagerError: Error {
            case invalidVideoBufferAmount
            case invalidASDModelAmount
            case regressingTimestamp
        }
        
        public var frameIndex: Int {
            queue.sync { frameIndexInternal }
        }
        
        private let queue = DispatchQueue(label: "ASD.ASDManager.Queue")
        
        private var available: [UUID: ASDBuffer] = [:]
        private var active: [UUID: ASDBuffer] = [:]
        private var unscoredActiveIds: Set<UUID> = []
        private var reservations: OrderedSet<UUID> = []
        private let scheduler: Scheduler
        private let modelPool: ASDModelPool
        private var frameIndexInternal: Int
        private var previousTimestamp: TimeInterval
        
        // MARK: - Init
        public init(atTime time: TimeInterval, numVideoBuffers: Int, numASDModels: Int) throws {
            guard numVideoBuffers > 0 else {
                throw VideoManagerError.invalidVideoBufferAmount
            }
            guard numASDModels > 0 else {
                throw VideoManagerError.invalidASDModelAmount
            }
            
            for _ in (0..<numVideoBuffers) {
                let buffer = ASDBuffer()
                self.available[buffer.id] = buffer
            }
            
            self.frameIndexInternal = Self.getFrameIndex(forTime: time)
            self.active.reserveCapacity(numVideoBuffers)
            self.scheduler = .init(cooldown: ASDConfiguration.framesPerUpdate,
                                   numHandlers: ASDConfiguration.numASDModels)
            self.modelPool = try ASDModelPool(count: numASDModels)
            self.previousTimestamp = time
        }
        
        // MARK: - Public methods
        
        /// Next frame
        /// - Parameters:
        ///   - time: Current timestamp
        ///   - skip: Whether the frame should be dropped
        public func advanceFrame(atTime time: TimeInterval, dropFrame: Bool = false) throws {
            try queue.sync(flags: .barrier) {
                for (id, video) in active {
                    if video.hasEnoughFrames {
                        scheduler.registerIfNew(id: id)
                    } else {
                        scheduler.remove(id: id)
                    }
                }
                // Advance ASD Schedule
                scheduler.advance()
                
                // Update ASD scores if needed
                if let callId = scheduler.callId, let buffer = active[callId] {
                    guard buffer.hasEnoughFrames else {
                        debugPrint("How the did we get here without enough frames?")
                        return
                    }
                    debugPrint("Running ASD for \(buffer.id)")
                    let input = ASDConfiguration.ASDModel.Input(videoInput: try buffer.read(at: -1))
                    let asdRequest = buffer.makeASDRequest(atFrame: frameIndexInternal)
                    
                    Task(priority: .userInitiated) {
                        let logits = try await modelPool.runInference(on: input)
                        debugPrint("Logits: \(logits)")
                        buffer.addNewLogits(from: asdRequest, logits: logits)
                    }
                }
                
                // Advance frame index
                if !dropFrame {
                    frameIndexInternal += 1
                    try syncFrameIndex(atTime: time)
                }
            }
        }
        
        /// Borrow a `VideoBuffer` if one is available
        /// Otherwise, reserve a spot in line for the UUID
        ///
        /// - Parameter id: Borrower ID
        /// - Returns: An `ASDBuffer` if one is availible
        public func requestASDBuffer(for id: UUID) -> ASDBuffer? {
            return queue.sync(flags: .barrier) { () -> ASDBuffer? in
                // Make a reservation if nothing is availible
                if available.isEmpty {
                    reservations.append(id)
                    return nil
                }
                
                // Check if we're at the front of the line (or if there even is a line)
                var canTake = reservations.isEmpty
                if reservations.first == id {
                    reservations.removeFirst()
                    canTake = true
                }
                
                // Take the next availible video buffer
                if canTake,
                   let id = available.keys.first,
                   let buffer = available.removeValue(forKey: id) {
                    active[id] = buffer
                    buffer.activate()
                    unscoredActiveIds.insert(id)
                    return buffer
                }
                
                return nil
            }
        }
        
        /// Return a `VideoBuffer` back into the pool.
        /// - Parameter buffer: the `ASDBuffer` object being returned
        public func recycle(_ buffer: ASDBuffer) {
            queue.sync(flags: .barrier) {
                // ensure the buffer was actually active
                guard active[buffer.id] != nil else { return }
                
                active.removeValue(forKey: buffer.id)
                unscoredActiveIds.remove(buffer.id)
                
                available[buffer.id] = buffer
                scheduler.remove(id: buffer.id)
            }
        }
        
        /// Cancel a reservation.
        /// - Parameter id: Borrower ID
        /// - Returns: `true` if removal was successful, `false` otherwise.
        @discardableResult
        public func cancelReservation(for id: UUID) -> Bool {
            queue.sync(flags: .barrier) {
                return self.reservations.remove(id) != nil
            }
        }
        
        /// Replace the ID for a reservation with a different ID.
        /// - Parameter oldId: Old Borrower ID
        /// - Parameter newId: New Borrower ID
        public func replaceReservation(for oldId: UUID, with newId: UUID) {
            queue.async(flags: .barrier) { [self] in
                guard oldId != newId, let oldIdx = reservations.firstIndex(of: oldId) else { return }

                if let newIdx = reservations.firstIndex(of: newId) {
                    if newIdx < oldIdx {
                        // Earlier `newId` stays; drop `oldId`.
                        reservations.remove(oldId)
                    } else {
                        // `newId` is later; remove it, then place `newId` at `oldIdx`.
                        reservations.remove(newId)
                        reservations.insert(newId, at: oldIdx)
                    }
                } else {
                    // No existing `newId`; overwrite position of `oldId`.
                    reservations.insert(newId, at: oldIdx)
                }
            }
        }
        
        /// Check if an ID has a spot in line
        public func hasReservation(for id: UUID) -> Bool {
            return self.reservations.contains(id)
        }
        
        // MARK: - Private helpers
        
        /// Realign timestamps if they deviate too much
        /// - Throws: `.regressingTimestamp`
        private func syncFrameIndex(atTime time: TimeInterval) throws {
            // Ensure the timestamp did not regress
            defer { previousTimestamp = time }
            guard time > previousTimestamp else {
                throw VideoManagerError.regressingTimestamp
            }
            
            // Check frame deviation
            let expectedFrameIndex = Self.getFrameIndex(forTime: time)
            if abs(expectedFrameIndex - frameIndexInternal) > 1 {
                debugPrint("WARNING: Skipping ahead in score stream due to timestamp mismatch (\(expectedFrameIndex) != \(frameIndexInternal))")
                frameIndexInternal = expectedFrameIndex
            }
        }
        
        /// Convert timestamp into a frame index
        private static func getFrameIndex(forTime time: TimeInterval) -> Int {
            return Int(round(time * ASDConfiguration.frameRate))
        }
    }
}
