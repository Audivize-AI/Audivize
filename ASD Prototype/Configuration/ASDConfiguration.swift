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
        static let videoLength: Int = 25                /// Number of frames used for ASD
        static let videoBufferFrontPadding: Int = 0     /// Number of frames to allow ASD to lag
        static let videoBufferBackPadding: Int = 25     /// Number of frames before the video buffer rolls over

        // score buffer description
        static let scoreBufferCapacity: Int = 25 + videoLength /// Number of frames for which speaker scores are remembered.
        
        // model pool size
        static let numASDModels: Int = 8 /// Number of models to maintain in the ASD model pool.
    }
}
