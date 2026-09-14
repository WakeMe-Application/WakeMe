import Foundation

/// 하차 알림 시점 정책 (기획서 6장).
public struct AlertPolicy: Codable, Hashable, Sendable {
    /// 1차(준비) 알림: 목적지 N역 전을 출발할 때. 2 미만이면 끈다.
    public var prepareStopsBefore: Int
    /// 2차(하차) 알림을 전역 출발보다 앞당기는 시간(초)
    public var alightEarlierBy: TimeInterval

    public init(prepareStopsBefore: Int = 2, alightEarlierBy: TimeInterval = 0) {
        self.prepareStopsBefore = prepareStopsBefore
        self.alightEarlierBy = alightEarlierBy
    }
}

public struct TripAlert: Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        /// 1차 준비
        case prepare
        /// 2차 하차 — 문 열림 전 리드타임 확보
        case alightNow
        /// 3차 확인 — 목적지 도착
        case arrived
    }

    public let kind: Kind
    /// 출발역 출발 기준 발생 시점(초)
    public let offset: TimeInterval
}

extension Trip {
    /// 발생 순서대로 정렬된 알림 목록.
    public func alerts(policy: AlertPolicy) -> [TripAlert] {
        let dest = destinationIndex
        let alight = TripAlert(
            kind: .alightNow,
            offset: max(0, stops[dest - 1].departureOffset - policy.alightEarlierBy))

        var result: [TripAlert] = []
        let prepareIndex = dest - policy.prepareStopsBefore
        if policy.prepareStopsBefore >= 2, prepareIndex >= 0 {
            let offset = stops[prepareIndex].departureOffset
            if offset < alight.offset {
                result.append(TripAlert(kind: .prepare, offset: offset))
            }
        }
        result.append(alight)
        result.append(TripAlert(kind: .arrived, offset: stops[dest].arrivalOffset))
        return result
    }
}
