//
//  TrackData.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/21/25.
//

import Foundation
import CoreVideo
import CoreGraphics
import Vision


extension Pairing {
    struct SendableSpeaker:
        Sendable,
        Identifiable,
        Hashable,
        Equatable
    {
        let id: UUID                                                    /// Speaker ID
        let name: String?                                               /// Speaker name
        let rect: CGRect                                                /// Bounding box
        let costString: String                                          /// Cost summary (Debugging)
        let status: Tracking.Track.Status                               /// Visual track status
        let misses: Int                                                 /// Number of consecutive misses
        let speechHistory: [(timestamp: TimeInterval, score: Float)]    /// Speaker probabilities
        let score: Float
        var probability: Float { 1.0 / (1.0 + exp(-self.score)) }
        var isSpeaking: Bool { return self.score > 0 }
        var string: String {
            " \(self.name ?? String(id.uuidString.prefix(4))) \(self.isSpeaking ? "is speaking " : " ")" //+
            //"\nP = \(String(format: "%.2f", probability))" +
            //"\n\(costString)"
        }
        
        init(track: Tracking.SendableTrack, speechHistory: [(timestamp: TimeInterval, score: Float)], mirrored: Bool, rect: CGRect? = nil) {
            self.id = track.id
            self.name = track.name
            let rect = rect ?? track.rect
            if mirrored {
                self.rect = rect
            } else {
                self.rect = CGRect(
                    x: 1 - rect.maxX,
                    y: rect.minY,
                    width: rect.width,
                    height: rect.height
                )
            }
            self.status = track.status
            self.costString = track.costString
            self.misses = track.misses
            self.score = speechHistory.last?.score ?? 0
            self.speechHistory = speechHistory
        }
        
        static func == (lhs: SendableSpeaker, rhs: SendableSpeaker) -> Bool {
            return lhs.id == rhs.id
        }
        
        nonisolated public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}
