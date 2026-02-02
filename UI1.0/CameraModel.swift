//
//  CameraModel.swift
//  audi
//
//  Created by Sebastian Zimmerman on 12/17/25.
//

import AVFoundation
import Combine

final class CameraModel: ObservableObject {
    @Published var showPermissionAlert = false
    private var videoDevice: AVCaptureDevice?
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    private var isConfigured = false

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.start() }
                    else { self.showPermissionAlert = true }
                }
            }
        default:
            showPermissionAlert = true
        }
    }

    func start() {
        sessionQueue.async {
            if !self.isConfigured {
                self.configureSession()
                self.isConfigured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    @discardableResult
    func setZoomFactor(_ zoom: CGFloat) -> CGFloat {
        var applied: CGFloat = zoom

        sessionQueue.sync {
            guard let device = self.videoDevice else { return }

            let minZoom = device.minAvailableVideoZoomFactor
            let maxZoom = min(device.maxAvailableVideoZoomFactor, 10.0)
            let clamped = max(minZoom, min(zoom, maxZoom))
            applied = clamped

            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch { }
        }

        return applied
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high
        let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
        guard
            let device = discovery.devices.first,
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        session.commitConfiguration()
        self.videoDevice = device 
    }
}
