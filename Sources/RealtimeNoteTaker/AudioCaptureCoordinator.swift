@preconcurrency import ScreenCaptureKit
import Foundation

enum AudioCaptureError: LocalizedError {
    case sourceApplicationNotFound(String)
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .sourceApplicationNotFound(let target): return "システム音声の取得対象が見つかりません: \(target)"
        case .displayNotFound: return "音声取得に使用するディスプレイが見つかりません。"
        }
    }
}

final class AudioCaptureCoordinator: @unchecked Sendable {
    private let microphone = MicrophoneCaptureService()
    private let systemAudio = SystemAudioCaptureService()

    func start(
        configuration: MeetingConfiguration,
        onChunk: @escaping @Sendable (Data, TranscriptSource, Date) -> Void
    ) async throws {
        if configuration.mode.requiresMicrophone {
            let source: TranscriptSource = configuration.mode == .online ? .selfMicrophone : .roomMicrophone
            try microphone.start { data, date in onChunk(data, source, date) }
        }
        guard configuration.mode.requiresSystemAudio else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw AudioCaptureError.displayNotFound }
        let query = captureTargetQuery(configuration).lowercased()
        guard let app = content.applications.first(where: {
            $0.applicationName.lowercased().contains(query) || $0.bundleIdentifier.lowercased().contains(query)
        }) else { throw AudioCaptureError.sourceApplicationNotFound(captureTargetQuery(configuration)) }
        let source: TranscriptSource = configuration.mode == .video ? .videoSystem : .remoteSystem
        try await systemAudio.start(display: display, including: app, allApplications: content.applications) { data, date in
            onChunk(data, source, date)
        }
    }

    func stop() async {
        microphone.stop()
        try? await systemAudio.stop()
    }

    private func captureTargetQuery(_ configuration: MeetingConfiguration) -> String {
        configuration.meetingApp.captureQuery
    }
}
