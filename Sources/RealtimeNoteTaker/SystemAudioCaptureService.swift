@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
import Foundation

/// Captures system audio from a selected display while excluding every application except the selected one.
/// The actual source is always confirmed by the user in the macOS content picker before capture starts.
final class SystemAudioCaptureService: NSObject, SCStreamOutput, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.aoiseki.RealtimeNoteTaker.systemAudio")
    private var stream: SCStream?
    private var accumulator: AudioChunkAccumulator?
    private var onChunk: ((Data, Date) -> Void)?

    static func runningApplications() async throws -> [SCRunningApplication] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.applications
    }

    func start(
        display: SCDisplay,
        including application: SCRunningApplication,
        allApplications: [SCRunningApplication],
        onChunk: @escaping (Data, Date) -> Void
    ) async throws {
        let excluded = allApplications.filter { $0.bundleIdentifier != application.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 24_000
        configuration.channelCount = 1

        self.onChunk = onChunk
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await newStream.startCapture()
        stream = newStream
    }

    func stop() async throws {
        guard let stream else { return }
        try await stream.stopCapture()
        self.stream = nil
        accumulator = nil
        onChunk = nil
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                      let format = AVAudioFormat(standardFormatWithSampleRate: description.mSampleRate, channels: description.mChannelsPerFrame),
                      let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer) else {
                    return
                }
                if accumulator == nil { accumulator = AudioChunkAccumulator(format: format) }
                if let wav = try accumulator?.append(pcmBuffer) {
                    onChunk?(wav, Date())
                }
            }
        } catch {
            // Device and stream errors are surfaced by the coordinator at the next start/retry.
        }
    }
}
