import Foundation

private struct MinutesRefreshResponse: Decodable {
    let importantIndices: [Int]
    let sections: [String: String]
}

private struct ResponsesAPIResponse: Decodable {
    struct Output: Decodable {
        struct Content: Decodable { let type: String; let text: String? }
        let content: [Content]?
    }
    let output: [Output]

    var text: String? {
        output.flatMap { $0.content ?? [] }.first(where: { $0.type == "output_text" })?.text
    }
}

struct MinutesRefreshService {
    func refresh(
        recentSegments: [TranscriptSegment],
        current: StructuredMinutes
    ) async throws -> (importantIDs: Set<UUID>, updatedSections: [String: String]) {
        let indexed = recentSegments.enumerated().map { index, segment in
            "[\(index)] \(segment.speaker): \(segment.text)"
        }.joined(separator: "\n")
        let sectionList = current.template.sections.joined(separator: "、")
        let prompt = """
        以下は日本語会議の直近30秒の発話です。議事録を最小限に保つため、本当に重要な発話だけを選び、既存の議事録を更新してください。
        重要とするのは、決定・合意、次の行動、担当・期限、方針変更、重大な問題・リスク、結論を左右する事実・数値だけです。
        挨拶、相づち、言い直し、途中で切れた発話、背景説明の細部、具体例、既存内容の繰り返しは重要発話に選ばず、議事録にも書かないでください。
        重要な内容がなければ、importantIndicesは空配列、sectionsは空のオブジェクトにしてください。
        発言者名は構造化まとめには書かないでください。推測で事実を追加しないでください。
        構造化まとめは箇条書きで簡潔に書き、各見出しは最大3項目・合計120文字程度までに抑えてください。既存内容を冗長に言い換えたり、重要度の低い情報で更新したりしないでください。
        必ずJSONのみを返してください。
        形式: {"importantIndices":[0],"sections":{"見出し":"更新後の本文"}}
        許可された見出し: \(sectionList)
        既存のまとめ: \(current.sections)
        発話:
        \(indexed)
        """
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try OpenAISettings.apiKey())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-5-mini",
            "store": false,
            "input": prompt
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OpenAIServiceError.invalidResponse
        }
        guard let text = try JSONDecoder().decode(ResponsesAPIResponse.self, from: data).text,
              let json = text.data(using: .utf8) else { throw OpenAIServiceError.invalidResponse }
        let result = try JSONDecoder().decode(MinutesRefreshResponse.self, from: json)
        let valid = Set(result.importantIndices.compactMap { recentSegments.indices.contains($0) ? recentSegments[$0].id : nil })
        let sections = result.sections.filter { current.template.sections.contains($0.key) }
        return (valid, sections)
    }
}
