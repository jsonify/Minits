import Foundation

/// The contents of a session's session.json.
struct SessionConfig: Codable, Equatable, Sendable {
    var venue: String?
    var notes: String?
    var members: [String] = []
    /// Seconds to add to a member's track timestamps to land on table.wav's timeline. Overrides clap sync.
    var trackOffsetsSeconds: [String: Double] = [:]
}

enum SessionFolderError: LocalizedError, Equatable {
    case missing(session: String, file: String)
    case noSessions(String)

    var errorDescription: String? {
        switch self {
        case .missing(let session, let file): return "Session \(session) has no \(file)"
        case .noSessions(let path): return "No sessions (folders with table.wav) under \(path)"
        }
    }
}

/// One recorded session on disk:
///
///     <name>/session.json  table.wav  enroll/<member>.wav  tracks/<member>.wav  labels.json
struct SessionFolder: Equatable, Sendable {
    var url: URL

    var name: String { url.lastPathComponent }
    var tableURL: URL { url.appendingPathComponent("table.wav") }
    var labelsURL: URL { url.appendingPathComponent("labels.json") }
    var configURL: URL { url.appendingPathComponent("session.json") }
    var enrollURL: URL { url.appendingPathComponent("enroll") }
    var tracksURL: URL { url.appendingPathComponent("tracks") }

    /// `path` itself when it is a session, otherwise its immediate subfolders that are, by name.
    static func discover(at path: URL) throws -> [SessionFolder] {
        let files = FileManager.default
        if files.fileExists(atPath: path.appendingPathComponent("table.wav").path) {
            return [SessionFolder(url: path)]
        }
        let children = (try? files.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)) ?? []
        let sessions = children
            .filter { files.fileExists(atPath: $0.appendingPathComponent("table.wav").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(SessionFolder.init)
        guard !sessions.isEmpty else { throw SessionFolderError.noSessions(path.path) }
        return sessions
    }

    func config() throws -> SessionConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return SessionConfig() }
        return try JSONDecoder().decode(SessionConfig.self, from: Data(contentsOf: configURL))
    }

    func labels() throws -> GroundTruth {
        guard FileManager.default.fileExists(atPath: labelsURL.path) else {
            throw SessionFolderError.missing(session: name, file: "labels.json")
        }
        return try JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: labelsURL))
    }

    /// Enrollment samples by member name, sorted.
    func enrollmentSamples() throws -> [(member: String, url: URL)] {
        let samples = wavFiles(in: enrollURL)
        guard !samples.isEmpty else { throw SessionFolderError.missing(session: name, file: "enroll/*.wav") }
        return samples
    }

    /// Personal tracks by member name, sorted.
    func trackFiles() throws -> [(member: String, url: URL)] {
        let tracks = wavFiles(in: tracksURL)
        guard !tracks.isEmpty else { throw SessionFolderError.missing(session: name, file: "tracks/*.wav") }
        return tracks
    }

    private func wavFiles(in folder: URL) -> [(member: String, url: URL)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "wav" }
            .map { ($0.deletingPathExtension().lastPathComponent, $0) }
            .sorted { $0.member < $1.member }
    }
}

extension GroundTruth {
    /// labels.json as written by `minits-eval label`: sorted keys, readable, stable.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
