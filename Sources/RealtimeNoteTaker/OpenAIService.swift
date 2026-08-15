import Foundation

enum OpenAISettings {
    private static let apiKeyAccount = "openai-api-key"

    static var hasAPIKey: Bool {
        (try? KeychainStore.load(account: apiKeyAccount)) != nil
    }

    static func saveAPIKey(_ value: String) throws {
        try KeychainStore.save(Data(value.utf8), account: apiKeyAccount)
    }

    static func apiKey() throws -> String {
        guard let data = try KeychainStore.load(account: apiKeyAccount),
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            throw OpenAIServiceError.apiKeyMissing
        }
        return key
    }
}

struct OpenAIDiarizedSegment: Codable {
    let start: Double
    let end: Double
    let speaker: String
    let text: String
}

private struct OpenAITranscriptionResponse: Codable {
    let segments: [OpenAIDiarizedSegment]?
}

/// Sends short WAV chunks to the Audio Transcriptions API. No audio file is written to disk.
struct OpenAITranscriptionService {
    func transcribe(wavData: Data) async throws -> [OpenAIDiarizedSegment] {
        let boundary = "RealtimeNoteTaker-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try OpenAISettings.apiKey())", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, wavData: wavData)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw OpenAIServiceError.requestFailed(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data).segments ?? []
    }

    private func multipartBody(boundary: String, wavData: Data) -> Data {
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        append("\r\n")
        field("model", "gpt-4o-transcribe-diarize")
        field("response_format", "diarized_json")
        field("language", "ja")
        append("--\(boundary)--\r\n")
        return body
    }
}

enum OpenAIServiceError: LocalizedError {
    case apiKeyMissing
    case invalidResponse
    case requestFailed(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            "OpenAI APIキーを設定してください。"
        case .invalidResponse:
            "OpenAI APIから正しい応答を受け取れませんでした。"
        case .requestFailed(let status, let body):
            "OpenAI APIへの送信に失敗しました（HTTP \(status)）。\(body)"
        }
    }
}
