//
//  PairingEvaluation.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/9/25.
//

import Foundation

extension Pairing {
    public static func softIoU(visualScores: Pairing.ASD.ScoreSegment, voiceSegment: Voice.VoiceSegment) -> Float {
        let speechStartIndex = visualScores.getLocalIndex(forTime: voiceSegment.startTime)
        let speechEndIndex = visualScores.getLocalIndex(forTime: voiceSegment.endTime)
        let lo = Swift.max(0, speechStartIndex)
        let hi = Swift.min(visualScores.count, speechEndIndex)
        
        let confidence: Float = voiceSegment.confidence.probability
        guard hi > lo && confidence > 0 else { return 0 }
        
        var sumOverlap: Float = 0
        var sumAll: Float = 0
        
        for (i, score) in visualScores.scores.enumerated() {
            let probability = score.probability
            if lo <= i && i < hi {
                sumOverlap += probability
            }
            sumAll += probability
        }
        
        let sumAllSpeech = confidence * Float(hi - lo)
        let intersection = sumOverlap * confidence
        let union = sumAll + sumAllSpeech - intersection
        
        return intersection / union
    }
}
