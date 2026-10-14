// SPDX-License-Identifier: Apache-2.0
import Foundation

@main
struct ProcessLogTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("game.log")
        let sink = try BoundedProcessLog(url:url,limit:4096)
        sink.append(Data(repeating:65,count:3000)); sink.append(Data(repeating:66,count:3000))
        sink.append(Data(repeating:67,count:10000))
        // Keeping a writer open must not make finish wait for EOF.
        let heldWriter = dup(sink.pipe.fileHandleForWriting.fileDescriptor)
        try sink.pipe.fileHandleForWriting.write(contentsOf:Data("tail\n".utf8))
        let start = ProcessInfo.processInfo.systemUptime
        sink.finish()
        sink.finish() // Idempotent termination, without accessing a closed descriptor.
        precondition(ProcessInfo.processInfo.systemUptime-start < 1)
        close(heldWriter)
        let data = try Data(contentsOf:url)
        precondition(data.count <= 4096)
        precondition(String(decoding:data,as:UTF8.self).hasSuffix("tail\n"))
        print("Bounded output, final tail and retained-writer checks passed.")
    }
}
