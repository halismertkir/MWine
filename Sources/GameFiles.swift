// SPDX-License-Identifier: Apache-2.0
import Foundation
import CryptoKit
import Darwin

enum WindowsExecutable {
    static func isSupported(_ url:URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom:url) else { return false }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount:64), header.count == 64, header[0] == 0x4d, header[1] == 0x5a else { return false }
        let offset = (0..<4).reduce(UInt64(0)) { $0 | UInt64(header[60+$1]) << (8*$1) }
        guard offset >= 64, offset < 16_000_000 else { return false }
        do {
            try file.seek(toOffset:offset)
            let pe = try file.read(upToCount:6) ?? Data()
            guard pe.count == 6, Array(pe.prefix(4)) == [0x50,0x45,0,0] else { return false }
            let machine = UInt16(pe[4]) | UInt16(pe[5]) << 8
            return machine == 0x8664 || machine == 0x014c
        } catch { return false }
    }
}

enum DepotAssembler {
    private static func digest(_ url:URL) throws -> SHA256.Digest {
        let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount:1_048_576), !data.isEmpty { hash.update(data:data) }
        return hash.finalize()
    }
    static func assemble(_ directories:[URL], into destination:URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at:destination.deletingLastPathComponent(), withIntermediateDirectories:true)
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".merge-" + UUID().uuidString)
        try fm.createDirectory(at:stage, withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:stage) }
        for directory in directories {
            let sourceRoot = directory.standardizedFileURL.resolvingSymlinksInPath()
            var traversalError:Error?
            guard let enumerator = fm.enumerator(at:sourceRoot, includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey,.isRegularFileKey], options:[], errorHandler:{ _, error in traversalError = error; return false }) else {
                throw SteamDownloadError.message("Paket okunamıyor.")
            }
            for case let listed as URL in enumerator {
                let source = listed.standardizedFileURL
                let flags = try source.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey,.isRegularFileKey])
                guard flags.isSymbolicLink != true else { throw SteamDownloadError.message("Paket sembolik bağlantı içeriyor; güvenli birleştirme durduruldu.") }
                let base = sourceRoot.path.hasSuffix("/") ? sourceRoot.path : sourceRoot.path + "/"
                guard source.path.hasPrefix(base) else { throw SteamDownloadError.message("Paket yolu kök dışında.") }
                let relative = String(source.path.dropFirst(base.count))
                let target = stage.appendingPathComponent(relative)
                guard target.standardizedFileURL.path.hasPrefix(stage.path + "/") else { throw SteamDownloadError.message("Paket yolu geçersiz.") }
                if flags.isDirectory == true { try fm.createDirectory(at:target, withIntermediateDirectories:true); continue }
                guard flags.isRegularFile == true else { throw SteamDownloadError.message("Desteklenmeyen paket dosyası.") }
                try fm.createDirectory(at:target.deletingLastPathComponent(), withIntermediateDirectories:true)
                if fm.fileExists(atPath:target.path) {
                    guard try digest(source) == digest(target) else { throw SteamDownloadError.message("Paketlerde çakışan dosya var: \(relative). Elle kurulum gerekiyor.") }
                } else if clonefile(source.path, target.path, 0) != 0 { try fm.copyItem(at:source, to:target) }
            }
            if let traversalError { throw traversalError }
        }
        // Do not overwrite an existing game tree or its saves on a failed merge.
        if fm.fileExists(atPath:destination.path) {
            let backup = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".previous-" + UUID().uuidString)
            try fm.moveItem(at:destination, to:backup)
            do { try fm.moveItem(at:stage, to:destination) }
            catch { try? fm.moveItem(at:backup, to:destination); throw error }
            // Keep old files (including any game-local saves) for manual recovery.
        } else { try fm.moveItem(at:stage, to:destination) }
    }
}
