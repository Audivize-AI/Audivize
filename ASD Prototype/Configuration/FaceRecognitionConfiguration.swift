//
//  FaceRecognitionConfiguration.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/18/25.
//

import Foundation

extension ASD.Tracking {
    struct EmbeddingConfiguration {
        /// Landmark reference points for a 112x112 image
        static let landmarkReferencePoints: [(x: Float, y: Float, z: Float)] = [
            (38.2946, 51.6963, -21.6537595378), /// Left eye center
            (73.5318, 51.5014, -21.6537595378), /// Right eye center
            (56.0252, 71.7366,   0.0000000000), /// Nose
            (41.5493, 92.3655, -20.0756127104), /// Left mouth corner
            (70.7299, 92.2041, -20.0756127104)  /// Right mouth corner
        ]
        
        /// Input image size
        static let imageSize: Int = 112
        
        /// Size of the image that `landmarkReferencePoints` are scaled for.
        static let referenceSize: Int = 112
        
        /// Factor by which to scale the reference points (perhaps to fit more of the face in the image)
        static let referenceScale: Float = 1  // 0.875
        
        static let pitchStep: Float = .pi / 12
        static let rollStep: Float = .pi / 12
    }
}
