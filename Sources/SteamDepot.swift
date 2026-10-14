// SPDX-License-Identifier: Apache-2.0
import Foundation

struct SteamGame: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let executable: String
    let usesDXMT: Bool
    var graphics: String { "DirectX / Vulkan → Metal · motora ve oyuna bağlı" }
    static func imported(_ input: String) throws -> SteamGame {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String
        if let url = URL(string: text), url.scheme == "https", url.host == "store.steampowered.com",
           url.pathComponents.count >= 3, url.pathComponents[1] == "app" { value = url.pathComponents[2] }
        else { value = text }
        guard value.allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int(value), id > 0, id <= Int(UInt32.max) else {
            throw SteamDownloadError.message("Geçerli bir Steam App ID veya Steam mağaza bağlantısı girin.")
        }
        return catalog.first(where: { $0.id == id }) ?? SteamGame(id:id, name:"Steam oyun \(id)", executable:"", usesDXMT:false)
    }
    static let catalog = [
        SteamGame(id: 3405340, name: "Megabonk", executable: "Megabonk.exe", usesDXMT: true),
        SteamGame(id: 5165210, name: "Find The Needle Demo", executable: "FindTheNeedle.exe", usesDXMT: false)
    ]
}

struct SteamDepot: Codable, Equatable {
    let id: String
    let manifest: String
    let diskBytes: UInt64
    let downloadBytes: UInt64
}

struct SteamDownloadPlan: Codable, Equatable {
    let appID: Int
    let depots: [SteamDepot]
    var executable: String? = nil
    var title: String? = nil
    var downloadBytes: UInt64 { depots.reduce(0) { $0 + $1.downloadBytes } }
    var diskBytes: UInt64 { depots.reduce(0) { $0 + $1.diskBytes } }
    func arguments(for depot: SteamDepot) -> [String] {
        ["-console", "+download_depot", String(appID), depot.id, depot.manifest]
    }
    var commands: String {
        depots.map { "download_depot \(appID) \($0.id) \($0.manifest)" }.joined(separator: "\n")
    }
}

enum SteamDownloadError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

// Parse only the public app-info block requested from the local Steam client.
// No account/config/login files are read.
indirect enum SteamValue {
    case text(String)
    case object([String: SteamValue])
    var text: String? { if case .text(let value) = self { return value }; return nil }
    var object: [String: SteamValue] { if case .object(let value) = self { return value }; return [:] }
    subscript(_ key: String) -> SteamValue? { object[key] }
}

struct SteamVDFParser {
    private let characters: [Character]
    private var index = 0
    init(_ text: String) { characters = Array(text) }
    private mutating func whitespace() {
        while index < characters.count {
            if characters[index].isWhitespace { index += 1 }
            else if index + 1 < characters.count && characters[index] == "/" && characters[index + 1] == "/" {
                while index < characters.count && characters[index] != "\n" { index += 1 }
            } else { break }
        }
    }
    private mutating func token() throws -> String {
        whitespace()
        guard index < characters.count else { throw SteamDownloadError.message("Steam bilgisi eksik.") }
        let first = characters[index]; index += 1
        if first == "{" || first == "}" { return String(first) }
        var result = ""
        if first == "\"" {
            while index < characters.count {
                let character = characters[index]; index += 1
                if character == "\"" { return result }
                if character == "\\", index < characters.count {
                    let next = characters[index]; index += 1
                    if next != "\\" && next != "\"" { result.append("\\") }
                    result.append(next)
                } else { result.append(character) }
            }
            throw SteamDownloadError.message("Steam bilgisi eksik.")
        }
        result.append(first)
        while index < characters.count && !characters[index].isWhitespace && characters[index] != "{" && characters[index] != "}" {
            result.append(characters[index]); index += 1
        }
        return result
    }
    private mutating func object(depth: Int = 0) throws -> SteamValue {
        guard depth < 64 else { throw SteamDownloadError.message("Steam bilgisi geçersiz.") }
        var entries: [String: SteamValue] = [:]
        while true {
            let key = try token()
            if key == "}" { return .object(entries) }
            guard key != "{", entries[key] == nil else { throw SteamDownloadError.message("Steam bilgisi belirsiz.") }
            let value = try token()
            guard value != "}" else { throw SteamDownloadError.message("Steam bilgisi eksik.") }
            entries[key] = value == "{" ? try object(depth: depth + 1) : .text(value)
        }
    }
    mutating func parse() throws -> SteamValue {
        let key = try token()
        guard try token() == "{" else { throw SteamDownloadError.message("Steam bilgisi geçersiz.") }
        return .object([key: try object()])
    }
}

enum SteamMetadata {
    static func safeExecutable(_ raw: String) -> String? {
        let path = raw.replacingOccurrences(of:"\\", with:"/")
        let parts = path.split(separator:"/", omittingEmptySubsequences:false)
        guard !path.isEmpty, !path.contains(":"), !path.contains("\0"), !path.hasPrefix("/"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }), path.lowercased().hasSuffix(".exe") else { return nil }
        return path
    }
    static func appBlock(appID: Int, in output: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?m)^(?:\\[[^\\r\\n]+\\]\\s*)?(\"\(appID)\"\\s*\\{)") else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        // The most recent response is the only one eligible for planning.
        guard let match = regex.matches(in: output, range: range).last,
              let swiftRange = Range(match.range(at: 1), in: output) else { return nil }
        var depth = 0, quoted = false, escaped = false, opened = false
        var end = swiftRange.lowerBound
        while end < output.endIndex {
            let character = output[end]
            if quoted {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
            } else if character == "\"" { quoted = true }
            else if character == "{" { depth += 1; opened = true }
            else if character == "}" {
                depth -= 1
                if opened && depth == 0 { return String(output[swiftRange.lowerBound...end]) }
            }
            end = output.index(after: end)
        }
        return nil
    }
    static func plan(game: SteamGame, output: String) throws -> SteamDownloadPlan? {
        guard let block = appBlock(appID: game.id, in: output) else { return nil }
        var parser = SteamVDFParser(block)
        guard let app = try parser.parse()[String(game.id)] else { return nil }
        let launches = app["config"]?["launch"]?.object ?? [:]
        let candidates = launches.sorted { (Int($0.key) ?? Int.max) < (Int($1.key) ?? Int.max) }.compactMap { entry -> String? in
            let launch = entry.value
            let os = launch["config"]?["oslist"]?.text ?? "windows"
            guard os.split(separator:",").contains("windows"), let raw = launch["executable"]?.text else { return nil }
            return safeExecutable(raw)
        }
        guard let executable = candidates.first(where: { $0 == game.executable }) ?? candidates.first else {
            throw SteamDownloadError.message("Güvenli bir Windows .exe başlatıcısı bulunamadı. Oyunu elle indirip .exe ekleyebilirsiniz.")
        }
        var depots: [SteamDepot] = []
        for (id, depot) in app["depots"]?.object ?? [:] {
            guard UInt64(id).map({ $0 > 0 }) == true else { continue }
            let config = depot["config"]
            if let os = config?["oslist"]?.text, !os.split(separator: ",").contains("windows") { continue }
            if let arch = config?["osarch"]?.text, arch != "64" && arch != "32" { continue }
            if let language = config?["language"]?.text, language != "english" { continue }
            if depot["dlcappid"]?.text != nil { continue }
            guard depot["depotfromapp"]?.text == nil else {
                throw SteamDownloadError.message("Bu oyun ortak Steam paketi kullanıyor. Dosyaları elle indirip .exe bağlayın.")
            }
            guard let manifest = depot["manifests"]?["public"]?["gid"]?.text,
                  UInt64(manifest).map({ $0 > 0 }) == true else {
                throw SteamDownloadError.message("Windows paketinin public sürümü Steam'den alınamadı.")
            }
            depots.append(SteamDepot(id: id, manifest: manifest,
                diskBytes: UInt64(depot["manifests"]?["public"]?["size"]?.text ?? "0") ?? 0,
                downloadBytes: UInt64(depot["manifests"]?["public"]?["download"]?.text ?? "0") ?? 0))
        }
        guard !depots.isEmpty else { throw SteamDownloadError.message("Steam'de uygun Windows paketi bulunamadı.") }
        return SteamDownloadPlan(appID: game.id, depots: depots.sorted { $0.id < $1.id }, executable:executable, title:app["common"]?["name"]?.text)
    }
}

enum SteamDepotEvent: Equatable {
    case started, complete, failure(String)
    static func events(in output: String, appID: Int, depot: SteamDepot) -> [SteamDepotEvent] {
        output.components(separatedBy: .newlines).compactMap { line in
            if line.contains("Depot download complete"),
               line.replacingOccurrences(of: "\\", with: "/").contains("/app_\(appID)/depot_\(depot.id)\""),
               line.contains("manifest \(depot.manifest))") { return .complete }
            if line.contains("Downloading depot \(depot.id) (") { return .started }
            if line.contains("Depot download failed") {
                let lower = line.lowercased()
                return .failure(lower.contains("license") || lower.contains("subscription")
                    ? "Steam bu oyun için indirme lisansı vermedi. Doğru Steam hesabına giriş yapıp oyuna sahip olduğunuzu kontrol edin."
                    : "Steam indirmeyi tamamlayamadı. Steam konsolundaki hata ayrıntısını kontrol edin.")
            }
            return nil
        }
    }
}

struct SteamConsoleLines {
    private var pending = ""
    mutating func append(_ chunk: String) -> String {
        pending += chunk
        // Swift treats CRLF as one Character; looking for the LF Character alone misses Steam's log lines.
        guard let newline = pending.lastIndex(where: { $0.isNewline }) else { return "" }
        let result = String(pending[...newline])
        pending = String(pending[pending.index(after: newline)...])
        return result
    }
}

struct SteamLogCursor: Codable {
    var offset: UInt64
    var fileNumber: UInt64?
    init(url: URL) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        offset = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        fileNumber = (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value
    }
    mutating func read(url: URL) throws -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "" }
        let number = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        guard size >= offset, fileNumber == nil || fileNumber == number else {
            throw SteamDownloadError.message("Steam yeniden başlatıldı veya konsol kaydı yenilendi. İndirme düğmesine tekrar basın.")
        }
        fileNumber = number
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: 2_000_000) ?? Data()
        offset += UInt64(data.count)
        return String(decoding: data, as: UTF8.self)
    }
}

struct SteamDownloadJob: Codable {
    let gameID: Int
    let plan: SteamDownloadPlan
    var depotIndex: Int
    var cursor: SteamLogCursor
    var commandSent: Bool
}

struct SteamDownloadReceipt: Codable {
    let plan: SteamDownloadPlan
    let completedAt: Date
}
