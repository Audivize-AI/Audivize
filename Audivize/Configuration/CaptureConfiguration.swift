//
//  CaptureConfig.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/5/25.
//

import Foundation
@preconcurrency import AVFoundation

struct CaptureConfiguration {
    static let videoPreset: AVCaptureSession.Preset = .hd1920x1080
    
    fileprivate static let frontCameraMax = getHighestResolutionFormat(for: .front)
    fileprivate static let backCameraMax = getHighestResolutionFormat(for: .back)
    
    static var frontCameraMaxFormat: AVCaptureDevice.Format? { frontCameraMax?.format }
    static var backCameraMaxFormat: AVCaptureDevice.Format? { backCameraMax?.format }
    static var frontCameraMaxDimensions: CMVideoDimensions? { frontCameraMax?.dimensions }
    static var backCameraMaxDimensions: CMVideoDimensions? { backCameraMax?.dimensions }
    
    static let frontVideoWidth: CGFloat? = frontCameraMaxDimensions.map { CGFloat($0.width) }
    static let frontVideoHeight: CGFloat? = frontCameraMaxDimensions.map { CGFloat($0.height) }
    
    static let backVideoWidth: CGFloat? = backCameraMaxDimensions.map { CGFloat($0.width) }
    static let backVideoHeight: CGFloat? = backCameraMaxDimensions.map { CGFloat($0.height) }
    
    static var supportsFront: Bool { frontVideoWidth != nil }
    static var supportsBack: Bool { backVideoWidth != nil }
    static var supportsCamera: Bool { supportsBack || supportsFront }
    
    static let preferedCameraPosition: AVCaptureDevice.Position = .front
    
    static let videoWidth: CGFloat = videoPreset.width //(preferedCameraPosition == .front
//                                      ? frontVideoWidth ?? backVideoWidth ?? -1
//                                      : backVideoWidth ?? frontVideoWidth ?? -1)
    static let videoHeight: CGFloat = videoPreset.height //(preferedCameraPosition == .front
//                                       ? frontVideoHeight ?? backVideoHeight ?? -1
//                                       : backVideoHeight ?? frontVideoHeight ?? -1)
    static var videoSize: CGSize {
        .init(width: videoWidth, height: videoHeight)
    }
    
    private static func getHighestResolutionFormat(for position: AVCaptureDevice.Position) -> (format: AVCaptureDevice.Format, dimensions: CMVideoDimensions)? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return nil
        }
        var bestFormat: AVCaptureDevice.Format?
        var maxResolution: CMVideoDimensions = CMVideoDimensions(width: 0, height: 0)
        
        for format in device.formats {
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)

            if dims.width * dims.height > maxResolution.width * maxResolution.height {
                bestFormat = format
                maxResolution = dims
            }
        }

        if let best = bestFormat {
            print("max resolution for \(position): \(maxResolution.width)x\(maxResolution.height)")
            return (best, maxResolution)
        } else {
            return nil
        }
    }
}
 
