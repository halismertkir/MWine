// SPDX-License-Identifier: Apache-2.0
import AppKit

@main
struct DownloadCLI {
    @MainActor
    static func main() async {
        guard CommandLine.arguments.count == 2, let game = try? SteamGame.imported(CommandLine.arguments[1]) else {
            print("Kullanım: mwine-download <Steam-App-ID-veya-mağaza-bağlantısı>")
            exit(2)
        }
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let root = binary.deletingLastPathComponent().deletingLastPathComponent()
        let downloads = SteamDownloader(root: root)
        try? downloads.add(String(game.id))
        if !downloads.busy { downloads.start(game) }
        var last = ""
        while downloads.busy {
            if last != downloads.status { last = downloads.status; print(last); fflush(stdout) }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        print(downloads.status)
        exit(downloads.hasError ? 1 : 0)
    }
}
