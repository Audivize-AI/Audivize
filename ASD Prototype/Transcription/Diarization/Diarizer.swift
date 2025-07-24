//
//  Diarizer.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/9/25.
//

import Foundation
import FluidAudio
import CoreMedia
import Accelerate

// Initialize and process audio

class Diarizer: @unchecked Sendable {
    struct VoicePrint {
        var embedding: [Float]
        var hits: Int = 1
        
        mutating func update(with embedding: [Float]) {
            vDSP.multiply(1 / Float(self.hits+1),
                          vDSP.add(vDSP.multiply(Float(self.hits), self.embedding),
                                   embedding),
                          result: &self.embedding)
            self.hits += 1
        }
    }
    
    private let diarizer: DiarizerManager
    
    private var speakers: [VoicePrint] = []
    private var samples: [Float]
    private let similarityThreshold: Float = 0.7
    private let chunkSize = 16000 * 3
    private let frequency = 3
    private let period: Int
    
    init() throws {
        self.samples = []
        self.samples.reserveCapacity(chunkSize + 8000)
        self.period = 16000 / frequency
        
        self.diarizer = .init(config: .init(
            clusteringThreshold: self.similarityThreshold,
            minDurationOn: 0.5,
            minDurationOff: 0.5,
            debugMode: false
        ))
        Task {
            try await diarizer.initialize()
        }
    }
    
    func diarize(from sampleBuffer: CMSampleBuffer) {
        self.samples.append(contentsOf: ASD.resampleAudioToFloat32(from: sampleBuffer, to: 16000))
        if self.samples.count >= chunkSize {
            let tmpSamples = self.samples
            Task.detached {
                let result = try self.diarizer.performCompleteDiarization(tmpSamples)
                
                for segment in result.segments {
                    let speaker = self.determineSpeaker(segment.embedding)
                    print("\(speaker.index): \(segment.startTimeSeconds)s - \(segment.endTimeSeconds)s")
                }
            }
            self.samples.removeFirst(chunkSize - (self.samples.count - period))
        }
    }
    
    private func determineSpeaker(_ embedding: [Float]) -> (index: Int, similarity: Float) {
        var best: (index: Int, similarity: Float) = (-1, self.similarityThreshold)
        for (i, speaker) in speakers.enumerated() {
            let similarity = cosineSimilarity(from: embedding, to: speaker.embedding)
            if similarity > best.similarity {
                best = (i, similarity)
            }
        }
        if best.index != -1 {
            self.speakers[best.index].update(with: embedding)
            return best
        }
        self.speakers.append(.init(embedding: embedding))
        return (self.speakers.count, 1)
    }
    
    @inline(__always)
    private func cosineSimilarity(from a: [Float], to b: [Float]) -> Float {
        let dotAB = vDSP.dot(a, b)
        let normAB = sqrt(vDSP.sumOfSquares(a) * vDSP.sumOfSquares(b))
        return dotAB / normAB
    }
}
