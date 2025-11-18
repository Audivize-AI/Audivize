// Code originally from FluidInference Swift Scribe: https://github.com/FluidInference/swift-scribe

import Foundation
import Speech
import SwiftUI


final class SpokenWordTranscriber: @unchecked Sendable {
    private let inputSequence: AsyncStream<AnalyzerInput>
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), any Error>?
    private var newText: [(text: AttributedString, time: CMTimeRange)] = []

    // The format of the audio.
    var analyzerFormat: AVAudioFormat?

    let converter = BufferConverter()
    var downloadProgress: Progress?

    var volatileTranscript: AttributedString = ""
    var finalizedTranscript: AttributedString = ""
    
    var updates: [(text: AttributedString, time: CMTimeRange)] {
        get {
            let results = self.newText
            self.newText.removeAll()
            return results
        }
    }

    static let locale = Locale(
        components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates))

    init() {
        print(
            "[Transcriber DEBUG]: Initializing SpokenWordTranscriber with locale: \(SpokenWordTranscriber.locale.identifier)"
        )
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = stream
        self.inputBuilder = continuation
    }

    func setUpTranscriber() async throws {
        print("[Transcriber DEBUG]: Starting transcriber setup...")

        transcriber = SpeechTranscriber(
            locale: SpokenWordTranscriber.locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence])

        guard let transcriber else {
            print("[Transcriber DEBUG]: ERROR - Failed to create SpeechTranscriber")
            throw TranscriptionError.failedToSetupRecognitionStream
        }
        print("[Transcriber DEBUG]: SpeechTranscriber created successfully")

        analyzer = SpeechAnalyzer(modules: [transcriber])
        print("[Transcriber DEBUG]: SpeechAnalyzer created with transcriber module")

        do {
            print("[Transcriber DEBUG]: Ensuring model is available...")
            try await ensureModel(transcriber: transcriber, locale: SpokenWordTranscriber.locale)
            print("[Transcriber DEBUG]: Model check completed successfully")
        } catch let error as TranscriptionError {
            print("[Transcriber DEBUG]: Model setup failed with error: \(error.descriptionString)")
            return
        }

        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [
            transcriber
        ])
        print("[Transcriber DEBUG]: Best audio format: \(String(describing: analyzerFormat))")

        recognizerTask = Task {
            print("[Transcriber DEBUG]: Starting recognition task...")
            do {
                print("[Transcriber DEBUG]: About to start listening for transcription results...")
                var resultCount = 0
                for try await case let result in transcriber.results {
                    resultCount += 1
                    let text = result.text
                    if result.isFinal {
                        finalizedTranscript += text
                        volatileTranscript = ""
                    } else {
                        volatileTranscript = text
                        volatileTranscript.font = volatileTranscript.font?.italic()
                    }
//                    self.newText += text
                    
                }
                print(
                    "[Transcriber DEBUG]: Recognition task completed normally after \(resultCount) results"
                )
            } catch {
                print(
                    "[Transcriber DEBUG]: ERROR - Speech recognition failed: \(error.localizedDescription)"
                )
            }
        }

        do {
            try await analyzer?.start(inputSequence: inputSequence)
            print("[Transcriber DEBUG]: SpeechAnalyzer started successfully")
        } catch {
            print(
                "[Transcriber DEBUG]: ERROR - Failed to start SpeechAnalyzer: \(error.localizedDescription)"
            )
            throw error
        }
    }

    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let analyzerFormat else {
            print("[Transcriber DEBUG]: ERROR - No analyzer format available")
            throw TranscriptionError.invalidAudioDataType
        }

        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)

        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }

    public func finishTranscribing() async throws {
        print("[Transcriber DEBUG]: Finishing transcription...")
        inputBuilder.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        print("[Transcriber DEBUG]: Transcription finished and cleaned up")
    }

    /// Reset the transcriber for a new recording session
    /// This clears existing transcripts when restarting recording
    public func reset() {
        print("[Transcriber DEBUG]: Resetting transcriber - clearing transcripts")
        volatileTranscript = ""
        finalizedTranscript = ""
    }
}

extension SpokenWordTranscriber {
    public func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        print("[Transcriber DEBUG]: Checking model availability for locale: \(locale.identifier)")

        guard await supported(locale: locale) else {
            print("[Transcriber DEBUG]: ERROR - Locale not supported: \(locale.identifier)")
            throw TranscriptionError.localeNotSupported
        }
        print("[Transcriber DEBUG]: Locale is supported: \(locale.identifier)")

        if await installed(locale: locale) {
            print("[Transcriber DEBUG]: Model already installed for locale: \(locale.identifier)")
        } else {
            print("[Transcriber DEBUG]: Model not installed, attempting download...")
            try await downloadIfNeeded(for: transcriber)
        }

        // Always ensure locale is allocated after installation/download
        try await allocateLocale(locale: SpokenWordTranscriber.locale)
    }

    func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        let isSupported = supported.map { $0.identifier(.bcp47) }.contains(
            locale.identifier(.bcp47))
        print(
            "[Transcriber DEBUG]: Supported locales check - locale: \(locale.identifier), supported: \(isSupported)"
        )
        print(
            "[Transcriber DEBUG]: All supported locales: \(supported.map { $0.identifier(.bcp47) })"
        )
        return isSupported
    }

    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        let isInstalled = installed.map { $0.identifier(.bcp47) }.contains(
            locale.identifier(.bcp47))
        print(
            "[Transcriber DEBUG]: Installed locales check - locale: \(locale.identifier), installed: \(isInstalled)"
        )
        print(
            "[Transcriber DEBUG]: All installed locales: \(installed.map { $0.identifier(.bcp47) })"
        )
        return isInstalled
    }

    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        print("[Transcriber DEBUG]: Checking if download is needed...")
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module])
        {
            print("[Transcriber DEBUG]: Download required, starting asset installation...")
            self.downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
            print("[Transcriber DEBUG]: Asset download and installation completed")
        } else {
            print("[Transcriber DEBUG]: No download needed")
        }
    }

    func allocateLocale(locale: Locale) async throws {
        print("[Transcriber DEBUG]: Checking if locale is already allocated: \(locale.identifier)")
        let allocated = await AssetInventory.reservedLocales
        print(
            "[Transcriber DEBUG]: Currently allocated locales: \(allocated.map { $0.identifier })")

        if allocated.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            print("[Transcriber DEBUG]: Locale already allocated: \(locale.identifier)")
            return
        }

        print("[Transcriber DEBUG]: Allocating locale: \(locale.identifier)")
        try await AssetInventory.reserve(locale: locale)
        print("[Transcriber DEBUG]: Locale allocated successfully: \(locale.identifier)")
    }

    func deallocate() async {
        print("[Transcriber DEBUG]: Deallocating locales...")
        let allocated = await AssetInventory.reservedLocales
        print("[Transcriber DEBUG]: Allocated locales: \(allocated.map { $0.identifier })")
        for locale in allocated {
            await AssetInventory.release(reservedLocale: locale)
        }
        print("[Transcriber DEBUG]: Deallocation completed")
    }
}
