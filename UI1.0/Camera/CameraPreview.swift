//
//  CameraPreview.swift
//  audi
//
//  Created by Sebastian Zimmerman on 12/17/25.
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill

        v.applyOrientation()

        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.applyOrientation()
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds

        applyOrientation()
    }

    /// Sets the AVCaptureVideoPreviewLayer orientation to match the current interface orientation.
    func applyOrientation() {
        guard let connection = videoPreviewLayer.connection,
              connection.isVideoOrientationSupported else { return }

        let io = window?.windowScene?.interfaceOrientation ?? .portrait
        connection.videoOrientation = AVCaptureVideoOrientation(io)
    }
}

private extension AVCaptureVideoOrientation {
    init(_ interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: self = .portrait
        }
    }
}
