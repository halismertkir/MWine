// SPDX-License-Identifier: Apache-2.0
import AppKit
import Combine

@MainActor
final class SteamDownloader: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var activeGameID: Int?
    @Published private(set) var status = "Mac Steam hesabınızla Windows paketini indirin."
    @Published private(set) var hasError = false
    @Published private(set) var receipts: [Int: SteamDownloadReceipt] = [:]
    @Published private(set) var currentPlan: SteamDownloadPlan?
    @Published private(set) var games: [SteamGame] = SteamGame.catalog
    private let root: URL
    private var task: Task<Void, Never>?
    private var children: [UUID: Process] = [:]
    private var jobURL: URL { root.appendingPathComponent("downloads/state/active-download.json") }
    private var consoleLog: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam/logs/console_log.txt")
    }
    init(root: URL) {
        self.root = root
        if let data = try? Data(contentsOf: root.appendingPathComponent("library.json")),
           let saved = try? JSONDecoder().decode([SteamGame].self, from:data) {
            games = saved.filter { $0.id > 0 && $0.id <= Int(UInt32.max) }
        }
        for game in games {
            let url = receiptURL(game.id)
            if let data = try? Data(contentsOf: url), let receipt = try? JSONDecoder().decode(SteamDownloadReceipt.self, from: data) {
                receipts[game.id] = receipt
            }
        }
        if let data = try? Data(contentsOf: jobURL),
           let job = try? JSONDecoder().decode(SteamDownloadJob.self, from: data),
           let game = games.first(where: { $0.id == job.gameID }), job.plan.appID == game.id {
            begin(game: game) { try await self.download(game: game, initialJob: job) }
        }
    }
    func add(_ input: String) throws {
        let game = try SteamGame.imported(input)
        if !games.contains(where: { $0.id == game.id }) { games.append(game) }
        try save(games, at:root.appendingPathComponent("library.json"))
    }
    func remove(_ game:SteamGame) throws {
        guard !busy else { throw SteamDownloadError.message("İndirme sürerken oyun kaldırılamaz.") }
        let remaining = games.filter { $0.id != game.id }
        try save(remaining, at:root.appendingPathComponent("library.json"))
        games = remaining
        // Keep prefixes, downloads and saves; removing a library entry never deletes user data.
    }
    func replaceExecutable(for game: SteamGame, with url: URL) throws {
        guard WindowsExecutable.isSupported(url) else { throw SteamDownloadError.message("x86 / x64 Windows PE dosyası seçin.") }
        try save(url.path, at:root.appendingPathComponent("downloads/state/\(game.id)-local.json"))
        objectWillChange.send()
    }
    private func receiptURL(_ id: Int) -> URL { root.appendingPathComponent("downloads/state/\(id)-receipt.json") }
    private func save<T: Encodable>(_ value: T, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
    private var steamExecutable: URL? {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx")
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.valvesoftware.steam")?.appendingPathComponent("Contents/MacOS/steam_osx")
        return [support, app].compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    private func run(_ executable: URL, arguments: [String], log: URL? = nil) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = executable; process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            var logHandle: FileHandle?
            if let log {
                do {
                    try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
                    FileManager.default.createFile(atPath: log.path, contents: nil)
                    logHandle = try FileHandle(forWritingTo: log)
                    process.standardOutput = logHandle; process.standardError = logHandle
                } catch { continuation.resume(throwing: error); return }
            }
            let output = logHandle
            process.terminationHandler = { [weak self] completed in
                try? output?.close()
                Task { @MainActor in
                    self?.children.removeValue(forKey: id)
                    if completed.terminationStatus == 0 { continuation.resume() }
                    else { continuation.resume(throwing: SteamDownloadError.message("Başlatıcı işlemi tamamlanamadı. Kayıtları kontrol edin.")) }
                }
            }
            children[id] = process
            do { try process.run() }
            catch { try? output?.close(); children.removeValue(forKey: id); continuation.resume(throwing: error) }
        }
    }
    private func send(_ arguments: [String]) async throws {
        if arguments.contains("+download_depot") {
            guard arguments.count == 5, arguments.dropFirst(2).allSatisfy({ UInt64($0).map { $0 > 0 } == true }) else {
                throw SteamDownloadError.message("İndirme kimlikleri geçersiz.")
            }
        }
        guard let executable = steamExecutable else { throw SteamDownloadError.message("Mac Steam bulunamadı. Önce Steam'i kurup hesabınıza giriş yapın.") }
        // A cold-started Steam process stays alive until the user quits Steam.
        // Dispatch now and verify the response in the console; never wait for that process to exit.
        let id = UUID(), process = Process()
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.children.removeValue(forKey:id) } }
        children[id] = process
        do { try process.run() } catch { children.removeValue(forKey:id); throw error }
    }
    private func begin(game: SteamGame, operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; hasError = false; activeGameID = game.id
        task = Task { @MainActor in
            do { try await operation() }
            catch {
                hasError = true; status = error.localizedDescription
                // A failure requires a fresh query on retry; Steam may keep downloading.
                try? FileManager.default.removeItem(at: jobURL)
            }
            busy = false; task = nil
        }
    }
    func start(_ game: SteamGame) {
        begin(game: game) {
            self.status = "\(game.name) için güncel Windows paketi Steam'den sorgulanıyor…"
            self.currentPlan = nil
            var cursor = SteamLogCursor(url: self.consoleLog)
            try await self.send(["-console", "+app_info_print", String(game.id)])
            var output = ""
            let deadline = Date().addingTimeInterval(60)
            var plan: SteamDownloadPlan?
            while Date() < deadline {
                try Task.checkCancellation()
                output += try cursor.read(url: self.consoleLog)
                guard output.utf8.count < 4_000_000 else { throw SteamDownloadError.message("Steam konsolu çok fazla çıktı üretti. İndirmeyi yeniden deneyin.") }
                if let found = try SteamMetadata.plan(game: game, output: output) { plan = found; break }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            guard let plan else { throw SteamDownloadError.message("Steam oyun bilgilerini yanıtlamadı. Mac Steam'de çevrimiçi olduğunuzu ve hesabınıza giriş yaptığınızı kontrol edin.") }
            self.currentPlan = plan
            try self.save(plan, at: self.root.appendingPathComponent("downloads/state/\(game.id)-plan.json"))
            // A new completion receipt is required when downloading/verifying a new manifest.
            self.receipts.removeValue(forKey: game.id)
            try? FileManager.default.removeItem(at: self.receiptURL(game.id))
            let job = SteamDownloadJob(gameID: game.id, plan: plan, depotIndex: 0,
                cursor: SteamLogCursor(url: self.consoleLog), commandSent: false)
            try self.save(job, at: self.jobURL)
            try await self.download(game: game, initialJob: job)
        }
    }
    private func download(game: SteamGame, initialJob: SteamDownloadJob) async throws {
        var job = initialJob
        currentPlan = job.plan
        guard job.depotIndex >= 0 && job.depotIndex <= job.plan.depots.count else { throw SteamDownloadError.message("İndirme kaydı geçersiz.") }
        while job.depotIndex < job.plan.depots.count {
            let depot = job.plan.depots[job.depotIndex]
            var cursor = job.cursor
            if !job.commandSent {
                job.cursor = SteamLogCursor(url: consoleLog); cursor = job.cursor
                // Checkpoint before sending: re-opened MYT follows this request instead of duplicating it.
                job.commandSent = true; try save(job, at: jobURL)
                status = "\(game.name): indirme isteği Mac Steam'e gönderiliyor…"
                try await send(job.plan.arguments(for: depot))
            } else { status = "\(game.name): Steam indirmesi takip ediliyor…" }
            var lineBuffer = SteamConsoleLines()
            var started = false, complete = false
            let acknowledgement = Date().addingTimeInterval(60)
            let deadline = Date().addingTimeInterval(3600)
            while Date() < deadline && !complete {
                try Task.checkCancellation()
                let lines = lineBuffer.append(try cursor.read(url: consoleLog))
                if !lines.isEmpty {
                    for event in SteamDepotEvent.events(in: lines, appID: game.id, depot: depot) {
                        switch event {
                        case .started:
                            started = true
                            let size = ByteCountFormatter.string(fromByteCount: Int64(clamping: job.plan.downloadBytes), countStyle: .file)
                            status = "\(game.name) indiriliyor / dosyalar doğrulanıyor. Paket indirme boyutu: \(size)."
                        case .complete: complete = true
                        case .failure(let message): throw SteamDownloadError.message(message)
                        }
                    }
                }
                if !started && !complete && Date() > acknowledgement {
                    throw SteamDownloadError.message("Steam indirme isteğini doğrulamadı. Mac Steam oturumunu ve konsolunu kontrol edip yeniden deneyin.")
                }
                if !complete { try await Task.sleep(nanoseconds: 1_000_000_000) }
            }
            guard complete else { throw SteamDownloadError.message("Steam indirmesi zaman aşımına uğradı. Steam konsolunu kontrol edip yeniden deneyin.") }
            job.depotIndex += 1; job.cursor = cursor; job.commandSent = false
            try save(job, at: jobURL)
        }
        if job.plan.depots.count > 1 {
            let directories = try job.plan.depots.map { depot -> URL in
                guard let path = depotDirectory(appID:game.id, depot:depot) else { throw SteamDownloadError.message("İndirilen paket klasörü bulunamadı.") }
                return path
            }
            status = "Windows paketleri birleştiriliyor…"
            let destination = root.appendingPathComponent("games/\(game.id)")
            try await Task.detached { try DepotAssembler.assemble(directories, into:destination) }.value
        }
        guard locateExecutable(game: game, plan: job.plan) != nil else {
            throw SteamDownloadError.message("Steam indirmeyi tamamladı ancak Windows oyun dosyası bulunamadı. Oyun profilini kontrol edin.")
        }
        let receipt = SteamDownloadReceipt(plan: job.plan, completedAt: Date())
        try save(receipt, at: receiptURL(game.id)); receipts[game.id] = receipt
        try? FileManager.default.removeItem(at: jobURL)
        status = "\(game.name) indirildi. Steam tamamlanmayı doğruladı; Windows dosyaları hazır."
        // Runtime preparation belongs to launch: only install the engine the user selected.
    }
    private func depotDirectory(appID:Int, depot:SteamDepot) -> URL? {
        let steamRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam")
        let roots = [steamRoot.appendingPathComponent("Steam.AppBundle/Steam/Contents/MacOS/steamapps/content"), steamRoot.appendingPathComponent("steamapps/content")]
        return roots.map { $0.appendingPathComponent("app_\(appID)/depot_\(depot.id)") }.first { FileManager.default.fileExists(atPath:$0.path) }
    }
    private func locateExecutable(game:SteamGame, plan:SteamDownloadPlan) -> URL? {
        guard let path = SteamMetadata.safeExecutable(plan.executable ?? game.executable) else { return nil }
        let directories = plan.depots.count > 1 ? [root.appendingPathComponent("games/\(game.id)")] : plan.depots.compactMap { depotDirectory(appID:game.id, depot:$0) }
        return directories.map { $0.appendingPathComponent(path) }.first { WindowsExecutable.isSupported($0) }
    }
    func executable(for game:SteamGame) -> URL? {
        if let data = try? Data(contentsOf:root.appendingPathComponent("downloads/state/\(game.id)-local.json")),
           let path = try? JSONDecoder().decode(String.self, from:data), WindowsExecutable.isSupported(URL(fileURLWithPath:path)) { return URL(fileURLWithPath:path) }
        guard let receipt = receipts[game.id] else { return nil }
        return locateExecutable(game:game, plan:receipt.plan)
    }
    func openConsole() {
        Task {
            do { try await send(["-console", "steam://open/console"]) }
            catch { hasError = true; status = error.localizedDescription }
        }
    }
    func prepareDXMT() async throws {
        status = "DirectX–Metal desteği hazırlanıyor…"
        try await run(URL(fileURLWithPath: "/bin/bash"), arguments: [root.appendingPathComponent("scripts/setup-dxmt").path], log: root.appendingPathComponent("logs/setup-dxmt.log"))
        status = "DirectX–Metal desteği hazır."
    }
    func prepareNativeRuntime() async throws {
        status = "Yerel ARM64 motoru hazırlanıyor…"
        try await run(URL(fileURLWithPath: "/bin/bash"), arguments: [root.appendingPathComponent("scripts/setup-native-arm64").path], log: root.appendingPathComponent("logs/setup-native-arm64.log"))
        status = "Yerel ARM64 Wine + FEX motoru hazır."
    }
    func prepareVulkanRuntime() async throws {
        status = "Önceki Vulkan motoru hazırlanıyor…"
        try await run(URL(fileURLWithPath:"/bin/bash"), arguments:[root.appendingPathComponent("scripts/setup-vulkan-game").path], log:root.appendingPathComponent("logs/setup-vulkan-game.log"))
        status = "Önceki Vulkan motoru hazır."
    }
}
