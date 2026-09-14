import Foundation

/// 탑승 1회분 JSONL 파일.
/// 스레드 안전하지 않다 — SensorHub의 직렬 큐에서만 호출한다.
final class JSONLWriter {
    let url: URL
    private let handle: FileHandle
    private var buffer = Data()
    private var isClosed = false
    private let flushThreshold = 64 * 1024

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
        self.url = url
    }

    func append(_ line: LogLine) {
        // 종료 직후 도착한 센서 콜백은 버린다
        guard !isClosed else { return }
        buffer.append(Data(line.text.utf8))
        if buffer.count >= flushThreshold { flush() }
    }

    func flush() {
        guard !isClosed, !buffer.isEmpty else { return }
        try? handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    func close() {
        guard !isClosed else { return }
        flush()
        try? handle.synchronize()
        try? handle.close()
        isClosed = true
    }
}
