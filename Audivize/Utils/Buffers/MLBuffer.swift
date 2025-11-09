import Foundation
import CoreML
import Accelerate

protocol Buffer: AccelerateBuffer, AccelerateMutableBuffer {}

extension Utils {
    class MLBuffer: Buffer {
        typealias Element = Float32
        
        public let numChunks: Int
        public let chunkSize: Int
        
        public var count: Int {
            return self.windowSize
        }
        
        public var chunkViews: some Sequence<ArraySlice<Float>> {
            (0..<self.numChunks).lazy.map{ self[$0] }
        }
        
        public var chunks: some Sequence<Array<Float>> {
            (0..<self.numChunks).lazy.map{ Array(self[$0]) }
        }
        
        private var buffer: ContiguousArray<Float>
        private var writeIndex: Int
        
        private let paddedWindowSize: Int
        private let windowSize: Int
        
        private var shape: [NSNumber]
        private var strides: [NSNumber]
        private var bufferSize: Int { self.buffer.count }
        
        private var startIndex: Int {
            self.writeIndex - self.windowSize
        }
        
        /// - Parameter chunkShape the shape of a chunk
        /// - Parameter defaultChunk what to fill all the chunks with upon intialization
        /// - Parameter length: length of the buffer in chunks
        /// - Parameter frontPadding: number of additional chunks to add to the front of the window so that we can always read at least this many chunks back into the past
        /// - Parameter backPadding: number of chunks that can be written before the contents are shifted to the front
        /// - Parameter strides: strides
        init(chunkShape: [Int], defaultChunk: [Float], length: Int, frontPadding: Int, backPadding: Int, strides: [Int]? = nil) {
            self.shape = ([1, length] + chunkShape).map(NSNumber.init)
            
            if let strides = strides {
                self.strides = strides.map(NSNumber.init)
                self.chunkSize = chunkShape.reduce(1, *)
            } else {
                var strides = [Int](repeating: 0, count: self.shape.count)
                var runningProduct = 1
                for axis in stride(from: self.shape.count - 1, through: 0, by: -1) {
                    strides[axis] = runningProduct
                    runningProduct *= self.shape[axis].intValue
                }
                self.strides = strides.map(NSNumber.init)
                self.chunkSize = strides[1]
            }
            assert(self.chunkSize == defaultChunk.count)
            
            self.windowSize = chunkSize * length
            self.paddedWindowSize = chunkSize * (length + frontPadding)
            self.numChunks = length + frontPadding + backPadding
            self.buffer = []
            self.buffer.reserveCapacity(chunkSize * numChunks)
            for _ in 0..<numChunks {
                buffer.append(contentsOf: defaultChunk)
            }
            
            self.writeIndex = self.paddedWindowSize
        }
        
        // MARK: Buffer
        
        func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Float>) throws -> R) rethrows -> R {
            return try self.buffer.withUnsafeBufferPointer(body)
        }
        
        func withUnsafeMutableBufferPointer<R>(_ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            return try self.buffer.withUnsafeMutableBufferPointer(body)
        }
        
        /// - Parameters:
        ///   - time the time stamp at which the input what obtained
        ///   - body the closure that uses the pointer
        public func withUnsafeWritingPointer<R>(_ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            self.wrapAround(for: self.chunkSize)
            let ptr = try self.buffer[self.writeIndex..<(self.writeIndex + self.chunkSize)].withUnsafeMutableBufferPointer(body)
            self.writeIndex += self.chunkSize
            return ptr
        }
        
        /// - Parameters:
        ///   - time the time stamp at which the input what obtained
        ///   - startIndex window start index (in chunks) (use negative to read from the back)
        ///   - endIndex window end index (in chunks)
        ///   - body the closure that uses the pointer
        /// - Returns: a mutable buffer pointer
        public func withUnsafeWritingPointer<R>(from startIndex: Int, through endIndex: Int, _ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            let writeSize = (endIndex + 1) * self.chunkSize
            self.wrapAround(for: writeSize)
            let upperBound = self.writeIndex + writeSize
            self.writeIndex = self.writeIndex + startIndex * self.chunkSize
            let ptr = try self.buffer[self.writeIndex..<upperBound].withUnsafeMutableBufferPointer(body)
            self.writeIndex = upperBound
            return ptr
        }
        
        /// - Parameters:
        ///   - time the time stamp at which the input what obtained
        ///   - startIndex window start index (in chunks) (use negative to read from the back)
        ///   - endIndex window end index (in chunks)
        ///   - body the closure that uses the pointer
        /// - Returns: a mutable buffer pointer
        @inline(__always)
        public func withUnsafeWritingPointer<R>(from startIndex: Int, to endIndex: Int, _ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            return try self.withUnsafeWritingPointer(from: startIndex, through: endIndex-1, body)
        }
        
        /// - Parameters:
        ///   - time the time stamp at which the input what obtained
        ///   - range the range of offsets from the current writing index (in chunks) that will be included in the buffer pointer
        ///   - body the closure that uses the pointer
        /// - Returns: a mutable buffer pointer
        @inline(__always)
        public func withUnsafeWritingPointer<R>(forRange range: ClosedRange<Int>, _ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            return try self.withUnsafeWritingPointer(from: range.lowerBound, through: range.upperBound, body)
        }
        
        /// - Parameters:
        ///   - time the time stamp at which the input what obtained
        ///   - range the range of offsets from the current writing index (in chunks) that will be included in the buffer pointer
        ///   - body the closure that uses the pointer
        /// - Returns: a mutable buffer pointer
        @inline(__always)
        public func withUnsafeWritingPointer<R>(forRange range: Range<Int>, _ body: (inout UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
            return try self.withUnsafeWritingPointer(from: range.lowerBound, to: range.upperBound, body)
        }
        
        // MARK: subscripting
        
        public subscript(_ chunkIndex: Int) -> ArraySlice<Float> {
            get {
                let startIdx = self.toBufferIndex(from: chunkIndex)
                return self.buffer[startIdx..<(startIdx + self.chunkSize)]
            }
            
            set {
                assert(newValue.count == self.chunkSize)
                memcpy(&self.buffer[self.toBufferIndex(from: chunkIndex)],
                       newValue.withUnsafeBufferPointer { $0.baseAddress! },
                       self.chunkSize * MemoryLayout<Float>.stride)
            }
        }
        
        public subscript(_ range: Range<Int>) -> ArraySlice<Float> {
            get {
                return self.buffer[self.toBufferRange(from: range)]
            }
            
            set {
                assert(range.count * self.chunkSize == newValue.count)
                memcpy(&self.buffer[self.toBufferIndex(from: range.lowerBound)],
                       newValue.withUnsafeBufferPointer { $0.baseAddress! },
                       newValue.count * MemoryLayout<Float>.stride)
            }
        }
        
        // MARK: public methods
        
        /// Swap two axes
        /// - Parameter axis1: the first axis
        /// - Parameter axis2: the second axis
        /// - Returns self after the transposition
        @discardableResult
        public func transpose(axis1: Int, axis2: Int) -> MLBuffer {
            precondition(axis1 > 0 && axis1 < self.strides.count)
            precondition(axis2 > 0 && axis2 < self.strides.count)
            swap(&self.strides[axis1], &self.strides[axis2])
            swap(&self.shape[axis1], &self.shape[axis2])
            return self
        }
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - source the data source from which to write
        public func write(from source: [Float]) {
            let numChunks = source.count / chunkSize
            assert(numChunks * chunkSize == source.count)
            self.wrapAround(for: source.count)
            memcpy(&self.buffer[self.writeIndex],
                   source.withUnsafeBufferPointer { $0.baseAddress! },
                   source.count * MemoryLayout<Float>.stride)
            self.writeIndex += source.count
        }
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - startIndex window start index (in chunks) (use negative to read from the back)
        ///   - endIndex window end index (in chunks)
        ///   - source the data source from which to write
        public func write(from startIndex: Int, through endIndex: Int, from source: [Float]) {
            let writeSize = (endIndex + 1) * self.chunkSize
            self.wrapAround(for: writeSize)
            let upperBound = self.writeIndex + writeSize
            self.writeIndex = self.writeIndex + startIndex * self.chunkSize
            assert(upperBound - writeIndex == source.count)
            
            memcpy(&self.buffer[self.writeIndex],
                   source.withUnsafeBufferPointer { $0.baseAddress! },
                   source.count * MemoryLayout<Float>.stride)
            
            self.writeIndex = upperBound
        }
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - startIndex window start index (in chunks) (use negative to read from the back)
        ///   - endIndex window end index (in chunks)
        ///   - source the data source from which to write
        @inline(__always)
        public func write(from startIndex: Int, to endIndex: Int, from source: [Float]) {
            self.write(from: startIndex, through: endIndex-1, from: source)
        }
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - range the range of offsets from the current writing index (in chunks) that will be written to
        ///   - source the data source from which to write
        public func write(forRange range: ClosedRange<Int>, from source: [Float]) {
            self.write(from: range.lowerBound, through: range.upperBound, from: source)
        }
        
        /// Write to the buffer
        /// - Parameters:
        ///   - time the time at which the input was processed or added
        ///   - range the range of offsets from the current writing index (in chunks) that will be written to
        ///   - source the data source from which to write
        @inline(__always)
        public func write(forRange range: Range<Int>, from source: [Float]) {
            self.write(from: range.lowerBound, to: range.upperBound, from: source)
        }
        
        /// Read the buffer between two indices
        /// - Parameters:
        ///   - index window end index (use negative to read from the back)
        ///   - endIdx window end index
        /// - Returns an MLMultiArray made from the data in the buffer
        public func read(at index: Int) -> MLMultiArray {
            return try! MLMultiArray(
                dataPointer: &self.buffer[self.startIndex + (index + 1) * self.chunkSize],
                shape: self.shape,
                dataType: .float32,
                strides: self.strides
            )
        }
        
        /// Read the buffer between two indices
        /// - Parameters:
        ///   - startIdx window start index (use negative to read from the back)
        ///   - endIdx window end index
        /// - Returns an MLMultiArray made from the data in the buffer
        public func read(from startIdx: Int, to endIdx: Int) -> MLMultiArray {
            var shape = self.shape
            shape[1] = NSNumber(value: endIdx - startIdx)
            
            return try! MLMultiArray(
                dataPointer: &self.buffer[self.toBufferIndex(from: startIdx)],
                shape: shape,
                dataType: .float32,
                strides: self.strides
            )
        }
        
        /// Read the buffer between two indices
        /// - Parameters:
        ///   - startIdx window start index (use negative to read from the back)
        ///   - endIdx window end index
        /// - Returns an MLMultiArray made from the data in the buffer
        public func read(from startIdx: Int, through endIdx: Int) -> MLMultiArray {
            var shape = self.shape
            shape[1] = NSNumber(value: endIdx - startIdx + 1)
            
            return try! MLMultiArray(
                dataPointer: &self.buffer[self.toBufferIndex(from: startIdx)],
                shape: shape,
                dataType: .float32,
                strides: self.strides
            )
        }
        
        /// Read the buffer between two indices
        /// - Parameters:
        ///   - range range from which to read
        /// - Returns an MLMultiArray made from the data in the buffer
        public func read(fromRange range: Range<Int>) -> MLMultiArray {
            return self.read(from: range.lowerBound, to: range.upperBound)
        }
        
        /// Read the buffer between two indices
        /// - Parameters:
        ///   - range range from which to read
        /// - Returns an MLMultiArray made from the data in the buffer
        public func read(fromRange range: ClosedRange<Int>) -> MLMultiArray {
            return self.read(from: range.lowerBound, through: range.upperBound)
        }
        
        @inline(__always)
        private func wrapAround(for writeSize: Int) {
            if self.writeIndex + writeSize > self.bufferSize {
                let copySize = self.paddedWindowSize - writeSize
                let bufferSize = self.bufferSize
                _ = self.buffer.withUnsafeMutableBufferPointer { ptr in
                    memcpy(ptr.baseAddress!,
                           ptr.baseAddress!.advanced(by: bufferSize - copySize),
                           copySize * MemoryLayout<Float>.stride)
                }
                self.writeIndex = copySize
            }
        }
        
        @inline(__always)
        private func toBufferIndex(from chunkIndex: Int) -> Int {
            let index = Utils.wrapIndex(chunkIndex * self.chunkSize,
                                   start: self.startIndex,
                                   end: self.writeIndex,
                                   capacity: self.bufferSize)
            assert(index >= self.startIndex)
            return index
        }
        
        @inline(__always)
        private func toBufferRange(from range: Range<Int>) -> Range<Int> {
            let range = Utils.wrapRange(range.lowerBound * self.chunkSize,
                                        range.upperBound * self.chunkSize,
                                        start: self.startIndex,
                                        end: self.writeIndex,
                                        capacity: self.bufferSize)
            assert(range.lowerBound >= self.startIndex)
            return range
        }
        
        @inline(__always)
        private func toBufferClosedRange(from range: ClosedRange<Int>) -> ClosedRange<Int> {
            let range = Utils.wrapClosedRange(range.lowerBound * self.chunkSize,
                                              range.upperBound * self.chunkSize,
                                              start: self.startIndex,
                                              end: self.writeIndex,
                                              capacity: self.bufferSize)
            assert(range.lowerBound >= self.startIndex)
            return range
        }
    }
}
