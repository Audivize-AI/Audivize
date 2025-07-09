//
//  AudioEncoder.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/28/25.
//

import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreML

extension ASD {
    final actor AudioEncoder {
        public var lastWriteTime: Double { self.audioFeatures.lastWriteTime }
        
        private static let inputLength: Int = 100
        
//        private let model: ASDAudioEncoder
        private let audioFeatures: AudioFeatureBuffer
        
        public init(atTime time: Double, frontPadding: Int = 3, backPadding: Int = 25) {
            self.audioFeatures = .init(atTime: time,
                                       length: AudioEncoder.inputLength,
                                       frontPadding: frontPadding,
                                       backPadding: backPadding)
            let config = MLModelConfiguration()
            config.computeUnits = .all
//            self.model = try! ASDAudioEncoder(configuration: config)
        }
        
        public func update(atTime time: Double, from signal: [Float]) {
            self.audioFeatures.write(atTime: time, from: signal)
        }
        
        public func encode(atTime time: Double) throws -> MLMultiArray {
            let features = self.audioFeatures.read(atTime: time)
//            let input = ASDAudioEncoderInput(audioFeatures: features)
//            return try self.model.prediction(input: input).audioEmbedding
            return .init()
        }
    }
}

//extension ASDAudioEncoderOutput: @unchecked Sendable {}
