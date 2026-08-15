import AVFoundation
import Foundation

final class MicrophoneCaptureService {
    private let engine = AVAudioEngine()
    private var isRunning = false

    func start(onChunk: @escaping @Sendable (Data, Date) -> Void) throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let accumulator = AudioChunkAccumulator(format: format)

        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            do {
                if let wav = try accumulator.append(buffer) {
                    onChunk(wav, Date())
                }
            } catch {
                // Audio formats can change when an external device disconnects.
                // The session coordinator observes device changes and warns the user.
            }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}
