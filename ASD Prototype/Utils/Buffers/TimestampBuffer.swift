//
//  TimestampBuffer.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/27/25.
//

import Foundation
import AVFoundation


extension Utils {
    class TimestampBuffer: Buffer {
        typealias Element = Double
        
        struct SendableState: Sendable {
            let buffer: ContiguousArray<Element>
            let writeIndex: Int
            let startIndex: Int
            let lastWriteTime: Element
        }
        
        // MARK: Public Attributes
        public private(set) var lastWriteTime: Element
        public var count: Int { writeIndex - startIndex }
        public var timestamps: [Element] {
            (self.startIndex...self.endIndex).lazy.map { i in
                self.buffer[i < 0 ? i + self.buffer.count : i]
            }
        }
        
        public var data: SendableState {
            .init(buffer: self.buffer,
                  writeIndex: self.writeIndex,
                  startIndex: self.startIndex,
                  lastWriteTime: self.lastWriteTime)
        }

        // MARK: Private attributes
        private var buffer: ContiguousArray<Element>
        private var writeIndex: Int = 0
        private var startIndex: Int = 0
        private var endIndex: Int { self.writeIndex - 1 }
        
        // MARK: Constructors
        public init(atTime time: Element, capacity: Int) {
            self.buffer = .init(repeating: -1, count: capacity)
            self.lastWriteTime = time
        }
        
        public init(from data: SendableState) {
            self.buffer = data.buffer
            self.startIndex = data.startIndex
            self.writeIndex = data.writeIndex
            self.lastWriteTime = data.lastWriteTime
        }
        
        // MARK: Subscripting
        public subscript (_ index: Int) -> Element {
            get {
                self.buffer[wrapIndex(index, start: self.startIndex, end: self.writeIndex, capacity: self.buffer.count)]
            }
            set {
                self.buffer[wrapIndex(index, start: self.startIndex, end: self.writeIndex, capacity: self.buffer.count)] = newValue
            }
        }
        
        // MARK: Public methods
        public func indexOf(_ t: Element) -> Int {
            var lo = self.startIndex - self.writeIndex, hi = -1
            
            var tLow = self[lo]
            var tHigh = self[hi]
            
            if t <= tLow { return lo }
            if t >= tHigh { return hi }
            
            while true {
                // estimate position
                let pos = lo + Int((t - tLow) * Element(hi-lo) / (tHigh - tLow) + 0.5)
                
                if pos <= lo || pos >= hi {
                    return pos
                }
                
                let value = self[pos]
                if value < t {
                    lo = pos
                    tLow = value
                } else if value > t {
                    hi = pos
                    tHigh = value
                } else {
                    return pos
                }
            }
        }
        
        public func write(atTime time: Element, count: Int) {
            switch count {
            case 0: return
            case 1: self.write(atTime: time)
            default:
                let timestamps = ML.linspace(past: self.lastWriteTime, through: time, count: count)
                let bufferSize = self.buffer.count
                
                timestamps.withUnsafeBufferPointer { timePtr in
                    self.buffer.withUnsafeMutableBufferPointer { bufferPtr in
                        let bufferBase = bufferPtr.baseAddress!
                        let timeBase = timePtr.baseAddress!
                        
                        if self.writeIndex + count < bufferSize {
                            memcpy(bufferBase + self.writeIndex,
                                   timeBase,
                                   MemoryLayout<Element>.stride * count)
                            self.writeIndex += count
                            if self.startIndex != 0 {
                                self.startIndex += count
                            }
                        } else {
                            let firstCount = bufferSize - self.writeIndex
                            memcpy(bufferBase.advanced(by: self.writeIndex),
                                   timeBase,
                                   MemoryLayout<Element>.stride * firstCount)
                            memcpy(bufferBase,
                                   timeBase.advanced(by: firstCount),
                                   MemoryLayout<Element>.stride * (count - firstCount))
                            self.writeIndex = count - firstCount
                            self.startIndex = self.writeIndex - bufferSize
                        }
                    }
                }
            }
            self.lastWriteTime = time
        }
        
        public func write(atTime time: Element) {
            if self.writeIndex < self.buffer.count {
                self.buffer[self.writeIndex] = time
                self.writeIndex += 1
                if startIndex != 0 {
                    self.startIndex += 1
                }
            } else {
                self.buffer[0] = time
                self.writeIndex = 1
                self.startIndex = 1 - self.buffer.count
            }
            self.lastWriteTime = time
        }
        
        // MARK: Alignment
        public func computeAlignmentError(from startIndex: Int, to endIndex: Int, with expectedDuration: Double, tolerance: Double? = nil) -> Double {
            let actualDuration = self[endIndex] - self[startIndex]
            return fabs(actualDuration - expectedDuration)
        }
        
        public func isAligned(from startIndex: Int, to endIndex: Int, with duration: Double, tolerance: Double? = nil) -> Bool {
            let tolerance = tolerance ?? 0.5 / Double(endIndex - startIndex)
            return computeAlignmentError(from: startIndex, to: endIndex, with: duration) <= tolerance
        }
        
        public func computeAlignmentError(from startTime: Double, to endTime: Double, with expectedCount: Int) -> Int {
            let actualCount = indexOf(endTime) - indexOf(startTime) + 1
            return abs(actualCount - expectedCount)
        }
        
        public func isAligned(from startTime: Double, to endTime: Double, with expectedCount: Int, tolerance: Int = 0) -> Bool {
            return computeAlignmentError(from: startTime, to: endTime, with: expectedCount) <= tolerance
        }
        
        // MARK: Buffer
        
        func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R {
            return try self.buffer.withUnsafeBufferPointer(body)
        }
        
        func withUnsafeMutableBufferPointer<R>(_ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R {
            return try self.buffer.withUnsafeMutableBufferPointer(body)
        }
    }
}
