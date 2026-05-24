import AppKit
import Combine

// MARK: - Usage model (5h block + weekly token quota, written by usage-tick.sh)

@MainActor
final class AgentUsageModel: ObservableObject {
    @Published var blockPct: Double = 0
    @Published var weeklyPct: Double = 0
    @Published var blockResetUnix: Int = 0
    @Published var weeklyResetUnix: Int = 0

    private var fileSource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var lastMtime: Date?
    private let path: String

    init(path: String, createIfMissing: Bool = true) {
        self.path = path
        if createIfMissing { ensureFileExists() }
        reload()
        watchFile()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollIfChanged()
        }
    }

    private func ensureFileExists() {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: Data("0\t0\t0\t0\t0\t0\n".utf8))
        }
    }

    private func pollIfChanged() {
        let filePath = self.path
        let mtime = self.lastMtime
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                  let newMtime = attrs[.modificationDate] as? Date else { return }
            if mtime != newMtime {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.lastMtime = newMtime
                    self.reload()
                }
            }
        }
    }

    func reload() {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.indices.contains(0) { blockPct        = Double(parts[0]) ?? 0 }
        if parts.indices.contains(1) { blockResetUnix  = Int(parts[1]) ?? 0 }
        if parts.indices.contains(2) { weeklyPct       = Double(parts[2]) ?? 0 }
        if parts.indices.contains(3) { weeklyResetUnix = Int(parts[3]) ?? 0 }
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            self.reload()
            if flags.contains(.delete) || flags.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.ensureFileExists()
                    self.watchFile()
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
    }
}
