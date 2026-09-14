import Foundation

/// 탑승 로그 파일 위치와 목록.
/// Documents/rides 는 파일 앱의 "나의 iPhone > 깨워줘 로거"에서도 보인다 (UIFileSharingEnabled).
enum RideStore {
    struct RideFile: Identifiable, Hashable {
        let url: URL
        let size: Int
        let modified: Date
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    static var directory: URL {
        URL.documentsDirectory.appending(path: "rides", directoryHint: .isDirectory)
    }

    static func newFileURL(startedAt date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return directory.appending(path: "ride-\(formatter.string(from: date)).jsonl")
    }

    static func list() -> [RideFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls
            .filter { $0.pathExtension == "jsonl" }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return RideFile(
                    url: url,
                    size: values?.fileSize ?? 0,
                    modified: values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }
    }

    static func delete(_ file: RideFile) {
        try? FileManager.default.removeItem(at: file.url)
    }
}
