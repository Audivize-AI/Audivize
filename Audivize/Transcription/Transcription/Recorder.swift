// Code originally from FluidInference Swift Scribe: https://github.com/FluidInference/swift-scribe

import AVFoundation
import Foundation
import SwiftUI

class Recorder {
    private var outputContinuation: AsyncStream<AudioData>.Continuation?
    
    // Separate engines for recording and playback to avoid conflicts
    private let recordingEngine: AVAudioEngine
    private let transcriber: SpokenWordTranscriber
    
    init(transcriber: SpokenWordTranscriber) {
        self.recordingEngine = AVAudioEngine()
        self.transcriber = transcriber
    }
    
    func record() async throws {
        print("DEBUG [Recorder]: Starting recording session")
        guard await isAuthorized() else {
            print("DEBUG [Recorder]: Recording authorization failed")
            throw TranscriptionError.failedToSetupRecognitionStream
        }
        
        // Set up audio session for both iOS and macOS
        do {
            try setUpAudioSession()
            print("DEBUG [Recorder]: Audio session setup completed")
        } catch {
            print("DEBUG [Recorder]: Audio session setup failed: \(error)")
            throw error
        }
        
        do {
            try await transcriber.setUpTranscriber()
            print("DEBUG [Recorder]: Transcriber setup completed")
        } catch {
            print("DEBUG [Recorder]: Transcriber setup failed: \(error)")
            throw error
        }
        
        print("DEBUG [Recorder]: Audio session and transcriber set up successfully")
        
        // Create audio stream and process it
        do {
            let audioStreamSequence = try await audioStream()
            for await audioData in audioStreamSequence {
                // Process the buffer for transcription
                try await self.transcriber.streamAudioToTranscriber(audioData.buffer)
            }
        } catch {
            print("DEBUG [Recorder]: Audio streaming failed: \(error)")
            throw error
        }
    }
    
    func stopRecording() async throws {
        print("DEBUG [Recorder]: Stopping recording session")
        
        // Stop the recording engine if it's running
        if recordingEngine.isRunning {
            recordingEngine.stop()
            print("DEBUG [Recorder]: Recording engine stopped")
        }
        
        // Remove tap safely
        recordingEngine.inputNode.removeTap(onBus: 0)
        
        // Clean up continuation
        outputContinuation?.finish()
        outputContinuation = nil
        print("DEBUG [Recorder]: Audio stream continuation finished")
        
        do {
            try await transcriber.finishTranscribing()
            print("DEBUG [Recorder]: Transcription finalized")
        } catch {
            print("DEBUG [Recorder]: Error finalizing transcription: \(error)")
            throw error
        }
        
        print("DEBUG [Recorder]: Recording stopped and transcription finalized")
    }
    
    func pauseRecording() {
        print("DEBUG [Recorder]: Pausing recording")
        recordingEngine.pause()
    }
    
    func resumeRecording() throws {
        print("DEBUG [Recorder]: Resuming recording")
        try recordingEngine.start()
    }
    
#if os(iOS)
    func setUpAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
#else
    // macOS audio session setup
    func setUpAudioSession() throws {
        print("DEBUG [Recorder]: Setting up macOS audio session")
        
        // Reset recording engine if needed
        if recordingEngine.isRunning {
            print("DEBUG [Recorder]: Stopping recording engine for reset")
            recordingEngine.stop()
        }
        recordingEngine.reset()
        
        // Request microphone access
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("DEBUG [Recorder]: Audio access already authorized")
        case .notDetermined:
            print("DEBUG [Recorder]: Audio access not determined, requesting...")
            // This will be handled by the isAuthorized() check in record()
        case .denied, .restricted:
            print("DEBUG [Recorder]: Audio access denied or restricted")
            throw TranscriptionError.failedToSetupRecognitionStream
        @unknown default:
            print("DEBUG [Recorder]: Unknown audio authorization status")
            throw TranscriptionError.failedToSetupRecognitionStream
        }
    }
#endif
    
    private func audioStream() async throws -> AsyncStream<AudioData> {
        try setupRecordingEngine()
        
        recordingEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: recordingEngine.inputNode.outputFormat(forBus: 0)
        ) { [weak self] (buffer, time) in
            guard let self else { return }
            // Wrap in AudioData to make it Sendable for Swift 6
            let audioData = AudioData(buffer: buffer, time: time)
            self.outputContinuation?.yield(audioData)
        }
        
        recordingEngine.prepare()
        try recordingEngine.start()
        print("DEBUG [Recorder]: Recording engine started successfully")
        
        return AsyncStream(AudioData.self, bufferingPolicy: .unbounded) { continuation in
            self.outputContinuation = continuation
        }
    }
    
    private func setupRecordingEngine() throws {
        print("DEBUG [Recorder]: Setting up recording engine")
        
        // Stop and reset if already running
        if recordingEngine.isRunning {
            print("DEBUG [Recorder]: Stopping existing recording engine")
            recordingEngine.stop()
        }
        
        // Remove any existing taps first
        recordingEngine.inputNode.removeTap(onBus: 0)
        
        // Reset the engine to clean state
        recordingEngine.reset()
        
        let inputFormat = recordingEngine.inputNode.outputFormat(forBus: 0)
        print("DEBUG [Recorder]: Input format: \(inputFormat)")
    }
}
