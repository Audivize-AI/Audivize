//
//  ASDConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/1/25.
//

import Foundation

extension ASD {
    struct ASDConfiguration {
        // frame description
        static let cropScale: CGFloat = 0.40 /// How much to pad the image before cropping for the ASD model
        static let frameSize: CGSize = .init(width: 112, height: 112) /// Size of the ASD model input
        
        // video buffer description
        typealias ASDModel = ASD50_AVA
        static let videoBufferFrontPadding: Int = 0     /// Number of frames to allow ASD to lag
        static let videoBufferBackPadding: Int = 25     /// Number of frames before the video buffer rolls over
        
        // score buffer description
        static let scoreBufferCapacity: Int = 25 + ASDModel.videoLength /// Number of frames for which speaker scores are remembered.
        
        // model pool size
        static let numASDModels: Int = 8 /// Number of models to maintain in the ASD model pool.
        
        // update frequency
        static let framesPerUpdate: Int = 8 /// number of frames between updates.
        static let speakingThreshold: Float = 0.0 /// minimum P(speaking) to label as speaking.
        static let frameRate: Double = 25.0
    }
}
