//
//  Transcriber.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/8/25.
//

import Foundation
import AVFoundation
import Speech
import FluidAudio


public class Transcriber {
    
    // Simple macOS CLI tool demonstrating streaming transcription with punctuation and timestamps.
    // Ensure Terminal has Microphone & Speech Recognition permission:
    // System Settings → Privacy & Security → Microphone & Speech Recognition
    
    
    
    enum AuthStatusError: Error { case denied, restricted, notDetermined, unavailable }
    
    func requestSpeechAuthorization() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
        print("🔍 Debug: Requesting Speech Recognizer authorization...")
        SFSpeechRecognizer.requestAuthorization { status in
            authStatus = status
            print("🔍 Debug: Authorization status raw: \(status.rawValue)")
            semaphore.signal()
        }
        semaphore.wait()
        switch authStatus {
        case .authorized:
            print("✅ Debug: Authorization granted")
            return
        case .denied:
            print("❌ Debug: Authorization denied")
            throw AuthStatusError.denied
        case .restricted:
            print("❌ Debug: Authorization restricted")
            throw AuthStatusError.restricted
        case .notDetermined:
            print("❌ Debug: Authorization not determined")
            throw AuthStatusError.notDetermined
        @unknown default:
            print("❌ Debug: Authorization unknown")
            throw AuthStatusError.unavailable
        }
    }
    
    func startTranscription() throws {
        print("🔍 Debug: Setting up AVAudioEngine...")
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            print("❌ Debug: Could not create SFSpeechRecognizer")
            fatalError("Speech recognizer unavailable for locale")
        }
        print("🔍 Debug: Recognizer availability: \(recognizer.isAvailable)")
        
        print("⏱️ Starting live transcription... Press CTRL+C to stop.")
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        print("🔍 Debug: Audio engine started")
        
        recognizer.recognitionTask(with: recognitionRequest) { result, error in
            if let error = error {
                print("❌ Transcription error: \(error)")
                exit(1)
            }
            guard let result = result else { return }
            
            // Print the full transcription with punctuation
            let transcript = result.bestTranscription.formattedString
            let lastTimestamp = result.bestTranscription.segments.last?.timestamp ?? 0.0
            let ts = String(format: "%.2f", lastTimestamp)
            print("[At ~\(ts)s] \(transcript)")
            
            if result.isFinal {
                print("🎉 Final transcription reached.")
                audioEngine.stop()
                recognitionRequest.endAudio()
                exit(0)
            }
        }
        
        RunLoop.main.run()
    }
    
    
    
}
