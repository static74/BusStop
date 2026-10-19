import BusStopCore
import Foundation
import os

/// Reads and writes `history.json` (SPEC §5.6). Writes run on a serial
/// background queue so encoding a few megabytes never blocks the UI.
nonisolated final class HistoryFile: Sendable {
    /// Hard-coded: `Bundle.main.bundleIdentifier` is nil under `swift run`.
    static let folderName = "io.github.static74.busstop"
    /// `~/Library/Application Support/io.github.static74.busstop`.
    static var standardDirectory: URL {
        URL.applicationSupportDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }

    let directory: URL
    let url: URL
    private let queue = DispatchQueue(label: "io.github.static74.busstop.history", qos: .utility)

    init(directory: URL) {
        self.directory = directory
        url = directory.appending(path: "history.json")
    }

    enum LoadResult: Sendable {
        case loaded(HistoryArchive)
        case missing
        /// The file could not be read; it was renamed `history-corrupt-<ms>.json`.
        case movedAside
        /// Written by a newer Bus Stop: left as it is and never overwritten.
        case newerSchema(Int)
    }

    func load() -> LoadResult {
        queue.sync {
            guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
            do {
                return .loaded(try HistoryArchive.decode(Data(contentsOf: url)))
            } catch HistoryArchive.DecodeError.newerSchema(let version) {
                return .newerSchema(version)
            } catch {
                let ms = Int64(Date().timeIntervalSince1970 * 1000)
                try? FileManager.default.moveItem(at: url, to: directory.appending(path: "history-corrupt-\(ms).json"))
                return .movedAside
            }
        }
    }

    /// Writes in the background.
    func save(_ archive: HistoryArchive) {
        queue.async { self.write(archive) }
    }

    /// Writes before returning, for will-sleep, quit and entering demo mode.
    func saveNow(_ archive: HistoryArchive) {
        queue.sync { write(archive) }
    }

    /// Returns once every queued write has finished.
    func waitForWrites() {
        queue.sync {}
    }

    /// Removes the file, corrupt copies and a newer version's file included.
    func delete() {
        queue.sync {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in names where name.hasPrefix("history") && name.hasSuffix(".json") {
                try? FileManager.default.removeItem(at: directory.appending(path: name))
            }
        }
    }

    func sizeOnDisk() -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }

    /// Atomic, so a failed or interrupted write leaves the previous file whole;
    /// a failure is not retried and the next save tries again.
    private func write(_ archive: HistoryArchive) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try archive.encoded().write(to: url, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Logger(subsystem: Self.folderName, category: "history")
                .error("Could not save \(self.url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
        }
    }
}
