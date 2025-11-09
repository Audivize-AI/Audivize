//
//  VideoBufferPool.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/6/25.
//

import Foundation
import OrderedCollections

extension ASD {
    /// A pool of `VideoBuffers` for ASD with scheduling.
    class VideoBufferPool: @unchecked Sendable {
        public var asdSchedulePhase: Int { queue.sync { schedulePhase } }
        private let queue = DispatchQueue(label: "ASD.VideoBufferPool")
        
        private var available: [VideoBuffer] = []
        private var active: OrderedSet<VideoBuffer> = []
        private var reservations: OrderedSet<UUID> = []
        private var scheduleSlots: OrderedSet<Int> = []
        private var schedulePeriod: Int = 0
        private var scheduleStep: Float = 0
        private var schedulePhase: Int = 0
        
        /// Initialize with N copies of your compiled model.
        public init(count: Int) throws {
            assert(count > 0)
            self.available = (0..<count).map { _ in VideoBuffer() }
            self.active.reserveCapacity(count)
            self.remakeSchedule()
        }
        
        /// Advance the schedule forward
        public func advanceSchedule() {
            queue.sync(flags: .barrier) {
                schedulePhase += 1
                
                // remake the schedule at the end of the cycle
                if schedulePhase >= schedulePeriod {
                    remakeSchedule()
                    
                    if schedulePhase >= schedulePeriod {
                        schedulePhase = 0
                    }
                }
            }
        }
        
        /// Borrow a `VideoBuffer` if one is available
        /// Otherwise, reserve a spot in line for the UUID
        ///
        /// - Parameter id: Borrower ID
        /// - Returns: A `VideoBuffer` if one is availible
        public func requestVideoBuffer(for id: UUID) -> VideoBuffer? {
            return queue.sync(flags: .barrier) { () -> VideoBuffer? in
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
                if canTake, let res = available.popLast() {
                    active.append(res)
                    res.activate()
                    return res
                }
                
                return nil
            }
        }
        
        /// Return a `VideoBuffer` back into the pool.
        /// - Parameter buffer: the `VideoBuffer` object being returned
        public func recycle(_ buffer: VideoBuffer) {
            queue.sync(flags: .barrier) {
                // ensure the buffer was actually active
                guard active.contains(buffer) else { return }
                
                active.remove(buffer)
                available.append(buffer)
                
                // cut schedule short if possible
                if let slot = scheduleSlots.remove(buffer.slot),
                    slot > scheduleSlots.last ?? 0 {
                    let next = scheduleSlots.last ?? 0
                    schedulePeriod = max(next + Int(ceil(scheduleStep)), ASDConfiguration.framesPerUpdate)
                }
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
        
        private func remakeSchedule() {
            let cooldown = ASDConfiguration.framesPerUpdate
            let numParallel = ASDConfiguration.numASDModels
            let scheduledBuffers = active.filter(\.hasEnoughFrames)
            let numSlots = scheduledBuffers.count
            
            schedulePeriod = max(
                cooldown,
                numSlots,
                Int(ceil(Float(numSlots * cooldown) / Float(numParallel)))
            )
            
            scheduleStep = Float(schedulePeriod) / Float(numSlots)
            scheduleSlots.removeAll(keepingCapacity: true)
            
            for (i, videoBuffer) in scheduledBuffers.enumerated() {
                let slot = Int(ceil(Float(i) * scheduleStep))
                videoBuffer.slot = slot
                scheduleSlots.append(slot)
            }
        }
    }
}
