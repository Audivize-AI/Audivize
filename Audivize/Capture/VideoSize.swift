//
//  VideoSize.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/5/25.
//

import Foundation
import AVFoundation

extension AVCaptureSession.Preset {
    var width: CGFloat {
        switch self {
        case .cif352x288:
            return 352
        case .vga640x480:
            return 640
        case .hd1280x720:
            return 1280
        case .hd1920x1080:
            return 1920
        case .hd4K3840x2160:
            return 3840
        default :
            return .nan
        }
    }
    
    var height: CGFloat {
        switch self {
        case .cif352x288:
            return 288
        case .vga640x480:
            return 480
        case .hd1280x720:
            return 720
        case .hd1920x1080:
            return 1080
        case .hd4K3840x2160:
            return 2160
        default :
            return .nan
        }
    }
    
    var size: CGSize {
        return CGSize(width: width, height: height)
    }
}
