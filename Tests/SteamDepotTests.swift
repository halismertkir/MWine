// SPDX-License-Identifier: Apache-2.0
import Foundation

@main
struct SteamDepotTests {
    static func main() throws {
        let game = SteamGame.catalog[0]
        let metadata = """
        "3405340"
        {
            "config" { "launch" { "0" { "executable" "Megabonk.exe" "config" { "oslist" "windows" } } } }
            "depots" {
                "3405342" { "config" { "oslist" "windows" } "manifests" { "public" { "gid" "446680890915713051" "size" "522734781" "download" "179240512" } } }
                "3405341" { "config" { "oslist" "linux" } "manifests" { "public" { "gid" "6464790072963772385" } } }
            }
        }
        """
        let plan = try SteamMetadata.plan(game: game, output: metadata)!
        precondition(plan.depots.count == 1 && plan.depots[0].id == "3405342")
        let timestamped = try SteamMetadata.plan(game: game, output: "[2026-10-10 17:02:00] " + metadata)
        precondition(timestamped == plan)
        precondition(plan.downloadBytes == 179240512 && plan.diskBytes == 522734781)
        precondition(plan.arguments(for: plan.depots[0]) == ["-console", "+download_depot", "3405340", "3405342", "446680890915713051"])
        let partial = try SteamMetadata.plan(game: game, output: String(metadata.dropLast()))
        let latestPartial = try SteamMetadata.plan(game: game, output: metadata + "\n\"3405340\"\n{")
        precondition(partial == nil && latestPartial == nil)
        func rejects(_ input: String) throws {
            var rejected = false
            do { _ = try SteamMetadata.plan(game: game, output: input) } catch { rejected = true }
            precondition(rejected)
        }
        try rejects(metadata.replacingOccurrences(of: "446680890915713051", with: "1;quit"))
        try rejects(metadata.replacingOccurrences(of: "Megabonk.exe", with: "../evil.exe"))
        try rejects(metadata.replacingOccurrences(of: "\"3405342\" {", with: "\"3405342\" { \"depotfromapp\" \"228980\""))
        var escapes = SteamVDFParser(#""root" { "path" "C:\\Game\\a.exe" "quote" "a\"{b}" }"#)
        let parsed = try escapes.parse()
        precondition(parsed["root"]?["path"]?.text == #"C:\Game\a.exe"#)
        precondition(parsed["root"]?["quote"]?.text == "a\"{b}")
        let imported = try SteamGame.imported("https://store.steampowered.com/app/123456/Example/")
        precondition(imported.id == 123456 && imported.executable.isEmpty)
        let arbitrary = SteamGame(id:3405340, name:"Test", executable:"", usesDXMT:false)
        let multiple = metadata.replacingOccurrences(of:"\"3405341\"", with:"\"3405343\"").replacingOccurrences(of:"\"linux\"", with:"\"windows\"")
        let multiPlan = try SteamMetadata.plan(game:arbitrary, output:multiple)!
        precondition(multiPlan.depots.count == 2 && multiPlan.executable == "Megabonk.exe")
        precondition(SteamMetadata.safeExecutable("bin\\game.exe") == "bin/game.exe")
        for path in ["../a.exe", "/a.exe", "C:\\a.exe", "a/../../b.exe", "a.exe\0"] { precondition(SteamMetadata.safeExecutable(path) == nil) }
        let depot = plan.depots[0]
        let success = "Depot download complete : \"/Steam/Contents/MacOS\\steamapps\\content\\app_3405340\\depot_3405342\" (manifest 446680890915713051)\n"
        precondition(SteamDepotEvent.events(in: success, appID: game.id, depot: depot) == [.complete])
        var lines = SteamConsoleLines()
        precondition(lines.append(String(success.dropLast())).isEmpty)
        let crlf = lines.append("\r\n")
        precondition(SteamDepotEvent.events(in: crlf, appID: game.id, depot: depot) == [.complete])
        precondition(SteamDepotEvent.events(in: success.replacingOccurrences(of: "app_3405340", with: "app_9"), appID: game.id, depot: depot).isEmpty)
        precondition(SteamDepotEvent.events(in: success.replacingOccurrences(of: depot.manifest, with: "123"), appID: game.id, depot: depot).isEmpty)
        precondition(SteamDepotEvent.events(in: "Downloading depot 3405342 (27 files, 170 MB) ...", appID: game.id, depot: depot) == [.started])
        let denial = SteamDepotEvent.events(in: "Depot download failed : No subscription", appID: game.id, depot: depot)
        precondition(denial.count == 1)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let log = temporary.appendingPathComponent("console.txt")
        try Data(success.utf8).write(to: log)
        var cursor = SteamLogCursor(url: log)
        let old = try cursor.read(url: log)
        precondition(old.isEmpty) // An old completion must not complete a fresh request.
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("new output\n".utf8)); try handle.close()
        let appended = try cursor.read(url: log)
        precondition(appended == "new output\n")
        try Data("rotated".utf8).write(to: log, options: .atomic)
        var rotated = false
        do { _ = try cursor.read(url: log) } catch { rotated = true }
        precondition(rotated)
        print("Steam metadata, platform filtering, fresh completion, errors, and log rotation checks passed.")
    }
}
