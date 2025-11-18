//
//  VoiceSegment.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/10/25.
//

import Foundation
import FluidAudio
import CoreMedia

extension Voice {
    struct DiarizerResult {
        let inputStartTime: TimeInterval
        let inputEndTime: TimeInterval
        let segments: [TimedSpeakerSegment]
    }
    
    struct TimeRange {
        let start: TimeInterval
        let end: TimeInterval
    }
    
    struct VoiceSegment {
        public var startTime: TimeInterval
        public var endTime: TimeInterval
        public var confidence: Pairing.ASD.Score
        
        public var duration: TimeInterval { endTime - startTime }
        
        public mutating func update(with segment: TimedSpeakerSegment, from inputTimeRange: TimeRange, inputEndTime: TimeInterval) {
            
        }
    }
}
