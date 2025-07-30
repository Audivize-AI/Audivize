//
//  ScoreBuffer.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/29/25.
//

import Foundation
import CoreML


extension ASD {
    final class ScoreBuffer: Buffer {
        typealias Element = Score
        
        enum ScoreClass: Int {
            case inactive = 0
            case active = 1
        }
        
        struct Score: Sendable {
            var cumulativeScore: Float = 0
            var updates: UInt32 = 0
            
            var score: Float {
                get { updates > 0 ? cumulativeScore / Float(updates) : 0 }
                set { updates = max(1, updates); cumulativeScore = newValue * Float(updates) }
            }
            
            var scoreClass: (ScoreClass, Float) {
                (isActive
                 ? (.active, probability)
                 : (.inactive, 1-probability))
            }
            
            var probability: Float { 1.0 / (1.0 + exp(-cumulativeScore)) } /// sigmoid probability using cumulative score.
            var isActive: Bool { cumulativeScore > 0 } /// whether the score is greater than 0
            
            mutating func update(with score: Float) {
                cumulativeScore = score
                updates += 1
            }
            
            mutating func reset(to score: Float = 0) {
                (cumulativeScore, updates) = (score, 1)
            }
        }
        
        struct SendableState: Sendable {
            let buffer: ContiguousArray<Score>
            let writeIndex: Int
        }
        
        // MARK: Attributes
        
        var count: Int { self.bufferSize }
        var data: SendableState { .init(buffer: self.buffer, writeIndex: self.writeIndex) }
        
        private var buffer: ContiguousArray<Score>
        private var writeIndex: Int
        private var bufferSize: Int { self.buffer.count }
        
        // MARK: Constructors
        
        public init(capacity: Int = 60) {
            self.writeIndex = 0
            self.buffer = .init(repeating: .init(), count: capacity)
        }
        
        public init(from state: SendableState) {
            self.buffer = state.buffer
            self.writeIndex = state.writeIndex
        }
        
        // MARK: Subscripting
        
        public subscript (_ index: Int) -> Float {
            get {
                return self.buffer[self.wrapIndex(index)].score
            }
            set {
                return self.buffer[self.wrapIndex(index)].update(with: newValue)
            }
        }
        
        // MARK: Buffer
        
        func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Score>) throws -> R) rethrows -> R {
            return try self.buffer.withUnsafeBufferPointer(body)
        }
        
        func withUnsafeMutableBufferPointer<R>(_ body: (inout UnsafeMutableBufferPointer<Score>) throws -> R) rethrows -> R {
            return try self.buffer.withUnsafeMutableBufferPointer(body)
        }
        
        // MARK: public methods
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - source the data source from which to write
        ///   - offset how many indices to skip
        public func write(from source: MLMultiArray, count numNew: Int) {
            var i = Utils.mod(self.writeIndex + numNew - source.count, self.bufferSize)
            
            source.withUnsafeBufferPointer(ofType: Float.self) { ptr in
                for score in ptr[0..<source.count-numNew] {
                    self.buffer[i].update(with: score)
                    Utils.advance_index(&i, by: 1, modulo: self.bufferSize)
                }
                for score in ptr[source.count-numNew..<source.count] {
                    self.buffer[self.writeIndex].reset(to: score)
                    Utils.advance_index(&self.writeIndex, by: 1, modulo: self.bufferSize)
                }
            }
        }
        
        public func read(at index: Int) -> Float {
            return self.buffer[self.wrapIndex(index)].score
        }
        
        // MARK: private helpers
        @inline(__always)
        private func wrapIndex(_ index: Int) -> Int {
            return Utils.wrapIndex(index, start: self.writeIndex - self.bufferSize, end: self.writeIndex, capacity: self.bufferSize)
        }
    }
}
