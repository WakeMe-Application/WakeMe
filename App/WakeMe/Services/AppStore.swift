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

/// 피드백이 알림 시점을 옮긴 기록
struct TimingAdjustment: Codable, Hashable {
    var date: Date
    /// 초. 양수면 알림을 그만큼 앞당겼다는 뜻이다.
    var delta: TimeInterval
    var resulting: TimeInterval
}

struct AppSettings: Codable, Hashable {
    /// 1차 알림: 목적지 N역 전 출발 시 (0이면 끔)
    var prepareStopsBefore = 2
    /// 2차 알림 앞당김(초)
    var alightEarlierBy: TimeInterval = 0
    var soundEnabled = true
    /// 이어폰으로 음성 안내. 노이즈캔슬링·수면 상황에서 진동보다 확실하다.
    var voiceEnabled = true
    /// 2차 하차 알림을 시스템 알람으로도 건다. 무음·집중 모드를 뚫는다.
    var alarmEnabled = true
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
    /// 피드백으로 `alightEarlierBy`를 마지막으로 옮긴 시각·폭. 설정 화면에 그대로 보여 준다.
    var lastTimingAdjustment: TimingAdjustment?

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

    /// 한 번에 옮기는 폭과 한계. 60초를 넘겨 앞당기면 엉뚱한 역에서 일어나게 된다.
    static let timingStep: TimeInterval = 30
    static let timingLimit: TimeInterval = 120

    func addFeedback(_ item: TripFeedback) {
        feedback.append(item)
        adjustAlertTiming()
    }

    /// ArrivalView가 "알려주시면 알림 시점을 더 정확하게 맞출게요"라고 약속한다.
    /// 그 약속을 지키는 곳이 여기다.
    ///
    /// 한 번의 응답으로는 바꾸지 않는다 — 그날 유난히 붐볐던 것과 실제 편향을 못 가른다.
    /// **마지막 보정 이후** 쌓인 응답이 3개 이상이고, 그 가운데 한쪽이 2개 이상이면서
    /// 반대쪽이 하나도 없을 때만 30초 옮긴다.
    ///
    /// 경로별이 아니라 전체로 본다. 문까지 걸리는 시간은 노선보다 사람과 혼잡도에 달려 있고,
    /// 경로별로 나누면 표본이 모이지 않는다.
    private func adjustAlertTiming() {
        let since = settings.lastTimingAdjustment?.date ?? .distantPast
        let recent = feedback.filter { $0.date > since }
        guard recent.count >= 3 else { return }

        let late = recent.filter { $0.timing == .tooLate }.count
        let early = recent.filter { $0.timing == .tooEarly }.count
        let delta: TimeInterval
        if late >= 2, early == 0 { delta = Self.timingStep }        // 늦었다 → 앞당긴다
        else if early >= 2, late == 0 { delta = -Self.timingStep }  // 일렀다 → 늦춘다
        else { return }

        let adjusted = min(max(settings.alightEarlierBy + delta, 0), Self.timingLimit)
        guard adjusted != settings.alightEarlierBy else { return }
        settings.alightEarlierBy = adjusted
        settings.lastTimingAdjustment = TimingAdjustment(
            date: .now, delta: delta, resulting: adjusted)
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
