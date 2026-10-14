// SPDX-License-Identifier: Apache-2.0
import Foundation

enum Workspace {
    static func prepare(bundle:Bundle = .main) throws -> URL {
        let fm = FileManager.default
        guard let payload = bundle.resourceURL?.appendingPathComponent("payload"), fm.fileExists(atPath:payload.path) else {
            throw SteamDownloadError.message("Uygulama kaynakları eksik. scripts/build-app ile yeniden derleyin.")
        }
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MWine")
        try fm.createDirectory(at:root, withIntermediateDirectories:true)
        // Only application resources are updated; installed engines, prefixes, games and saves stay separate.
        for name in ["scripts","Sources","Patches","EngineConfig","LICENSE","NOTICE","THIRD_PARTY_NOTICES.md"] {
            let source = payload.appendingPathComponent(name), target = root.appendingPathComponent(name)
            guard fm.fileExists(atPath:source.path) else { continue }
            if fm.fileExists(atPath:target.path) { try fm.removeItem(at:target) }
            try fm.copyItem(at:source, to:target)
        }
        try fm.createDirectory(at:root.appendingPathComponent("build"), withIntermediateDirectories:true)
        let probe = bundle.bundleURL.appendingPathComponent("Contents/Helpers/mwine-metal-probe")
        let target = root.appendingPathComponent("build/myt-metal-probe")
        if fm.fileExists(atPath:target.path) { try fm.removeItem(at:target) }
        try fm.copyItem(at:probe, to:target)
        return root
    }
}
