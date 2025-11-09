//
//  ScoreBuffer.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/29/25.
//

import Foundation
import CoreML


extension ASD {
    enum ScoreClass: Int {
        case inactive = 0
        case active = 1
    }
    
    internal struct Score: Sendable {
        public static let nan = Self(.nan)
        
        /// Raw logit score
        public var logit: Float
        
        /// Sigmoid probability
        public var probability: Float { 1.0 / (1.0 + exp(-logit)) }
        
        /// Whether the score is greater than 0
        public var isActive: Bool { logit > 0 }
        
        /// Predicted class (active or inactive) and confidence
        public var label: (class: ScoreClass, confidence: Float) {
            (isActive
             ? (.active, probability)
             : (.inactive, 1 - probability))
        }
        
        public init(_ logit: Float = 0) {
            self.logit = logit
        }
        
        public init(logit: Float) {
            self.logit = logit
        }
        
        public init(probability: Float) {
            self.logit = -logf(1.0 / probability - 1.0)
        }
        
        @inline(__always)
        public mutating func update(with logit: Float) {
            guard !(self.logit.isNaN || logit.isNaN) else { return }
            self.logit += logit
        }
        
        @inline(__always)
        public mutating func update(with logit: Float, replaceNan: Bool) {
            if !(self.logit.isNaN || logit.isNaN) {
                self.logit += logit
            } else if replaceNan && !logit.isNaN {
                self.logit = logit
            }
        }
    }
    
    final class ScoreBuffer: Buffer {
        typealias Element = Score
        
        struct SendableState: Sendable {
            let buffer: ContiguousArray<Score>
            let writeIndex: Int
        }
        
        // MARK: Attributes
        
        var count: Int { self.bufferSize }
        var data: SendableState { .init(buffer: self.buffer, writeIndex: self.writeIndex) }
        var orderedScores: ArraySlice<Score> { self.buffer[self.writeIndex...] + self.buffer[..<self.writeIndex] }
        var orderedLogits: [Float] { self.orderedScores.map(\.logit) }
        var orderedProbabilities: [Float] { self.orderedScores.map(\.probability) }
        
        private var buffer: ContiguousArray<Score>
        private var writeIndex: Int
        private var bufferSize: Int { self.buffer.count }
        
        // MARK: Constructors
        
        public init(capacity: Int) {
            self.writeIndex = 0
            self.buffer = .init(repeating: .init(), count: capacity)
        }
        
        public init(from state: SendableState) {
            self.buffer = state.buffer
            self.writeIndex = state.writeIndex
        }
        
        // MARK: Subscripting
        
        public subscript (_ index: Int) -> Score {
            get { return self.buffer[self.wrapIndex(index)] }
            set { return self.buffer[self.wrapIndex(index)] = newValue }
        }
        
        public subscript (_ index: Int) -> Float {
            get { return self.buffer[self.wrapIndex(index)].logit }
            set { return self.buffer[self.wrapIndex(index)].logit = newValue }
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
        public func write(from source: [Float], count numNew: Int) {
            var i = Utils.mod(self.writeIndex + numNew - source.count, self.bufferSize)
            for score in source[0..<source.count-numNew] {
                self.buffer[i].update(with: score)
                Utils.advance_index(&i, by: 1, modulo: self.bufferSize)
            }
            for logit in source[source.count-numNew..<source.count] {
                self.buffer[self.writeIndex].logit = logit
                Utils.advance_index(&self.writeIndex, by: 1, modulo: self.bufferSize)
            }
        }
        
        /// Read a score from the buffer
        public func read(at index: Int) -> Score {
            return self.buffer[self.wrapIndex(index)]
        }
        
        /// Read a logit from the buffer
        public func readLogit(at index: Int) -> Float {
            return self.buffer[self.wrapIndex(index)].logit
        }
        
        /// Read a probability from the buffer
        public func readProbability(at index: Int) -> Float {
            return self.buffer[self.wrapIndex(index)].probability
        }
        
        // MARK: private helpers
        @inline(__always)
        private func wrapIndex(_ index: Int) -> Int {
            return Utils.wrapIndex(index, start: self.writeIndex - self.bufferSize, end: self.writeIndex, capacity: self.bufferSize)
        }
    }
}
