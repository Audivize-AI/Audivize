//
//  MergeRequest.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/1/25.
//

import Foundation

extension ASD {
    public struct MergeRequest: Sendable {
        public let sourceID: UUID
        public let targetID: UUID
        
        init (from sourceID: UUID, into targetID: UUID) {
            self.sourceID = sourceID
            self.targetID = targetID
        }
    }
}
