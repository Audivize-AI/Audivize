//
//  ASDScheduler.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/13/25.
//

import Foundation
import OrderedCollections
import Atomics

extension Pairing.ASD {
    class Scheduler {
        /// Current call ID if there is one
        public var callId: UUID? {
            queue.sync { currentCallId }
        }
        
        private let queue: DispatchQueue = DispatchQueue(label: "ASDSchedulerQueue")
        private let cooldown: Int
        private let numHandlers: Int

        private var frame: Int = 0
        private var nextCallFrame: Int = 0
        private var nextCallIndex: Int = 0
        private var period: Int = 0
        private var currentCallId: UUID? = nil
        
        private var calls: OrderedSet<UUID> = []
        private var deleted: Set<UUID> = []
        
        /// - Parameters:
        ///   - Cooldown: Number of frames between each usage of the same handler
        ///   - numHandlers: Number of handlers
        public init(cooldown: Int, numHandlers: Int) {
            self.cooldown = cooldown
            self.numHandlers = numHandlers
        }
        
        /// Advance the schedule forward
        public func advance() {
            queue.sync(flags: .barrier) {
                currentCallId = nil
                
                // Do nothing if there are no calls
                guard !calls.isEmpty else {
                    frame = 0
                    nextCallFrame = 0
                    nextCallIndex = 0
                    return
                }
                
                frame += 1
                
                // Check if it's a new cycle
                if frame >= period {
                    // Remove deleted events
                    for event in deleted {
                        calls.remove(event)
                    }
                    deleted.removeAll(keepingCapacity: true)
                    recomputePeriod()
                    
                    // Reset frame
                    frame = 0
                    nextCallFrame = 0
                    nextCallIndex = 0
    
                    guard !calls.isEmpty else { return }
                }
                
                // update event index
                if frame >= nextCallFrame {
                    currentCallId = calls[nextCallIndex]
                    nextCallIndex += 1
                    nextCallFrame = Int(round(Float(nextCallIndex * cooldown) / Float(numHandlers)))
                }
            }
        }
        
        /// Register a new call ID
        /// - Parameter id: Call ID to register
        public func register(id: UUID) {
            queue.sync(flags: .barrier) {
                calls.append(id)
                deleted.remove(id)
                recomputePeriod()
            }
        }
        
        /// Register a new call ID if not already present
        /// - Parameter id: Call ID to register
        public func registerIfNew(id: UUID) {
            queue.sync(flags: .barrier) {
                guard calls.contains(id) == false else {
                    return
                }
                calls.append(id)
                deleted.remove(id)
                recomputePeriod()
            }
        }
        
        /// Remove a call ID
        /// - Parameter id: Call ID to remove
        public func remove(id: UUID) {
            queue.sync(flags: .barrier) {
                guard let index = calls.firstIndex(of: id) else {
                    return
                }
                
                if index > frame {
                    calls.remove(at: index)
                    recomputePeriod()
                } else {
                    deleted.insert(id)
                }
            }
        }
        
        /// Check if the schedule contains a call ID
        /// - Returns: `true` if the schedule contains the call ID, `false` if not.
        public func contains(id: UUID) -> Bool {
            queue.sync {
                return calls.contains(id)
            }
        }
        
        private func recomputePeriod() {
            period = max(calls.count,
                         Int(round(Float(calls.count * cooldown) / Float(numHandlers))))
        }
    }
}
