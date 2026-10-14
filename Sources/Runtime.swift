// SPDX-License-Identifier: Apache-2.0
import Foundation

enum MYTRuntime: String, CaseIterable, Identifiable, Codable {
    case nativeARM64
    case rosetta
    var id: String { rawValue }
    var name: String { self == .nativeARM64 ? "Yerel ARM64 · Deneysel" : "Önceki motor · Rosetta" }
    var cpuPath: String { self == .nativeARM64 ? "ARM64 Wine + FEX" : "x86-64 Wine + Rosetta" }
}

struct RuntimeLaunchPlan {
    let program: URL
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: URL
    let prefix: URL
    let cache: URL
}

enum RuntimeConfiguration {
    static let nativeVersion = "0.1.1"
    static func nativeRoot(_ project: URL) -> URL {
        project.appendingPathComponent("runtime/native-arm64/Hadron-\(nativeVersion).app/Contents/SharedSupport/runtime")
    }
    static func nativeAvailable(_ project: URL) -> Bool {
        let root = nativeRoot(project)
        guard FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("dist/bin/wine").path),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("dist/lib/wine/aarch64-windows/libarm64ecfex.dll").path) else { return false }
        return (try? MachOArchitecture.isARM64(root.appendingPathComponent("dist/bin/wine"))) == true
    }
    static func cleanEnvironment(_ inherited: [String: String]) -> [String: String] {
        var env: [String: String] = [:]
        for key in ["HOME", "USER", "LANG", "TMPDIR"] { env[key] = inherited[key] }
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        return env
    }
    static func nativePlan(project: URL, game: SteamGame, executable: URL, hud: Bool,
                           inherited: [String: String]) throws -> RuntimeLaunchPlan {
        guard nativeAvailable(project) else { throw SteamDownloadError.message("Yerel ARM64 motoru henüz kurulu değil.") }
        let prefix = project.appendingPathComponent("bottles/native-arm64/\(game.id)/pfx")
        let cache = project.appendingPathComponent("runtime/cache/native-\(nativeVersion)/\(game.id)")
        var env = cleanEnvironment(inherited)
        env["STEAM_COMPAT_DATA_PATH"] = prefix.deletingLastPathComponent().path
        env["STEAM_COMPAT_INSTALL_PATH"] = executable.deletingLastPathComponent().path
        env["STEAM_COMPAT_APP_ID"] = String(game.id)
        env["SteamAppId"] = String(game.id)
        env["SteamGameId"] = String(game.id)
        env["WINEDEBUG"] = "-all"
        env["FEX_DISKCACHE"] = "1"
        env["MTL_HUD_ENABLED"] = hud ? "1" : "0"
        env["DXMT_SHADER_CACHE_PATH"] = cache.appendingPathComponent("dxmt").path
        env["MESA_SHADER_CACHE_DIR"] = cache.appendingPathComponent("mesa").path
        env["DXMT_LOG_LEVEL"] = "error"
        // Leave rendering resolution, quality, vsync and CPU/GPU clock policy to the game/OS.
        var arguments = [String(game.id), executable.path]
        if game.id == 5165210 {
            let log = project.appendingPathComponent("logs/native/\(game.id)/godot.log")
            arguments += ["--print-fps", "--log-file", "Z:" + log.path.replacingOccurrences(of:"/",with:"\\")]
        }
        return RuntimeLaunchPlan(program: project.appendingPathComponent("scripts/native-game"),
            arguments: arguments, environment: env,
            workingDirectory: executable.deletingLastPathComponent(), prefix: prefix, cache: cache)
    }
}

enum MachOArchitecture {
    static func isARM64(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = Array(try handle.read(upToCount: 8) ?? Data())
        guard bytes.count == 8, Array(bytes[0..<4]) == [0xcf, 0xfa, 0xed, 0xfe] else { return false }
        let type = UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24
        return type == 0x0100000c
    }
}
