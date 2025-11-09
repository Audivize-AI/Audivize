//
//  TimedMultiArrayBuffer.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/29/25.
//

import Foundation


import Foundation
import CoreML
import Accelerate

extension Utils {
    class TimestampedMLBuffer: MLBuffer {
        public var lastWriteTime: Double { self.timestamps.lastWriteTime }
        private let timestamps: Utils.TimestampBuffer
        
        /// - Parameter chunkShape the shape of a chunk
        /// - Parameter defaultChunk what to fill all the chunks with upon intialization
        /// - Parameter length: length of the buffer in chunks
        /// - Parameter frontPadding: number of additional chunks to add to the front of the window so that we can always read at least this many chunks back into the past
        /// - Parameter backPadding: number of chunks that can be written before the contents are shifted to the front
        /// - Parameter strides: strides
        init(atTime time: Double, chunkShape: [Int], defaultChunk: [Float], length: Int, frontPadding: Int, backPadding: Int, strides: [Int]? = nil) {
            self.timestamps = .init(atTime: time, capacity: length + frontPadding + backPadding)
            super.init(chunkShape: chunkShape, defaultChunk: defaultChunk, length: length, frontPadding: frontPadding, backPadding: backPadding, strides: strides)
        }
        
        // MARK: Writing Pointer
        
        /// - Parameters:
        ///   - time the time stamp at which the input what obtained
        ///   - body the closure that uses the pointer
        public func withUnsafeWritingPointer<R>(atTime time: Double, _ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            let ptr = try super.withUnsafeWritingPointer(body)
            self.timestamps.write(atTime: time, count: 1)
            return ptr
        }
        
        /// - Parameters:
        ///   - time the time stamp at which the input what obtained
        ///   - startIndex window start index (in chunks) (use negative to read from the back)
        ///   - endIndex window end index (in chunks)
        ///   - body the closure that uses the pointer
        /// - Returns: a mutable buffer pointer
        public func withUnsafeWritingPointer<R>(atTime time: Double, from startIndex: Int, through endIndex: Int, _ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            let ptr = try super.withUnsafeWritingPointer(from: startIndex, through: endIndex, body)
            if endIndex >= 0 {
                self.timestamps.write(atTime: time, count: endIndex + 1)
            }
            return ptr
        }
        
        /// - Parameters:
        ///   - time the time stamp at which the input what obtained
        ///   - startIndex window start index (in chunks) (use negative to read from the back)
        ///   - endIndex window end index (in chunks)
        ///   - body the closure that uses the pointer
        /// - Returns: a mutable buffer pointer
        @inline(__always)
        public func withUnsafeWritingPointer<R>(atTime time: Double, from startIndex: Int, to endIndex: Int, _ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            return try self.withUnsafeWritingPointer(atTime: time, from: startIndex, through: endIndex-1, body)
        }
        
        /// - Parameters:
        ///   - time the time stamp at which the input what obtained
        ///   - range the range of offsets from the current writing index (in chunks) that will be included in the buffer pointer
        ///   - body the closure that uses the pointer
        /// - Returns: a mutable buffer pointer
        @inline(__always)
        public func withUnsafeWritingPointer<R>(atTime time: Double, forRange range: ClosedRange<Int>, _ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            return try self.withUnsafeWritingPointer(atTime: time, from: range.lowerBound, through: range.upperBound, body)
        }
        
        /// - Parameters:
        ///   - time the time stamp at which the input what obtained
        ///   - range the range of offsets from the current writing index (in chunks) that will be included in the buffer pointer
        ///   - body the closure that uses the pointer
        /// - Returns: a mutable buffer pointer
        @inline(__always)
        public func withUnsafeWritingPointer<R>(atTime time: Double, forRange range: Range<Int>, _ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            return try self.withUnsafeWritingPointer(atTime: time, from: range.lowerBound, to: range.upperBound, body)
        }
        
        // MARK: writing
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - source the data source from which to write
        public func write(atTime time: Double, from source: [Float]) {
            super.write(from: source)
            self.timestamps.write(atTime: time, count: 1)
        }
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - startIndex window start index (in chunks) (use negative to read from the back)
        ///   - endIndex window end index (in chunks)
        ///   - source the data source from which to write
        public func write(atTime time: Double, from startIndex: Int, through endIndex: Int, from source: [Float]) {
            super.write(from: startIndex, through: endIndex, from: source)
            if endIndex >= 0 {
                self.timestamps.write(atTime: time, count: endIndex + 1)
            }
        }
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - startIndex window start index (in chunks) (use negative to read from the back)
        ///   - endIndex window end index (in chunks)
        ///   - source the data source from which to write
        @inline(__always)
        public func write(atTime time: Double, from startIndex: Int, to endIndex: Int, from source: [Float]) {
            self.write(atTime: time, from: startIndex, through: endIndex-1, from: source)
        }
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - range the range of offsets from the current writing index (in chunks) that will be written to
        ///   - source the data source from which to write
        public func write(atTime time: Double, forRange range: ClosedRange<Int>, from source: [Float]) {
            self.write(atTime: time, from: range.lowerBound, through: range.upperBound, from: source)
        }
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - range the range of offsets from the current writing index (in chunks) that will be written to
        ///   - source the data source from which to write
        public func write(atTime time: Double, forRange range: Range<Int>, from source: [Float]) {
            self.write(atTime: time, from: range.lowerBound, to: range.upperBound, from: source)
        }
        
        // MARK: Reading
        
        /// Get the tensor that corresponds to the timestamp
        /// - Parameters:
        ///   - time window end timestamp
        /// - Returns an MLMultiArray made from the data in the buffer
        @inline(__always)
        public func read(atTime time: Double) -> MLMultiArray {
            let index = self.getIndex(for: time)
            return self.read(at: index)
        }
        
        /// Read the buffer between two timestamps
        /// - Parameters:
        ///   - startTime window start timestamp
        ///   - endTime window end timestamp
        /// - Returns an MLMultiArray made from the data in the buffer
        @inline(__always)
        public func read(from startTime: Double, to endTime: Double) -> MLMultiArray {
            return self.read(from: self.getIndex(for: startTime),
                             to: self.getIndex(for: endTime))
        }
        
        /// Read the buffer between two timestamps
        /// - Parameters:
        ///   - startTime window start timestamp
        ///   - endTime window end timestamp
        /// - Returns an MLMultiArray made from the data in the buffer
        @inline(__always)
        public func read(from startTime: Double, through endTime: Double) -> MLMultiArray {
            return self.read(from: self.getIndex(for: startTime),
                             through: self.getIndex(for: endTime))
        }
        
        /// Convert timestamp to an index
        /// - Parameter time the timestamp
        /// - Returns the index of the chunk in the buffer
        @inline(__always)
        public func getIndex(for time: Double) -> Int {
            return self.timestamps.indexOf(time)
        }
    }
}
