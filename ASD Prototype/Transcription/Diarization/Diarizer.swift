//
//  Diarizer.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/9/25.
//

import Foundation
import FluidAudio
import CoreMedia

// Initialize and process audio

class Diarizer {
    private let diarizer = DiarizerManager()
    private var samples: [Float]
    
    init() throws {
        self.samples = []
        self.samples.reserveCapacity(16000*3)
        let diarizer = self.diarizer
        Task {
            try await diarizer.initialize()
        }
    }
    
    
    func diarize(from sampleBuffer: CMSampleBuffer) {
        self.samples.append(contentsOf: ASD.resampleAudioToFloat32(from: sampleBuffer, to: 16000))
        if self.samples.count > 8000 * 3 {
            let diarizer = self.diarizer
            let samples = self.samples
            Task.detached {
                let result = try await diarizer.performCompleteDiarization(samples, sampleRate: 16000)
                print("num segments: \(result.segments.count)")
                for segment in result.segments {
                    print("\(segment.speakerId): \(segment.startTimeSeconds)s - \(segment.endTimeSeconds)s")
                }
            }
            self.samples.removeAll(keepingCapacity: true)
        }
    }
}
