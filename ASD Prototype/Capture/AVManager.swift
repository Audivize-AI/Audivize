// =================================================================
// FILE 1: CameraManager.swift
// Create a new Swift file and name it CameraManager.swift
// =================================================================
// This class is the heart of our app. It handles setting up the camera,
// processing video frames, and running the Core ML model via Vision.
// IMPORTANT: This class has no knowledge of the UI. It only deals with
// camera data and provides normalized results (coordinates from 0.0 to 1.0).

@preconcurrency import AVFoundation
@preconcurrency import Vision
import UIKit
import SwiftUI


class AVManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    // This allows the CameraPreview vbut hiew to reactively update when the session is ready.
    @Published var captureSession: AVCaptureSession?
    
    // Published properties to update the SwiftUI view
    @Published public private(set) var detections: [ASD.SendableSpeaker] = []
    
    // AVFoundation properties
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoCaptureDevice: AVCaptureDevice?
    private var audioCaptureDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "com.facedetector.sessionQueue")
    
    // Vision and Core ML properties
    private var asd: ASD.ASD?
        
    override init() {
        super.init()
        // Asynchronously check permissions and then set up the session
        sessionQueue.async {
            self.checkPermissionsAndSetup()
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        do {
            try self.asd?.update(
                videoSample: sampleBuffer,
                cameraPosition: self.videoCaptureDevice?.position ?? .unspecified,
                connection: connection
            )
        } catch {
            print("Video Error: \(error)")
        }
//        if output is AVCaptureVideoDataOutput {
//        } else {
//            self.asd?.updateAudio(audioSample: sampleBuffer)
//        }
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
    
    // MARK: - AVFoundation Camera Setup
    
    private func checkPermissionsAndSetup() {
        switch (AVCaptureDevice.authorizationStatus(for: .video), AVCaptureDevice.authorizationStatus(for: .audio)) {
        case (.authorized, .authorized):
            self.setupCaptureSession()
        case (.notDetermined, .authorized):
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupCaptureSession()
                } else {
                    print("Camera access was denied.")
                }
            }
        case (.authorized, .notDetermined):
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    self?.setupCaptureSession()
                } else {
                    print("Microphone access was denied.")
                }
            }
        case (.notDetermined, .notDetermined):
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                        if granted {
                            self?.setupCaptureSession()
                        } else {
                            print("Microphone access was denied.")
                        }
                    }
                } else {
                    print("Camera access was denied.")
                }
            }
        default:
            print("Camera and/or Microphone access is restricted or denied.")
        }
    }
    
    private func setupCaptureSession() {
        print("Setting up capture session...")
        // This method should only be called from the sessionQueue
        
        let session = AVCaptureSession()
        session.sessionPreset = Global.videoPreset
        
        self.setupCamera(for: session)
        //self.setupMicrophone(for: session)
        
        let currentTime = CMClockGetTime(session.synchronizationClock!).seconds
        self.asd = .init(
            atTime: currentTime,
            videoSize: Global.videoSize,
            cameraAngle: 0
        ) { speakers in
            Task.detached { @MainActor in
                self.detections = speakers
            }
        }
        
        session.startRunning()
        
        // Publish the now-running session to the main thread.
        
        Task { @MainActor in
            self.captureSession = session
        }
    }
    
    private func setupCamera(for session: AVCaptureSession) {
        self.videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        
        guard let videoCaptureDevice = self.videoCaptureDevice else {
            print("Error: No back camera found.")
            return
        }
        
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
            // Use the new API on iOS 17 and later
            if #available(iOS 17.0, *) {
                // To set portrait orientation, we check for and set a 90-degree rotation.
                if connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
            } else {
                // Fallback for earlier iOS versions
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .landscapeLeft
                }
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
