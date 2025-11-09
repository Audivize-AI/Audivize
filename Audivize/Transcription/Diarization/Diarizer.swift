import Foundation
import AVFoundation
import FluidAudio

/// A streaming diarizer using a rolling buffer of approximately `chunkDuration` seconds.
/// Timestamps in output segments are offset by `streamStartTime`.
class Diarizer: @unchecked Sendable {
    /// Number of updates per second (integer). Determines hop interval.
    let updatesPerSecond: Int
    /// Duration of the rolling buffer in seconds (e.g., 3s).
    let chunkDuration: TimeInterval
    /// Sampling rate after resampling (16 kHz).
    let sampleRate: Double = 16_000
    /// Mono float32 rolling buffer.
    private var buffer: [Float] = []
    /// When streaming started (wall-clock).
    private let streamStartTime: TimeInterval
    /// Samples count corresponding to chunkDuration.
    private let chunkSize: Int
    /// Hop size in samples (updatesPerSecond).
    private let hopSize: Int
    /// A diarizer manager (FluidAudio) instance.
    private let diarizer: DiarizerManager
    
    init(atTime time: TimeInterval, updatesPerSecond: Int, chunkDuration: TimeInterval = 3.0) async throws {
        self.updatesPerSecond = updatesPerSecond
        self.chunkDuration = chunkDuration
        self.streamStartTime = time
        
        // compute chunk size & hop size
        self.chunkSize = Int(sampleRate * chunkDuration)
        self.hopSize = Int(sampleRate / Double(updatesPerSecond))
        
        // reserve buffer capacity
        self.buffer.reserveCapacity(chunkSize + hopSize)
        
        // initialize diarizer
        let models = try await DiarizerModels.downloadIfNeeded()
        let config = DiarizerConfig(
            clusteringThreshold: 0.7,
            minSpeechDuration: 1.0,
            minEmbeddingUpdateDuration: 1.5,
            minSilenceGap: 0.3
        )
        let manager = DiarizerManager(config: config)
        manager.initialize(models: models)
        manager.speakerManager.speakerThreshold = 0.6
        manager.speakerManager.embeddingThreshold = 0.45
        
        self.diarizer = manager
    }
    
    /// Process a CMSampleBuffer chunk from the microphone.
    /// Call this each time you receive audio input.
    func process(sampleBuffer: CMSampleBuffer) {
        // Convert incoming buffer to Float32 mono at 16kHz
        let newSamples: [Float] = ASD.resampleAudioToFloat32(from: sampleBuffer, to: sampleRate)
        
        // Append to the rolling buffer
        buffer.append(contentsOf: newSamples)
        let sampleRate = Double(newSamples.count) / sampleBuffer.duration.seconds
        
        // If buffer longer than chunkSize + hopSize, drop older samples
        if buffer.count > chunkSize + hopSize {
            let extra = buffer.count - (chunkSize + hopSize)
            buffer.removeFirst(extra)
            print("WARNING: overflow")
        }
        
        // If enough samples to do a chunk
        if buffer.count >= chunkSize {
            // Take the last chunkSize samples
            let chunk = buffer.suffix(chunkSize)
            
            // Compute the start time for this chunk relative to stream start
            let time = sampleBuffer.presentationTimeStamp.seconds - self.streamStartTime
            let chunkStartSec = time - TimeInterval(chunkSize) / TimeInterval(sampleRate)
            
            // Perform diarization for this chunk
            do {
                let result = try diarizer.performCompleteDiarization(chunk, sampleRate: Int(sampleRate.rounded()))
                // Adjust timestamps by chunkStartSec
                for segment in result.segments {
                    let absoluteStart = chunkStartSec + TimeInterval(segment.startTimeSeconds)
                    let absoluteEnd   = chunkStartSec + TimeInterval(segment.endTimeSeconds)
                    // Deliver results (you must define how to handle them)
                    let (speaker, distance) = SpeakerUtilities.findClosestSpeaker(embedding: segment.embedding, candidates: [Speaker](diarizer.speakerManager.getAllSpeakers().values))

                    var id = segment.speakerId
                    print("distance:", distance)
                    if let speaker, distance < diarizer.speakerManager.embeddingThreshold {
                        id = speaker.id
                    } else {
                        id = "\(diarizer.speakerManager.speakerCount+1)"
                        diarizer.speakerManager.upsertSpeaker(id: id, currentEmbedding: segment.embedding, duration: segment.durationSeconds)
                    }

                    handleSpeakerSegment(speakerId: id,
                                         startSec: absoluteStart,
                                         endSec: absoluteEnd)
//                    print("id:", id, "embedding:", segment.embedding)
                }
            } catch {
                // Handle error
                print("Diarization error: \(error)")
            }
            
            // Remove the first hopSize samples from buffer (so next chunk moves forward)
            buffer.removeFirst(buffer.count - chunkSize + hopSize)
        }
    }
    
    /// Callback/handler for each speaker segment produced.
    /// You should implement this to integrate with your downstream logic.
    func handleSpeakerSegment(speakerId: String, startSec: TimeInterval, endSec: TimeInterval) {
//        print("Speaker \(speakerId): \(String(format: "%.3f", startSec)) – \(String(format: "%.3f", endSec))s")
    }
}
