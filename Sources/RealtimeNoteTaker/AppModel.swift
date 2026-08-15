import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var configuration = MeetingConfiguration()
    var activeSession: MeetingSession?
    var isCapturing = false
    var lastError: String?
    var pendingDeletionSession: MeetingSession?
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshAt = Date()
    var hasOpenAIAPIKey: Bool { OpenAISettings.hasAPIKey }

    func saveOpenAIAPIKey(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "OpenAI APIキーを入力してください。"
            return
        }
        do {
            try OpenAISettings.saveAPIKey(value.trimmingCharacters(in: .whitespacesAndNewlines))
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startMeeting() {
        guard !configuration.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "会議名を入力してください。"
            return
        }
        guard configuration.hasConfirmedConsent else {
            lastError = "録音・文字起こしおよびOpenAI APIへの送信について確認してください。"
            return
        }
        guard hasOpenAIAPIKey else {
            lastError = "開始前にOpenAI APIキーをKeychainへ登録してください。"
            return
        }
        let session = MeetingSession(configuration: configuration)
        do {
            try EncryptedSessionStore.save(session)
            activeSession = session
            isCapturing = true
            lastRefreshAt = Date()
            scheduleRefreshLoop()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func appendDemoSegment() {
        guard var session = activeSession else { return }
        let source: TranscriptSource = switch session.configuration.mode {
        case .inPerson: .roomMicrophone
        case .online: .remoteSystem
        case .video: .videoSystem
        }
        let segment = TranscriptSegment(
            startedAt: Date(),
            endedAt: Date(),
            source: source,
            speaker: source == .roomMicrophone ? "話者A" : source.rawValue,
            text: "文字起こしサービスから受け取った発話がここに表示されます。",
            isImportant: true
        )
        session.temporaryTranscript.append(segment)
        session.importantSegments.append(segment)
        activeSession = session
        persist(session)
    }

    func ingestTranscription(_ segments: [OpenAIDiarizedSegment], source: TranscriptSource, chunkEndedAt: Date) {
        guard var session = activeSession else { return }
        let chunkStartedAt = chunkEndedAt.addingTimeInterval(-4)
        for item in segments {
            session.temporaryTranscript.append(TranscriptSegment(
                startedAt: chunkStartedAt.addingTimeInterval(item.start),
                endedAt: chunkStartedAt.addingTimeInterval(item.end),
                source: source,
                speaker: speakerLabel(source: source, diarizedLabel: item.speaker),
                text: item.text,
                isImportant: false
            ))
        }
        activeSession = session
        persist(session)
    }

    func updateSection(_ section: String, text: String) {
        guard var session = activeSession else { return }
        session.structuredMinutes.sections[section] = text
        activeSession = session
        persist(session)
    }

    func finishMeeting() {
        guard var session = activeSession else { return }
        refreshTask?.cancel()
        session.endedAt = Date()
        isCapturing = false
        do {
            let url = try MinutesExporter.writeMarkdown(for: session)
            do {
                try GitRepositoryService.commitAndPush(
                    repositoryPath: session.configuration.repositoryPath,
                    fileURL: url,
                    title: session.configuration.title
                )
                session.hasBeenPushed = true
            } catch {
                lastError = "議事録はローカルへ保存しましたが、GitHubへの自動保存は失敗しました。後で再送できます。\n\(error.localizedDescription)"
            }
            activeSession = session
            persist(session)
            pendingDeletionSession = session
        } catch {
            lastError = error.localizedDescription
        }
    }

    func handleTemporaryTranscriptDeletion(delete: Bool) {
        guard let session = pendingDeletionSession else { return }
        if delete {
            do {
                try EncryptedSessionStore.delete(session)
                EncryptedSessionStore.destroyTemporaryTranscriptKey()
                activeSession = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
        pendingDeletionSession = nil
    }

    private func persist(_ session: MeetingSession) {
        do { try EncryptedSessionStore.save(session) }
        catch { lastError = error.localizedDescription }
    }

    private func scheduleRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await self?.refreshMinutes()
            }
        }
    }

    private func refreshMinutes() async {
        guard var session = activeSession, isCapturing else { return }
        let newSegments = session.temporaryTranscript.filter { $0.endedAt > lastRefreshAt }
        guard !newSegments.isEmpty else { return }
        do {
            let update = try await MinutesRefreshService().refresh(recentSegments: newSegments, current: session.structuredMinutes)
            session.importantSegments.append(contentsOf: newSegments.map { segment in
                var copy = segment
                copy.isImportant = update.importantIDs.contains(segment.id)
                return copy
            }.filter(\.isImportant))
            for (section, text) in update.updatedSections { session.structuredMinutes.sections[section] = text }
            lastRefreshAt = Date()
            activeSession = session
            persist(session)
        } catch {
            lastError = "議事録の30秒更新に失敗しました。次回の更新で再試行します。\n\(error.localizedDescription)"
        }
    }

    private func speakerLabel(source: TranscriptSource, diarizedLabel: String) -> String {
        switch source {
        case .selfMicrophone: "自分"
        case .roomMicrophone: "話者\(diarizedLabel)"
        case .remoteSystem: "相手\(diarizedLabel)"
        case .videoSystem: "動画\(diarizedLabel)"
        }
    }
}
