//
//  ASDConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/1/25.
//

import Foundation

extension Pairing.ASD {
    struct ASDConfiguration {
        // frame description
        /// How much to pad the image before cropping for the ASD model
        static let cropScale: CGFloat = 0.40
        /// Size of the ASD model input
        static let frameSize: CGSize = .init(width: 112, height: 112)
        
        // video buffer description
        typealias ASDModel = ASD50_AVA
        /// Number of frames to allow ASD to lag
        static let videoBufferFrontPadding: Int = 0
        /// Number of frames before the video buffer rolls over
        static let videoBufferBackPadding: Int = ASD50_AVA.videoLength + 25
        
        // score buffer description
        /// Number of frames for which speaker scores are remembered.
        static let scoreBufferCapacity: Int = 25 + ASDModel.videoLength
        /// 250 frames = 10 seconds
        static let deletionAge: Int = Int(round(frameRate * 10))
        /// Minimum number of missed frames to start a new segment
        static let minSegmentGap: Int = 12
        
        // model pool size
        /// Number of models to maintain in the ASD model pool
        static let numASDModels: Int = 4
        /// Maximum number of concurrent video buffers
        static let numVideoBuffers: Int = 6
        
        // update frequency
        /// number of frames between updates.
        static let framesPerUpdate: Int = 8
        /// minimum P(speaking) to label as speaking.
        static let speakingThreshold: Float = 0.0
        static let frameRate: Double = 30.0
        
    }
}
