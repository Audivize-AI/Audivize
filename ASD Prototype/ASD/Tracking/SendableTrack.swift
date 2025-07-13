//
//  SendableTrack.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/1/25.
//

import Foundation

extension ASD.Tracking {
    public final class SendableTrack: Sendable {
        let id: UUID
        let status: Track.Status
        let rect: CGRect
        let misses: Int
        let costString: String
        let embedding: [Float]
        
        init(_ track: Track) {
            self.id = track.id
            self.status = track.status
            self.costString = /*"\(track.costs.string)\n*/"Appearance (Average): \(String(format: "%.2f", 10 * track.averageAppearanceCost))"
            self.rect = track.rect
            self.misses = -track.hits
            self.embedding = track.embedding
        }
    }
}
