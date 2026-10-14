// SPDX-License-Identifier: Apache-2.0
import Foundation

@main
struct RuntimeTests {
    static func main() throws {
        let clean = RuntimeConfiguration.cleanEnvironment(["HOME":"/tmp/home", "USER":"test", "API_SECRET":"secret",
            "WINEPREFIX":"/another-prefix", "VK_DRIVER_FILES":"/old-driver", "DYLD_INSERT_LIBRARIES":"/inject"])
        precondition(clean["HOME"] == "/tmp/home" && clean["API_SECRET"] == nil)
        precondition(clean["WINEPREFIX"] == nil && clean["VK_DRIVER_FILES"] == nil && clean["DYLD_INSERT_LIBRARIES"] == nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = RuntimeConfiguration.nativeRoot(root)
        let wine = runtime.appendingPathComponent("dist/bin/wine")
        let fex = runtime.appendingPathComponent("dist/lib/wine/aarch64-windows/libarm64ecfex.dll")
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fex.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xcf,0xfa,0xed,0xfe,0x0c,0,0,1]).write(to: wine)
        try FileManager.default.setAttributes([.posixPermissions:0o755], ofItemAtPath:wine.path)
        try Data([1]).write(to: fex)
        precondition(RuntimeConfiguration.nativeAvailable(root))
        let game = SteamGame.catalog[0]
        let plan = try RuntimeConfiguration.nativePlan(project: root, game: game,
            executable: URL(fileURLWithPath:"/game dir/Megabonk.exe"), hud:false, inherited:["HOME":"/home", "TOKEN":"secret"])
        precondition(plan.arguments == ["3405340", "/game dir/Megabonk.exe"])
        precondition(plan.environment["FEX_DISKCACHE"] == "1")
        precondition(plan.environment["TOKEN"] == nil && plan.environment["MTL_HUD_ENABLED"] == "0")
        precondition(plan.environment["DXMT_CONFIG"] == nil && plan.environment["VK_DRIVER_FILES"] == nil)
        precondition(plan.prefix.path.contains("bottles/native-arm64/3405340/pfx"))
        try Data([0xcf,0xfa,0xed,0xfe,0x07,0,0,1]).write(to: wine)
        precondition(!RuntimeConfiguration.nativeAvailable(root)) // x86-64 is never labelled native.
        print("Runtime architecture, isolation, cache settings and environment checks passed.")
    }
}
