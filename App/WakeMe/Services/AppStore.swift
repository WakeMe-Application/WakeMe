import Foundation
import Observation
import WakeMeEngine

struct Routine: Codable, Identifiable, Hashable {
    var id = UUID()
    /// 예: "출근"
    var name: String
    var lineID: String
    var originID: String
    var destinationID: String
    var direction: Direction
}

struct RecentTrip: Codable, Hashable {
    var lineID: String
    var originID: String
    var destinationID: String
    var direction: Direction
    var date: Date
}

struct AppSettings: Codable, Hashable {
    /// 1차 알림: 목적지 N역 전 출발 시 (0이면 끔)
    var prepareStopsBefore = 2
    /// 2차 알림 앞당김(초)
    var alightEarlierBy: TimeInterval = 0
    var soundEnabled = true
    /// 잠금 중에도 전광판 갱신 (백그라운드 위치)
    var keepAliveEnabled = true
    /// 가속도계로 정차·출발을 감지해 위치를 자동 보정
    var autoDetectEnabled = true
    /// 사용자가 직접 넣은 인증키. 비어 있으면 앱에 내장된 기본 키를 쓴다.
    var realtimeKey = ""
    /// 실시간 열차위치로 위치 보정
    var realtimeEnabled = true
    /// 데모 모드 시간 배속
    var demoSpeed: Double = 1
    var hasOnboarded = false

    /// 실제로 호출에 쓸 인증키. 직접 넣은 키가 있으면 그것, 없으면 내장 키.
    var effectiveRealtimeKey: String {
        realtimeKey.isEmpty ? BuiltInKeys.realtimeSubway : realtimeKey
    }

    var alertPolicy: AlertPolicy {
        AlertPolicy(prepareStopsBefore: prepareStopsBefore, alightEarlierBy: alightEarlierBy)
    }
}

enum AlertTimingFeedback: String, Codable, CaseIterable, Identifiable {
    case tooEarly, justRight, tooLate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tooEarly: "일렀어요"
        case .justRight: "딱 좋았어요"
        case .tooLate: "늦었어요"
        }
    }
}

/// 알림 타이밍 피드백 — 성공 지표(기획서 9장)의 사용자 측 신호
struct TripFeedback: Codable, Hashable {
    var date: Date
    var lineID: String
    var originID: String
    var destinationID: String
    var stopCount: Int
    var timing: AlertTimingFeedback
}

/// 루틴·최근 경로·설정·피드백 저장소.
/// 데이터가 작아 SwiftData 대신 UserDefaults에 JSON으로 저장한다.
@MainActor
@Observable
final class AppStore {
    var routines: [Routine] { didSet { save(routines, for: Key.routines) } }
    private(set) var recents: [RecentTrip] { didSet { save(recents, for: Key.recents) } }
    var settings: AppSettings { didSet { save(settings, for: Key.settings) } }
    private(set) var feedback: [TripFeedback] { didSet { save(feedback, for: Key.feedback) } }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let routines = "routines.v1"
        static let recents = "recents.v1"
        static let settings = "settings.v1"
        static let feedback = "feedback.v1"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        routines = Self.load([Routine].self, from: defaults, key: Key.routines) ?? []
        recents = Self.load([RecentTrip].self, from: defaults, key: Key.recents) ?? []
        settings = Self.load(AppSettings.self, from: defaults, key: Key.settings) ?? AppSettings()
        feedback = Self.load([TripFeedback].self, from: defaults, key: Key.feedback) ?? []
    }

    func addRecent(_ trip: RecentTrip) {
        recents.removeAll {
            $0.lineID == trip.lineID && $0.originID == trip.originID && $0.destinationID == trip.destinationID
        }
        recents = Array(([trip] + recents).prefix(8))
    }

    func addFeedback(_ item: TripFeedback) {
        feedback.append(item)
    }

    /// 노선 데이터가 갱신되면 예전 역 코드를 가리키는 루틴·최근 경로가 남는다. 조용히 지운다.
    func prune(isKnown: (_ lineID: String, _ stationIDs: [String]) -> Bool) {
        routines.removeAll { !isKnown($0.lineID, [$0.originID, $0.destinationID]) }
        recents.removeAll { !isKnown($0.lineID, [$0.originID, $0.destinationID]) }
    }

    private func save<T: Encodable>(_ value: T, for key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
