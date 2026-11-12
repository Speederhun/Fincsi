import Foundation

/// Atomikus JSON-mentés. Sérült fájl esetén átnevezi (`.corrupt`), és üres értékkel indul újra.
public struct JSONFileStore<Value: Codable>: @unchecked Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Visszaadja a mentett értéket; `nil`, ha még nincs fájl. Sérült fájlnál a fájlt félreteszi és `nil`-t ad.
    public func load() -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            quarantine()
            return nil
        }
    }

    public func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(value)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw FincsiError.storage(error.localizedDescription)
        }
    }

    public func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    private func quarantine() {
        let backup = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}
