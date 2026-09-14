import Foundation

/// JSONL 한 줄. 센서 샘플이 초당 수십 개라 JSONEncoder 대신 문자열로 직접 조립한다.
struct LogLine: Sendable {
    private var parts: [String]

    /// - Parameters:
    ///   - type: 레코드 종류 (motion, pressure, location, mark, heartbeat …)
    ///   - t: Unix 시각(초)
    init(_ type: String, t: Double) {
        parts = ["\"type\":\"\(type)\"", "\"t\":\(Self.format(t, digits: 3))"]
    }

    mutating func add(_ key: String, _ value: Double, digits: Int = 4) {
        parts.append("\"\(key)\":\(Self.format(value, digits: digits))")
    }

    mutating func add(_ key: String, _ value: Int) {
        parts.append("\"\(key)\":\(value)")
    }

    mutating func add(_ key: String, _ value: Bool) {
        parts.append("\"\(key)\":\(value)")
    }

    mutating func add(_ key: String, _ value: String) {
        parts.append("\"\(key)\":\(Self.quote(value))")
    }

    var text: String { "{" + parts.joined(separator: ",") + "}\n" }

    static var now: Double { Date().timeIntervalSince1970 }

    private static func format(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return "null" }
        return String(format: "%.\(digits)f", value)
    }

    private static func quote(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
