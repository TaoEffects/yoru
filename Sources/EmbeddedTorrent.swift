import Foundation
import Security

actor TorrentClient {
    private struct Job: Codable {
        let id: String
        let name: String
        let folder: String
        let selected: Set<Int>
        let fileCount: Int
        var paused: Bool
    }

    private let storage: URL
    private let isolated: Bool
    private var engine: UnsafeMutableRawPointer?
    private var restored = false
    private var jobs: [String: Job] = [:]
    private var loadErrors: [String: String] = [:]
    private var monitor: Task<Void, Never>?
    private var completed = false
    private var available: [AvailableDownload] = []

    init(storage: URL = FileManager.support.appendingPathComponent("Torrents"), isolated: Bool = false) {
        self.storage = storage
        self.isolated = isolated
    }

    deinit {
        monitor?.cancel()
        if let engine { yoru_torrent_destroy(engine) }
    }

    private func jobFile(_ id: String) -> URL { storage.appendingPathComponent(id + ".json") }
    private func torrentFile(_ id: String) -> URL { storage.appendingPathComponent(id + ".torrent") }
    private func resumeFile(_ id: String) -> URL { storage.appendingPathComponent(id + ".resume") }
    private var availableFile: URL { storage.appendingPathComponent("Terminés.json") }

    private func error(_ raw: UnsafeMutablePointer<CChar>?) throws {
        guard let raw else { return }
        defer { free(raw) }
        throw Notice(String(cString: raw))
    }

    private func getEngine() throws -> UnsafeMutableRawPointer {
        if let engine { return engine }
        if !isolated, getenv("SSL_CERT_FILE") == nil {
            var certificateArray: CFArray?
            if SecTrustCopyAnchorCertificates(&certificateArray) == errSecSuccess,
               let certificates = certificateArray as? [SecCertificate], !certificates.isEmpty {
                let roots = storage.appendingPathComponent("trusted-roots.pem")
                let pem = certificates.map { certificate in
                    let raw = SecCertificateCopyData(certificate) as Data
                    return "-----BEGIN CERTIFICATE-----\n" + raw.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed]) + "\n-----END CERTIFICATE-----\n"
                }.joined()
                try pem.write(to: roots, atomically: true, encoding: .utf8)
                setenv("SSL_CERT_FILE", roots.path, 0)
            }
        }
        guard let result = yoru_torrent_create(isolated ? 1 : 0) else { throw Notice("Moteur BitTorrent indisponible.") }
        engine = result
        return result
    }

    private func start(_ job: Job, data: Data, resume: Data = Data()) throws {
        let engine = try getEngine()
        let selection = job.selected.sorted().map(Int32.init)
        let path = resumeFile(job.id).path
        let issue = data.withUnsafeBytes { bytes in
            resume.withUnsafeBytes { saved in
                yoru_torrent_add(engine, bytes.bindMemory(to: UInt8.self).baseAddress, data.count,
                    saved.bindMemory(to: UInt8.self).baseAddress, resume.count, job.name, job.id,
                    job.folder, path, selection, selection.count, job.fileCount, job.paused ? 1 : 0)
            }
        }
        try error(issue)
    }

    private func restore() throws {
        guard !restored else { return }
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: availableFile) {
            available = (try? JSONDecoder().decode([AvailableDownload].self, from: data)) ?? []
        }
        let files = try FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            guard let encoded = try? Data(contentsOf: file),
                  let job = try? JSONDecoder().decode(Job.self, from: encoded),
                  job.id.match(#"^[a-f0-9]{40}$"#) != nil,
                  file.lastPathComponent == job.id + ".json" else { continue }
            jobs[job.id] = job
            do {
                let (item, preview) = try TorrentSearch.local(torrentFile(job.id))
                guard item.id == job.id else { throw Notice("Empreinte du torrent modifiée.") }
                let resume = (try? Data(contentsOf: resumeFile(job.id))) ?? Data()
                try start(job, data: preview.data, resume: resume)
            } catch { loadErrors[job.id] = error.localizedDescription }
        }
        restored = true
        startMonitor()
    }

    func add(_ item: TorrentResult, preview: TorrentPreview, selected: Set<Int>, folder: URL) throws {
        try restore()
        guard jobs[item.id] == nil else { throw Notice("Ce torrent est déjà dans Yoru.") }
        guard preview.files.contains(where: { $0.isVideo && selected.contains($0.id) }) else { throw Notice("Choisis au moins une vidéo.") }
        let job = Job(id: item.id, name: item.title, folder: folder.path, selected: selected, fileCount: preview.files.count, paused: false)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try preview.data.write(to: torrentFile(item.id), options: .atomic)
        do {
            try JSONEncoder().encode(job).write(to: jobFile(item.id), options: .atomic)
            try start(job, data: preview.data)
            jobs[item.id] = job
            startMonitor()
        } catch {
            try? FileManager.default.removeItem(at: jobFile(item.id))
            try? FileManager.default.removeItem(at: torrentFile(item.id))
            throw error
        }
    }

    private func decode<Value: Decodable>(_ raw: UnsafeMutablePointer<CChar>?) throws -> Value {
        guard let raw else { throw Notice("Données de transfert indisponibles.") }
        defer { free(raw) }
        return try JSONDecoder().decode(Value.self, from: Data(String(cString: raw).utf8))
    }

    func transfers() throws -> [Transfer] {
        try restore()
        var rows = try pollEngine()
        for (id, detail) in loadErrors {
            guard let job = jobs[id] else { continue }
            rows.append(Transfer(hash: id, name: job.name, progress: 0, state: "error", dlspeed: 0,
                                 amount_left: 0, num_seeds: 0, content_path: "", save_path: job.folder, eta: nil, details: detail))
        }
        return rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func startMonitor() {
        guard monitor == nil, engine != nil, !jobs.isEmpty else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { break }
                if !(await self.monitorTick()) { break }
            }
        }
    }

    private func monitorTick() -> Bool {
        _ = try? pollEngine()
        let hasJobs = jobs.keys.contains { loadErrors[$0] == nil }
        if !hasJobs { monitor = nil }
        return hasJobs
    }

    private func pollEngine() throws -> [Transfer] {
        guard let engine else { return [] }
        let rows: [Transfer] = try decode(yoru_torrent_status(engine))
        for row in rows where row.finished && row.state != "error" {
            let files: [TransferredFile]? = try? decode(yoru_torrent_files(engine, row.id))
            yoru_torrent_remove(engine, row.id)
            if let job = jobs[row.id], let files {
                rememberCompletion(job, files: files)
            }
            jobs.removeValue(forKey: row.id)
            for file in [jobFile(row.id), torrentFile(row.id), resumeFile(row.id)] {
                try? FileManager.default.removeItem(at: file)
            }
            completed = true
        }
        return rows.filter { !$0.finished || $0.state == "error" }
    }

    private func rememberCompletion(_ job: Job, files: [TransferredFile]) {
        let root = URL(fileURLWithPath: job.folder, isDirectory: true).resolvingSymlinksInPath()
        let release = ReleaseName(job.name)
        let selected = files.enumerated().compactMap { index, file -> TorrentFile? in
            guard job.selected.contains(index), file.priority > 0, file.progress >= 1,
                  !file.name.hasPrefix("/"), !file.name.split(separator: "/").contains("..") else { return nil }
            let candidate = TorrentFile(id: index, path: file.name, bytes: 0)
            guard candidate.isVideo else { return nil }
            return candidate
        }
        let sorted = selected.sorted { left, right in
            if let exact = release.episode {
                let matchesLeft = left.episode == exact && (release.season == nil || left.season == nil || left.season == release.season)
                let matchesRight = right.episode == exact && (release.season == nil || right.season == nil || right.season == release.season)
                if matchesLeft != matchesRight { return matchesLeft }
            }
            if left.season != right.season { return (left.season ?? 0) < (right.season ?? 0) }
            if left.episode != right.episode { return (left.episode ?? Int.max) < (right.episode ?? Int.max) }
            return left.path.localizedStandardCompare(right.path) == .orderedAscending
        }
        let videos = sorted.compactMap { file -> URL? in
            let url = root.appendingPathComponent(file.path).resolvingSymlinksInPath()
            guard url.path.hasPrefix(root.path + "/"),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return url
        }
        guard !videos.isEmpty else { return }
        available.removeAll { $0.id == job.id }
        available.insert(AvailableDownload(id: job.id, title: job.name, videos: videos, finishedAt: Date()), at: 0)
        if available.count > 24 { available.removeLast(available.count - 24) }
        if let data = try? JSONEncoder().encode(available) { try? data.write(to: availableFile, options: .atomic) }
    }

    func finishedDownloads() throws -> [AvailableDownload] {
        try restore()
        return available
    }

    func transferSnapshot() throws -> (active: [Transfer], available: [AvailableDownload], completed: Bool) {
        let active = try transfers()
        return (active, available, takeCompletion())
    }

    func takeCompletion() -> Bool {
        defer { completed = false }
        return completed
    }

    func transferFiles(_ hash: String) throws -> [TransferredFile] {
        try restore()
        guard let engine else { return [] }
        return try decode(yoru_torrent_files(engine, hash))
    }

    func action(_ hash: String, start: Bool) throws {
        try restore()
        guard let engine, var job = jobs[hash] else { throw Notice("Transfert introuvable.") }
        if let detail = loadErrors[hash] { throw Notice(detail) }
        try error(yoru_torrent_action(engine, hash, start ? 1 : 0))
        job.paused = !start
        jobs[hash] = job
        try JSONEncoder().encode(job).write(to: jobFile(hash), options: .atomic)
    }

    // Used for loopback verification with a second embedded engine.
    func connectTestPeer(_ hash: String, port: UInt16) throws {
        guard isolated, let engine else { throw Notice("Session de test requise.") }
        try error(yoru_torrent_peer(engine, hash, "127.0.0.1", port))
    }

    func testPort() -> UInt16 { engine.map(yoru_torrent_port) ?? 0 }
}
