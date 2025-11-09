@preconcurrency import AVFoundation
@preconcurrency import Vision
import UIKit
import SwiftUI


class AVManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    
    // This allows the CameraPreview vbut hiew to reactively update when the session is ready.
    @Published var captureSession: AVCaptureSession?
    
    // Published properties to update the SwiftUI view
    @Published public private(set) var detections: [ASD.SendableSpeaker] = []
    @Published public private(set) var previewLayer: AVCaptureVideoPreviewLayer
    
    // AVFoundation properties
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoCaptureDevice: AVCaptureDevice?
    private var audioCaptureDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "com.facedetector.sessionQueue")
    
    // Vision and Core ML properties
    private var asd: ASD.ASD?
    private var diarizer: Diarizer?
        
    init(cameraAngle: CGFloat = 0.0) {
        self.previewLayer = .init()
        super.init()
        // Asynchronously check permissions and then set up the session
        sessionQueue.async {
            self.setupCaptureSession(cameraAngle: cameraAngle)
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            do {
//                print("video")
                try self.asd?.update(
                    videoSample: sampleBuffer,
                    cameraPosition: self.videoCaptureDevice?.position ?? .unspecified,
                    connection: connection
                )
            } catch {
                print("Video Error: \(error)")
            }
        } else {
            self.diarizer?.process(sampleBuffer: sampleBuffer)
        }
    }
    
    // Public methods to control session from the UI. These are useful for app lifecycle events.
    func startSession() {
        sessionQueue.async {
            if self.captureSession?.isRunning == false {
                self.captureSession?.startRunning()
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            if self.captureSession?.isRunning == true {
                self.captureSession?.stopRunning()
            }
        }
    }
    
    func updateVideoOrientation(for orientation: UIInterfaceOrientation) {
        let angle: CGFloat
        
        switch orientation {
        case .landscapeRight:
            angle = 180
        case .landscapeLeft:
            angle = 0
        default:
            fatalError("Unsupported orientation: \(orientation). \(String(describing: orientation))")
        }
        
        sessionQueue.async {
            guard let connection = self.videoOutput.connection(with: .video) else { return }

            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
        
        Task { @MainActor in
            self.previewLayer.connection?.videoRotationAngle = angle
        }
    }
    
    // MARK: - AVFoundation Camera Setup
    
    private func setupCaptureSession(cameraAngle: CGFloat) {
        print("Setting up capture session...")
        // This method should only be called from the sessionQueue
        
        let session = AVCaptureSession()
        session.sessionPreset = CaptureConfiguration.videoPreset
        
        // Set up camera
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.setupCamera(for: session, cameraAngle: cameraAngle)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupCamera(for: session, cameraAngle: cameraAngle)
                } else {
                    print("Camera access was denied.")
                }
            }
        default: break
        }
        
        // set up microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            self.setupMicrophone(for: session)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupMicrophone(for: session)
                } else {
                    print("Microphone access was denied.")
                }
            }
        default: break
        }
        
        let currentTime = CMClockGetTime(session.synchronizationClock!).seconds
        self.asd = .init(
            atTime: currentTime,
            videoSize: CaptureConfiguration.videoSize,
            cameraAngle: cameraAngle,
            onTrackComplete: { speakers in
                Task.detached { @MainActor in
                    self.detections = speakers
                }
            }
        )
        
        session.startRunning()
        
        // Publish the now-running session to the main thread.
        
        Task { @MainActor in
            do {
                self.diarizer = try await Diarizer(atTime: currentTime, updatesPerSecond: 3)
            } catch {
                print("Failed to initialize the diarizer: \(error)")
            }
            self.captureSession = session
            self.previewLayer.session = session
            self.previewLayer.videoGravity = .resizeAspect
            self.previewLayer.connection?.videoRotationAngle = cameraAngle
        }
    }
    
    private func setupCamera(for session: AVCaptureSession, cameraAngle: CGFloat) {
        if let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            self.videoCaptureDevice = videoCaptureDevice
            do {
                try videoCaptureDevice.lockForConfiguration()
                if videoCaptureDevice.isRampingVideoZoom {
                    videoCaptureDevice.cancelVideoZoomRamp()
                }
                // Set to the widest field of view available for this camera.
                videoCaptureDevice.videoZoomFactor = videoCaptureDevice.minAvailableVideoZoomFactor
                videoCaptureDevice.unlockForConfiguration()
                print("Zoom: \(videoCaptureDevice.minAvailableVideoZoomFactor)")
            } catch {
                print("Could not lock camera for configuration: \(error)")
            }
        }
        
        guard let videoCaptureDevice else {
            print("Error: No back camera found.")
            return
        }
        
//        try? videoCaptureDevice.lockForConfiguration()
//        videoCaptureDevice.activeFormat = CaptureConfiguration.frontCameraMaxFormat!
//        videoCaptureDevice.unlockForConfiguration()
        
        do {
            let input = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Error setting up camera input: \(error)")
            return
        }
        
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            print("Error: Could not add video output.")
            return
        }
        
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(cameraAngle) {
                connection.videoRotationAngle = cameraAngle
            } else {
                connection.videoRotationAngle = 0
            }
        }
    }
    
    private func setupMicrophone(for session: AVCaptureSession) {
        self.audioCaptureDevice = AVCaptureDevice.default(for: .audio)
        
        guard let audioCaptureDevice = self.audioCaptureDevice else {
            print("Error: No microphone found.")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: audioCaptureDevice)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Error setting up microphone input: \(error)")
            return
        }
        
        audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        } else {
            print("Error: Could not add audio output.")
            return
        }
    }
}
