// SPDX-License-Identifier: Apache-2.0
import Foundation

@main
struct GameFilesTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root, withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        let exe = root.appendingPathComponent("game.exe")
        var bytes = Data(repeating:0, count:134); bytes[0] = 0x4d; bytes[1] = 0x5a; bytes[60] = 128
        bytes.replaceSubrange(128..<134, with:[0x50,0x45,0,0,0x64,0x86])
        try bytes.write(to:exe); precondition(WindowsExecutable.isSupported(exe))
        bytes[132] = 0x4c; bytes[133] = 0x01
        try bytes.write(to:exe); precondition(WindowsExecutable.isSupported(exe))
        bytes[132] = 0x64; bytes[133] = 0xaa
        try bytes.write(to:exe); precondition(!WindowsExecutable.isSupported(exe))
        try Data([0x4d,0x5a]).write(to:exe); precondition(!WindowsExecutable.isSupported(exe))
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b"), output = root.appendingPathComponent("game")
        for url in [a,b] { try fm.createDirectory(at:url, withIntermediateDirectories:true) }
        try Data("same".utf8).write(to:a.appendingPathComponent("shared"))
        try Data("same".utf8).write(to:b.appendingPathComponent("shared"))
        try Data("asset".utf8).write(to:b.appendingPathComponent("asset"))
        try DepotAssembler.assemble([a,b], into:output)
        let asset = try String(contentsOf:output.appendingPathComponent("asset"), encoding:.utf8); precondition(asset == "asset")
        try Data("conflict".utf8).write(to:b.appendingPathComponent("shared"))
        var rejected = false
        do { try DepotAssembler.assemble([a,b], into:output) } catch { rejected = true }
        precondition(rejected)
        let shared = try String(contentsOf:output.appendingPathComponent("shared"), encoding:.utf8); precondition(shared == "same")
        try fm.removeItem(at:b.appendingPathComponent("shared"))
        try fm.createSymbolicLink(at:b.appendingPathComponent("escape"), withDestinationURL:exe)
        rejected = false
        do { try DepotAssembler.assemble([a,b], into:output) } catch { rejected = true }
        precondition(rejected)
        print("PE validation, multi-depot merge, conflict rollback and symlink rejection passed.")
    }
}
