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


extension ASD {
    struct SendableSpeaker:
        Sendable,
        Identifiable,
        Hashable,
        Equatable
    {
        let id: UUID
        let rect: CGRect
        let costString: String
        let status: Tracking.Track.Status
        let misses: Int
        let score: Float
        
        var string: String { "ID: \(id.uuidString)\n\(self.costString)\nScore: \(score)" }
        
        init(track: Tracking.SendableTrack, score: Float, mirrored: Bool, rect: CGRect? = nil) {
            self.id = track.id
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
            self.score = score
        }
        
        static func == (lhs: SendableSpeaker, rhs: SendableSpeaker) -> Bool {
            return lhs.id == rhs.id
        }
        
        nonisolated public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}
