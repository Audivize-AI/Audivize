//
//  CaptureConfig.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/5/25.
//

import Foundation
import AVFoundation

extension Global {
    static let videoPreset: AVCaptureSession.Preset = .hd1280x720
    static let videoWidth = videoPreset.width
    static let videoHeight = videoPreset.height
    static let videoSize = videoPreset.size
}
