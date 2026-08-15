import Foundation

enum MeetingMode: String, CaseIterable, Codable, Identifiable {
    case inPerson = "対面会議"
    case online = "オンライン会議"
    case video = "動画視聴"

    var id: String { rawValue }
    var requiresMicrophone: Bool { self != .video }
    var requiresSystemAudio: Bool { self != .inPerson }
}

enum MeetingApp: String, CaseIterable, Codable, Identifiable {
    case zoom = "Zoom"
    case teams = "Microsoft Teams"
    case googleChrome = "Google Chrome"

    var id: String { rawValue }

    var captureQuery: String {
        switch self {
        case .zoom: "zoom"
        case .teams: "teams"
        case .googleChrome: "google chrome"
        }
    }
}

enum AudioDeviceMode: String, CaseIterable, Codable, Identifiable {
    case builtIn = "MacBook Air（内蔵）"
    case earphones = "イヤホン"

    var id: String { rawValue }
}

enum MinutesTemplate: String, CaseIterable, Codable, Identifiable {
    case research = "研究・プロジェクト進捗"
    case groupDiscussion = "GD用"
    case lecture = "動画視聴・講義メモ"

    var id: String { rawValue }

    var sections: [String] {
        switch self {
        case .research:
            ["会議の目的", "主な議論", "決定事項", "ToDo", "未解決事項・次回確認"]
        case .groupDiscussion:
            ["議論のタイトル", "時間配分", "前提確認", "現状分析", "問題特定（whatの特定）", "原因・真因分析（whyの深掘り）", "施策議論・決定", "まとめ（発表用）", "その他"]
        case .lecture:
            ["内容の要約", "重要な論点・知見", "キーワード", "今後確認したいこと"]
        }
    }
}

struct MeetingConfiguration: Codable, Equatable {
    var title = ""
    var mode: MeetingMode = .inPerson
    var otherParticipantCount = 1
    var microphoneDeviceMode: AudioDeviceMode = .builtIn
    var speakerDeviceMode: AudioDeviceMode = .builtIn
    var meetingApp: MeetingApp = .zoom
    var template: MinutesTemplate = .research
    var hasConfirmedConsent = false
    var repositoryPath = NSString(string: "~/GitHub/Realtime_NoteTaker").expandingTildeInPath
}

enum TranscriptSource: String, Codable {
    case selfMicrophone = "自分"
    case roomMicrophone = "会議室"
    case remoteSystem = "相手側"
    case videoSystem = "動画音声"
}

struct TranscriptSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date
    var source: TranscriptSource
    var speaker: String
    var text: String
    var isImportant: Bool
}

struct StructuredMinutes: Codable, Equatable {
    var template: MinutesTemplate
    var sections: [String: String]

    init(template: MinutesTemplate) {
        self.template = template
        self.sections = Dictionary(uniqueKeysWithValues: template.sections.map { ($0, "") })
    }
}

struct MeetingSession: Codable, Identifiable {
    var id = UUID()
    var configuration: MeetingConfiguration
    var startedAt = Date()
    var endedAt: Date?
    var temporaryTranscript: [TranscriptSegment] = []
    var importantSegments: [TranscriptSegment] = []
    var structuredMinutes: StructuredMinutes
    var hasBeenPushed = false

    init(configuration: MeetingConfiguration) {
        self.configuration = configuration
        self.structuredMinutes = StructuredMinutes(template: configuration.template)
    }
}
