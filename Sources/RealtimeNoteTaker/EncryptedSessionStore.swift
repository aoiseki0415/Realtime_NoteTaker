import CryptoKit
import Foundation

enum EncryptedSessionStore {
    private static let keyAccount = "temporary-transcript-key"

    static var baseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("RealtimeNoteTaker/sessions", isDirectory: true)
    }

    static func save(_ session: MeetingSession) throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let key = try encryptionKey()
        let data = try JSONEncoder().encode(session)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw StoreError.invalidCiphertext }
        try combined.write(to: fileURL(for: session.id), options: .atomic)
    }

    static func loadAll() throws -> [MeetingSession] {
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return [] }
        let key = try encryptionKey()
        let files = try FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "session" }.compactMap { url in
            let combined = try Data(contentsOf: url)
            let box = try AES.GCM.SealedBox(combined: combined)
            let data = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode(MeetingSession.self, from: data)
        }
    }

    static func delete(_ session: MeetingSession) throws {
        let url = fileURL(for: session.id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Use only after all temporary sessions are deleted. This makes prior encrypted data unrecoverable.
    static func destroyTemporaryTranscriptKey() {
        KeychainStore.delete(account: keyAccount)
    }

    private static func encryptionKey() throws -> SymmetricKey {
        if let existing = try KeychainStore.load(account: keyAccount) {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        try KeychainStore.save(key.withUnsafeBytes { Data($0) }, account: keyAccount)
        return key
    }

    private static func fileURL(for id: UUID) -> URL {
        baseURL.appendingPathComponent("\(id.uuidString).session")
    }
}

enum StoreError: LocalizedError {
    case invalidCiphertext

    var errorDescription: String? { "一時転写データを暗号化できませんでした。" }
}
