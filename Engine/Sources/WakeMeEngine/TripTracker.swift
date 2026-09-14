import Foundation

public enum TripPhase: String, Codable, Hashable, Sendable {
    /// 승강장 대기 — 아직 출발 전
    case waiting
    /// 추적 중
    case riding
    /// 1차 준비 알림 이후
    case prepare
    /// 2차 하차 알림 이후 — 다음 역에서 내려야 함
    case alightNow
    /// 목적지 도착
    case arrived
}

public enum PositionConfidence: String, Codable, Hashable, Sendable {
    /// 최근에 출발·보정·센서로 위치가 확정됨
    case anchored
    /// 시간 모델만으로 여러 역을 지나 추정 오차가 커졌을 수 있음
    case estimated
}

public struct TripSnapshot: Hashable, Sendable {
    public let phase: TripPhase
    /// "이번 역" — 다음 정차역, 정차 중이면 지금 역 (`trip.stops` 인덱스)
    public let currentIndex: Int
    public let isDwelling: Bool
    /// 목적지까지 남은 정거장 수
    public let stopsRemaining: Int
    /// 목적지 도착까지 남은 실제 시간(초)
    public let secondsToArrival: TimeInterval
    /// 0...1
    public let progress: Double
    public let confidence: PositionConfidence
}

public struct ScheduledAlert: Hashable, Sendable {
    public let alert: TripAlert
    public let date: Date
}

/// 시간 모델 기반 위치 추적기.
/// 출발 시각(또는 보정 시각)을 기준으로 역간 소요시간을 따라가며, 정차 감지 같은 센서 관측은
/// 이후 `correct(arrivedAt:at:)`와 같은 형태로 시계를 재설정하는 방식으로 붙인다.
public struct TripTracker: Hashable, Sendable {
    /// 앵커 이후 이만큼 역을 지나면 추정 상태로 표시한다
    public static let estimatedAfterStops = 3

    public let trip: Trip
    public var policy: AlertPolicy
    /// 1이면 실시간. 데모 모드에서 시간을 빠르게 흘린다.
    public let timeScale: Double
    /// 출발역을 출발한(것으로 보정된) 시각
    public private(set) var departedAt: Date?
    /// 마지막으로 위치가 확정된 역 인덱스
    public private(set) var anchorIndex = 0

    public init(trip: Trip, policy: AlertPolicy = AlertPolicy(), timeScale: Double = 1) {
        self.trip = trip
        self.policy = policy
        self.timeScale = timeScale
    }

    public mutating func depart(at date: Date) {
        departedAt = date
        anchorIndex = 0
    }

    /// 사용자가 "지금 이 역에 정차 중"이라고 알려주면 그 역 도착 시각에 시계를 맞춘다.
    public mutating func correct(arrivedAt index: Int, at date: Date) {
        guard trip.stops.indices.contains(index) else { return }
        guard index > 0 else { return depart(at: date) }
        departedAt = date.addingTimeInterval(-trip.stops[index].arrivalOffset / timeScale)
        anchorIndex = index
    }

    /// 센서가 감지한 정차·출발을 반영한다.
    /// 시간 모델이 예상한 시각과 너무 동떨어진 정차(터널 신호대기 등)는 무시한다.
    /// - Returns: 시계를 다시 맞췄으면 true
    @discardableResult
    public mutating func observe(_ event: MotionEvent, tolerance: TimeInterval = 120) -> Bool {
        switch event {
        case .departed(let date):
            // 아직 출발 전이면 이게 탑승 시점이다
            guard departedAt == nil else { return false }
            depart(at: date)
            return true

        case .stopped(let date):
            guard departedAt != nil else { return false }
            let running = snapshot(at: date).currentIndex
            // 열차가 늦으면 시간 모델은 이미 다음 역으로 향하는 중이다.
            // 늦게 도착한 직전 역인지, 일찍 도착한 다음 역인지 예상 시각이 가까운 쪽을 고른다.
            let candidates = [running - 1, running].filter { $0 >= 1 && $0 <= trip.destinationIndex }
            guard let candidate = candidates.min(by: { gap(to: $0, at: date) < gap(to: $1, at: date) }),
                  gap(to: candidate, at: date) <= tolerance
            else { return false }

            // 직전 역을 떠난 지 얼마 되지 않았는데 멈췄다면 역이 아니라 신호대기로 본다
            let departure = trip.stops[candidate - 1].departureOffset
            let run = trip.stops[candidate].arrivalOffset - departure
            guard let earliest = self.date(atOffset: departure + run / 2), date >= earliest else {
                return false
            }
            correct(arrivedAt: candidate, at: date)
            return true
        }
    }

    /// 실시간 열차 정보처럼 **역을 특정할 수 있는** 관측을 반영한다.
    /// 가속도계와 달리 어느 역인지 알기 때문에 시각 대신 역으로 바로 맞춘다.
    /// - Returns: 시계를 다시 맞췄으면 true
    @discardableResult
    public mutating func observe(arrivedAt stationID: String, at date: Date) -> Bool {
        guard departedAt != nil,
              let index = trip.stops.firstIndex(where: { $0.station.id == stationID }),
              index > 0
        else { return false }
        correct(arrivedAt: index, at: date)
        return true
    }

    /// 그 역에 도착할 것으로 본 시각과 실제 감지 시각의 차이
    private func gap(to index: Int, at date: Date) -> TimeInterval {
        guard let expected = self.date(atOffset: trip.stops[index].arrivalOffset) else { return .infinity }
        return abs(date.timeIntervalSince(expected))
    }

    public func elapsed(at date: Date) -> TimeInterval? {
        departedAt.map { date.timeIntervalSince($0) * timeScale }
    }

    public func date(atOffset offset: TimeInterval) -> Date? {
        departedAt.map { $0.addingTimeInterval(offset / timeScale) }
    }

    public var arrivalDate: Date? { date(atOffset: trip.duration) }

    /// 알림 예약용 — 실제 시각으로 변환된 알림 목록
    public var scheduledAlerts: [ScheduledAlert] {
        trip.alerts(policy: policy).compactMap { alert in
            date(atOffset: alert.offset).map { ScheduledAlert(alert: alert, date: $0) }
        }
    }

    public func snapshot(at date: Date) -> TripSnapshot {
        let dest = trip.destinationIndex
        guard let elapsed = elapsed(at: date) else {
            return TripSnapshot(
                phase: .waiting, currentIndex: 0, isDwelling: true, stopsRemaining: dest,
                secondsToArrival: trip.duration / timeScale, progress: 0, confidence: .anchored)
        }

        var current = dest
        var dwelling = true
        for i in 1...dest {
            if elapsed < trip.stops[i].arrivalOffset {
                current = i
                dwelling = false
                break
            }
            if elapsed < trip.stops[i].departureOffset {
                current = i
                break
            }
        }

        let passedStop = dwelling ? current : current - 1
        return TripSnapshot(
            phase: Self.phase(elapsed: elapsed, alerts: trip.alerts(policy: policy)),
            currentIndex: current,
            isDwelling: dwelling,
            stopsRemaining: dwelling ? dest - current : dest - current + 1,
            secondsToArrival: max(0, trip.duration - elapsed) / timeScale,
            progress: min(1, max(0, elapsed / trip.duration)),
            confidence: passedStop - anchorIndex >= Self.estimatedAfterStops ? .estimated : .anchored)
    }

    static func phase(elapsed: TimeInterval, alerts: [TripAlert]) -> TripPhase {
        var phase = TripPhase.riding
        for alert in alerts where elapsed >= alert.offset {
            switch alert.kind {
            case .prepare: phase = .prepare
            case .alightNow: phase = .alightNow
            case .arrived: phase = .arrived
            }
        }
        return phase
    }
}
