// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class Launcher: ObservableObject {
    @Published var selectedID = 3405340
    @Published var entry = ""
    @Published var message = "Steam hesabınıza Mac Steam üzerinden giriş yapın."
    @Published var working = false
    @Published var hud = false
    @Published var arguments = ""
    @Published var nativeReady = false
    @Published var sessionRunning = false
    let root:URL
    let downloader:SteamDownloader
    private var process:Process?
    private var sessionLog:BoundedProcessLog?
    init() {
        do { root = try Workspace.prepare() }
        catch {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MWine")
            message = error.localizedDescription
        }
        downloader = SteamDownloader(root:root)
        nativeReady = RuntimeConfiguration.nativeAvailable(root)
        selectedID = downloader.games.first?.id ?? 3405340
    }
    var game:SteamGame? { downloader.games.first { $0.id == selectedID } }
    func addGame() {
        do {
            let imported = try SteamGame.imported(entry)
            try downloader.add(entry); selectedID = imported.id; entry = ""
            message = "Oyun eklendi. Windows paketini indirin veya mevcut .exe dosyasını seçin."
        } catch { message = error.localizedDescription }
    }
    func installEngine() {
        guard !working && !sessionRunning else { return }
        working = true
        Task { [self] in
            defer { working = false }
            do { try await downloader.prepareNativeRuntime(); nativeReady = RuntimeConfiguration.nativeAvailable(root); message = "Yerel ARM64 motoru hazır." }
            catch { message = error.localizedDescription }
        }
    }
    func chooseEXE(attach:Bool) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension:"exe") ?? .data]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard WindowsExecutable.isSupported(url) else { message = "x86 veya x64 Windows PE dosyası seçin."; return }
        if attach, let game {
            do { try downloader.replaceExecutable(for:game, with:url); message = "Oyun dosyası bağlandı. Steam gereken oyunlarda doğru App ID kullanın." }
            catch { message = error.localizedDescription }
        } else { launch(executable:url, game:nil) }
    }
    func openGame() {
        guard let game, let executable = downloader.executable(for:game) else { message = "Önce oyunu indirin veya mevcut .exe dosyasını bağlayın."; return }
        launch(executable:executable, game:game)
    }
    private func launch(executable:URL, game:SteamGame?) {
        guard !working && !sessionRunning else { return }
        guard nativeReady else { message = "Önce yerel motoru kurun. Kurulum yaklaşık 1,1 GB alan kullanır; her Windows ortamı ek alan gerektirir."; return }
        working = true
        Task { [self] in
            defer { working = false }
            do {
                let p = Process()
                var env = RuntimeConfiguration.cleanEnvironment(ProcessInfo.processInfo.environment)
                env["MTL_HUD_ENABLED"] = hud ? "1" : "0"
                let extra = arguments.components(separatedBy:.newlines).filter { !$0.isEmpty }
                if let game {
                    let plan = try RuntimeConfiguration.nativePlan(project:root, game:game, executable:executable, hud:hud, inherited:env)
                    try FileManager.default.createDirectory(at:plan.cache, withIntermediateDirectories:true)
                    p.executableURL = plan.program; p.arguments = plan.arguments + extra; p.environment = plan.environment
                } else {
                    p.executableURL = root.appendingPathComponent("scripts/native-exe"); p.arguments = [executable.path] + extra; p.environment = env
                }
                p.currentDirectoryURL = executable.deletingLastPathComponent()
                let logURL = root.appendingPathComponent("logs/sessions/last-session.log")
                try FileManager.default.createDirectory(at:logURL.deletingLastPathComponent(), withIntermediateDirectories:true)
                let log = try BoundedProcessLog(url:logURL, limit:8*1024*1024)
                p.standardOutput = log.pipe; p.standardError = log.pipe
                p.terminationHandler = { [weak self] ended in
                    log.finish()
                    Task { @MainActor in
                        self?.process = nil; self?.sessionLog = nil; self?.sessionRunning = false
                        self?.message = ended.terminationStatus == 0 ? "Oyun oturumu kapandı." : "Oyun kod \(ended.terminationStatus) ile kapandı. Kayıtlar bölümünden ayrıntıyı inceleyin."
                    }
                }
                process = p; sessionLog = log
                do { try p.run(); sessionRunning = true; message = "\(game?.name ?? executable.lastPathComponent) başlatıldı. Uyumluluk oyuna göre değişir." }
                catch { log.finish(); process = nil; sessionLog = nil; throw error }
            } catch { message = error.localizedDescription }
        }
    }
    func stop() { process?.terminate(); message = "Oyun oturumu kapatılıyor…" }
    func show(_ path:String) {
        let folder = root.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at:folder, withIntermediateDirectories:true)
        NSWorkspace.shared.open(folder)
    }
}

struct ContentView:View {
    @StateObject private var launcher = Launcher()
    private let accent = Color(red:0.73, green:0.92, blue:0.36)
    var body:some View { LibraryView(launcher:launcher, downloader:launcher.downloader, accent:accent).onDisappear { if launcher.sessionRunning { launcher.stop() } } }
}

struct LibraryView:View {
    @ObservedObject var launcher:Launcher
    @ObservedObject var downloader:SteamDownloader
    let accent:Color
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading, spacing:24) {
                HStack { Image(systemName:"cpu").foregroundStyle(accent); Text("M WINE").font(.system(size:24, weight:.black, design:.monospaced)) }
                Text("WINDOWS → MAC").font(.caption.monospaced()).foregroundStyle(.secondary)
                List(selection:$launcher.selectedID) {
                    ForEach(downloader.games) { game in
                        VStack(alignment:.leading, spacing:5) {
                            Text(downloader.receipts[game.id]?.plan.title ?? game.name).font(.headline)
                            Text("STEAM / \(String(game.id))").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }.padding(.vertical,6).tag(game.id).contextMenu {
                            Button("Kütüphaneden kaldır", role:.destructive) {
                                do { try downloader.remove(game); launcher.selectedID = downloader.games.first?.id ?? 0 }
                                catch { launcher.message = error.localizedDescription }
                            }.disabled(downloader.busy || launcher.sessionRunning)
                        }
                    }
                }.listStyle(.sidebar)
                Button("Bağımsız .exe aç…", systemImage:"plus.app") { launcher.chooseEXE(attach:false) }.disabled(launcher.working || launcher.sessionRunning)
                Button("Kayıtları aç", systemImage:"doc.text") { launcher.show("logs") }
                Link("GitHub · MWine", destination:URL(string:"https://github.com/halismertkir/MWine")!).font(.caption)
                Text("0.5.0 · Deneysel").font(.caption.monospaced()).foregroundStyle(.secondary)
            }.padding(24).frame(width:240).background(Color.black.opacity(0.22))
            ScrollView {
                VStack(alignment:.leading, spacing:24) {
                    HStack { Text("UYUMLULUK KÜTÜPHANESİ").font(.caption.monospaced().weight(.bold)).foregroundStyle(accent); Spacer(); Text("APPLE SILICON").font(.caption.monospaced()).foregroundStyle(.secondary) }
                    if let game = launcher.game {
                        Text(downloader.receipts[game.id]?.plan.title ?? game.name).font(.system(size:36, weight:.bold, design:.rounded))
                        Text("Windows oyununu kendi Steam hesabınız ve ayrı bir Windows ortamıyla çalıştırın.").foregroundStyle(.secondary)
                        HStack {
                            Button(downloader.executable(for:game) == nil ? "Windows paketini indir" : "Paketleri doğrula / güncelle", systemImage:"arrow.down.circle") { downloader.start(game) }.disabled(downloader.busy || launcher.working || launcher.sessionRunning)
                            Button("Oyunu aç", systemImage:"play.fill") { launcher.openGame() }.tint(accent).disabled(downloader.executable(for:game) == nil || launcher.working || launcher.sessionRunning)
                            Button(".exe bağla…") { launcher.chooseEXE(attach:true) }.disabled(launcher.working || launcher.sessionRunning || downloader.busy)
                        }.buttonStyle(.borderedProminent)
                    }
                    Divider()
                    VStack(alignment:.leading, spacing:12) {
                        Text("OYUN EKLE").font(.caption.monospaced().weight(.bold))
                        HStack {
                            TextField("Steam mağaza bağlantısı veya App ID", text:$launcher.entry).textFieldStyle(.roundedBorder).onSubmit { launcher.addGame() }
                            Button("Ekle") { launcher.addGame() }.disabled(launcher.entry.isEmpty || downloader.busy)
                        }
                        Text("Bir oyuna özel kod gerekmez. Ortak paketler, DRM ve anti-cheat bazı oyunlarda elle işlem gerektirebilir.").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment:.leading, spacing:12) {
                        HStack {
                            Label(launcher.nativeReady ? "Yerel ARM64 motoru kurulu" : "Yerel ARM64 motoru kurulmalı", systemImage:"cpu").font(.headline)
                            Spacer()
                            Button(launcher.nativeReady ? "Motoru doğrula" : "Motoru kur") { launcher.installEngine() }.disabled(launcher.working || launcher.sessionRunning || downloader.busy)
                        }
                        Text("Apple Silicon + macOS 27 veya sonrası. Wine Windows API'lerini, FEX Intel kodunu, grafik bileşenleri DirectX/Vulkan çağrılarını çevirir. Rosetta gerekmez.").font(.callout).foregroundStyle(.secondary)
                        Toggle("Metal performans göstergesini aç", isOn:$launcher.hud)
                        Text("Başlatma argümanları · her satır ayrı bir argüman").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text:$launcher.arguments).font(.system(.body, design:.monospaced)).frame(height:60)
                        Text("Oyun kalitesi veya çözünürlük zorlanmaz. Çeviri maliyeti ve oyuna özel sorunlar devam edebilir; performans artışı garanti edilmez.").font(.caption).foregroundStyle(.secondary)
                    }.padding(20).background(Color.white.opacity(0.045), in:RoundedRectangle(cornerRadius:14))
                    VStack(alignment:.leading, spacing:10) {
                        if downloader.busy || launcher.working { ProgressView().controlSize(.small) }
                        Text(downloader.status).foregroundStyle(downloader.hasError ? .orange : .secondary)
                        Text(launcher.message).font(.callout)
                        HStack {
                            Button("Steam konsolunu aç") { downloader.openConsole() }
                            Button("Veri klasörü") { launcher.show("") }
                            if launcher.sessionRunning { Button("Oyunu durdur", role:.destructive) { launcher.stop() } }
                        }
                        Text("İndirme hesabınızla Mac Steam'de gerçekleşir; MWine şifre istemez. Konsol indirmeleri Steam'in standart İndirilenler ekranında görünmeyebilir. Tamamlanma burada takip edilir.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(36).frame(maxWidth:.infinity, alignment:.leading)
            }
        }.frame(minWidth:1020, minHeight:750).background(Color(red:0.075, green:0.095, blue:0.10)).preferredColorScheme(.dark)
    }
}

@main
struct MWineApp:App {
    var body:some Scene {
        WindowGroup("MWine") { ContentView() }
        .commands {
            CommandGroup(replacing:.appInfo) {
                Button("MWine hakkında") {
                    NSWorkspace.shared.open(URL(string:"https://github.com/halismertkir/MWine")!)
                }
            }
        }
    }
}
