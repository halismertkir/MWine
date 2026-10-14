// SPDX-License-Identifier: Apache-2.0
import Foundation
import Darwin

// A runaway renderer error must not fill the disk. Reading the pipe also prevents
// its backpressure from blocking a game's rendering thread.
final class BoundedProcessLog: @unchecked Sendable {
    let pipe = Pipe()
    private let handle: FileHandle
    private let lock = NSLock()
    private let limit: Int
    private var written = 0
    private var closed = false
    private let queue = DispatchQueue(label: "local.myt.process-log")
    private let reader: DispatchSourceRead
    init(url: URL, limit: Int) throws {
        self.limit = limit
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        let input = pipe.fileHandleForReading
        let flags = fcntl(input.fileDescriptor, F_GETFL)
        _ = fcntl(input.fileDescriptor, F_SETFL, flags | O_NONBLOCK)
        reader = DispatchSource.makeReadSource(fileDescriptor: input.fileDescriptor, queue: queue)
        reader.setEventHandler { [weak self] in self?.drain() }
        reader.setCancelHandler { try? input.close() }
        reader.resume()
    }
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        do {
            if written + data.count > limit {
                try handle.truncate(atOffset: 0); try handle.seek(toOffset: 0); written = 0
            }
            let retained = data.suffix(limit)
            try handle.write(contentsOf: retained); written += retained.count
        } catch { /* Keep draining the pipe if disk writes fail. */ }
    }
    private func drain() {
        // Read only bytes currently buffered. A Wine service retaining a writer
        // must not block a frame or the process termination callback.
        let fd = pipe.fileHandleForReading.fileDescriptor
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            append(Data(buffer.prefix(count)))
        }
    }
    func finish() {
        queue.sync {
            lock.lock(); let alreadyClosed = closed; lock.unlock()
            if alreadyClosed { return }
            drain()
            lock.lock(); defer { lock.unlock() }
            if !closed { closed = true; try? handle.close(); reader.cancel(); try? pipe.fileHandleForWriting.close() }
        }
    }
    deinit { reader.cancel(); try? pipe.fileHandleForWriting.close(); try? handle.close() }
}
