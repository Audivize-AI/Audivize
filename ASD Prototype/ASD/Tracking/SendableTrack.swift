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
        let name: String?
        let iteration: UInt
        let status: Track.Status
        let rect: CGRect
        let misses: Int
        let costString: String
        let embedding: [Float]
        let landmarks: [CGPoint]
        
        init(_ track: Track) {
            self.id = track.id
            self.name = track.name
            self.status = track.status
            self.costString = "maha: \(track.costs.mahaDist),\nIoU: \(track.costs.iou),\nAppearance: \(track.costs.appearance),\nConfidence: \(track.costs.confidence)"
            self.rect = track.rect
            self.misses = -track.hits
            self.embedding = track.embedding
            self.iteration = track.iteration
            self.landmarks = track.landmarks
        }
    }
}
