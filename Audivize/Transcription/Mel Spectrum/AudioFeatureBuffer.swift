//
//  MFCCBuffer.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/27/25.
//

import Foundation
import AVFoundation


extension ASD {
    final class AudioFeatureBuffer: Utils.TimestampedMLBuffer {
        private var mfcc: MFCC
        private static let defaultChunk: [Float] = [-36.04365339, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] // the result of python_speech_features.mfcc(np.zeros((10000,), float), nfilt=32)
        
        init(atTime time: Double, length: Int = 100, frontPadding: Int = 25, backPadding: Int = 25) {
            self.mfcc = MFCC(.init())
            super.init(
                atTime: time,
                chunkShape: [13], // 13 MFCC Features
                defaultChunk: AudioFeatureBuffer.defaultChunk,
                length: length,
                frontPadding: frontPadding,
                backPadding: backPadding
            )
        }
        
        public override func write(atTime time: Double, from signal: [Float]) {
            let (range, features) = mfcc.update(signal: signal)
            self.write(atTime: time, forRange: range, from: features)
        }
    }
}
