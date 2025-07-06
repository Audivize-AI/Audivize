//
//  DetectionConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/1/25.
//

import Foundation

extension ASD.Tracking {
    internal static let detectorConfidenceThreshold: Float = 0.6
    internal static let embedderRequestLifespan: DispatchTimeInterval = .seconds(5)
    internal static let minReadyEmbedderRequests: Int = 8
}
