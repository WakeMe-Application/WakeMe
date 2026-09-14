import ActivityKit
import Foundation

/// Live Activity(잠금화면·다이내믹 아일랜드) 데이터. 앱과 위젯 확장이 함께 컴파일한다.
/// 위젯 확장은 엔진을 링크하지 않으므로 필요한 값만 평평하게 담는다.
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case waiting, riding, prepare, alightNow, arrived
        }

        var phase: Phase
        /// "이번 역" — 다음 정차역, 정차 중이면 지금 역
        var currentStation: String
        var nextStation: String?
        var isDwelling: Bool
        var stopsRemaining: Int
        /// 출발 시각 — 진행 막대의 시작점
        var departedAt: Date?
        /// 목적지 도착 예정 — 카운트다운이 앱 갱신 없이도 흐른다
        var arrivalAt: Date?
        var isEstimated: Bool
    }

    var lineShortName: String
    var lineColorHex: String
    var directionName: String
    var origin: String
    var destination: String
}
