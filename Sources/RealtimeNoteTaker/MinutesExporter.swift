import Foundation

enum MinutesExporter {
    static func writeMarkdown(for session: MeetingSession) throws -> URL {
        let fileManager = FileManager.default
        let repository = URL(fileURLWithPath: session.configuration.repositoryPath, isDirectory: true)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: session.startedAt)
        let directory = repository
            .appendingPathComponent("議事録管理", isDirectory: true)
            .appendingPathComponent(String(format: "%04d", components.year ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", components.month ?? 0), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let filename = "\(formatter.string(from: session.startedAt))_\(safeFilename(session.configuration.title)).md"
        let url = directory.appendingPathComponent(filename)
        try markdown(for: session).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func markdown(for session: MeetingSession) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var output = "# \(session.configuration.title)\n\n"
        output += "- 日時: \(dateFormatter.string(from: session.startedAt))\n"
        output += "- 種別: \(session.configuration.mode.rawValue)\n"
        output += "- 想定参加者: 自分 + \(session.configuration.otherParticipantCount)名\n"
        output += "- テンプレート: \(session.configuration.template.rawValue)\n\n"
        output += "## 構造化したまとめ\n\n"
        for section in session.structuredMinutes.template.sections {
            output += "### \(section)\n\n"
            output += "\(session.structuredMinutes.sections[section, default: "未記入"])\n\n"
        }
        output += "---\n\n## 重要発話ログ\n\n"
        output += "| 時刻 | 話者 | 発話 |\n| --- | --- | --- |\n"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "ja_JP")
        timeFormatter.dateFormat = "HH:mm:ss"
        for segment in session.importantSegments.sorted(by: { $0.startedAt < $1.startedAt }) {
            let text = segment.text.replacingOccurrences(of: "|", with: "\\|")
            output += "| \(timeFormatter.string(from: segment.startedAt)) | \(segment.speaker) | \(text) |\n"
        }
        return output
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "無題の会議" : cleaned
    }
}

enum GitRepositoryService {
    static func commitAndPush(repositoryPath: String, fileURL: URL, title: String) throws {
        let relativePath = fileURL.path.replacingOccurrences(of: URL(fileURLWithPath: repositoryPath).path + "/", with: "")
        try run("/usr/bin/git", ["-C", repositoryPath, "add", relativePath])
        try run("/usr/bin/git", ["-C", repositoryPath, "commit", "-m", "Save minutes: \(title)"])
        try run("/usr/bin/git", ["-C", repositoryPath, "push"])
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "不明なGitエラー"
            throw GitError.commandFailed(message)
        }
    }
}

enum GitError: LocalizedError {
    case commandFailed(String)
    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return "GitHubへの保存に失敗しました: \(message)"
        }
    }
}
