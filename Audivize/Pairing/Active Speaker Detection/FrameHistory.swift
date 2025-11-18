//
//  FrameMask.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/14/25.
//

import Foundation

extension Pairing.ASD {
    struct FrameHistory: Sendable, Sequence {
        typealias Element = Bool
        typealias Iterator = BitIterator
        typealias BitMask = UInt64
        
        public static let count = ASDConfiguration.ASDModel.videoLength
        public static let minGapSize = ASDConfiguration.minSegmentGap
        private static let gapMask: BitMask = (~0 &<< (count - minGapSize)) & mask
        private static let writeMask: BitMask = 1 &<< (count-1)
        private static let mask: BitMask = (1 &<< count) - 1
        private static let padding: Int = BitMask.bitWidth - count
        
        public var history: BitMask = 0
        public var hits: HitIterator { .init(history) }
        public var chunks: ChunkIterator { .init(history) }
        
        public var count: Int { Self.count }
        public var numHits: Int { history.nonzeroBitCount }
        public var numMisses: Int { count - history.nonzeroBitCount }
        public var hitStreak: Int { (~history << Self.padding).leadingZeroBitCount }
        public var missStreak: Int { history.leadingZeroBitCount - Self.padding }
        
        public var isEmpty: Bool { history == 0 }
        public var isFull: Bool { history == Self.mask }
        
        public init(_ mask: BitMask = 0) {
            self.history = mask
        }
        
        public mutating func registerHit() {
            // Fill end gap if it's sufficiently small
            if (history & Self.writeMask) == 0 && (history & Self.gapMask) != 0 {
                let sealShift = BitMask.bitWidth - history.leadingZeroBitCount
                let sealMask = (~(0 as BitMask) << sealShift) & Self.mask
                history |= sealMask
            }
            
            // Add frame
            history = (history &>> 1) | Self.writeMask
        }
        
        public mutating func registerMiss() {
            history &>>= 1
        }
        
        public mutating func reset(to mask: BitMask = 0) {
            history = mask
        }
        
        public func makeIterator() -> BitIterator {
            .init(history)
        }
    }
    
}

extension Pairing.ASD.FrameHistory {
    internal struct BitIterator: IteratorProtocol, Sequence {
        typealias Element = Bool
        private let mask: BitMask
        private var bit: BitMask = 1
        
        init(_ mask: BitMask) {
            self.mask = mask
        }
        
        /// Get next set bit
        mutating func next() -> Bool? {
            guard bit != 0 else { return nil }
            defer { bit &<<= 1 }
            return (bit & mask) != 0
        }
    }
    
    internal struct HitIterator: IteratorProtocol, Sequence {
        typealias Element = Int
        private var mask: BitMask
        
        init(_ mask: BitMask) {
            self.mask = mask
        }
        
        /// Get next set bit
        mutating func next() -> Int? {
            guard mask != 0 else { return nil }
            defer { mask &= (mask - 1) }
            return mask.trailingZeroBitCount
        }
    }
    
    struct ChunkIterator: IteratorProtocol, Sequence {
        typealias Element = Range<Int>
        private let mask: BitMask
        private var chunkStarts: BitMask
        private var chunkEnds: BitMask
        
        init(_ mask: BitMask) {
            self.mask = mask
            self.chunkStarts = mask & ~(mask &<< 1)  // 0 -> 1 transitions
            self.chunkEnds = ~mask & (mask &<< 1)    // 1 -> 0 transitions
        }
        
        /// Get next set bit
        mutating func next() -> Range<Int>? {
            guard chunkStarts != 0 else { return nil }
            defer {
                chunkStarts &= (chunkStarts &- 1)
                chunkEnds &= (chunkEnds &- 1)
            }
            let start = chunkStarts.trailingZeroBitCount
            let end = chunkEnds.trailingZeroBitCount
            return start..<end
        }
        
        func reversed() -> ReversedChunkIterator {
            .init(mask)
        }
    }

    internal struct ReversedChunkIterator: IteratorProtocol, Sequence {
        typealias Element = Range<Int>
        private let mask: BitMask
        private var chunkStarts: BitMask
        private var chunkEnds: BitMask
        
        init(_ mask: BitMask) {
            self.mask = mask
            self.chunkStarts = mask & ~(mask &<< 1)  // 0 -> 1 transitions
            self.chunkEnds = mask & ~(mask &>> 1)    // 1 -> 0 transitions
        }
        
        /// Get next set bit
        mutating func next() -> Range<Int>? {
            guard chunkStarts != 0 else { return nil }
            let start = BitMask.bitWidth - chunkStarts.leadingZeroBitCount - 1
            let end = BitMask.bitWidth - chunkEnds.leadingZeroBitCount
            chunkStarts ^= (1 as BitMask) &<< start
            chunkEnds ^= (1 as BitMask) &<< (end - 1)
            return start..<end
        }
        
        func reversed() -> ChunkIterator {
            .init(mask)
        }
    }
}
