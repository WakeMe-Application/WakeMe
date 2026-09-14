import Foundation
import Observation
import WakeMeEngine

/// 탑승 1회. 환승이 있으면 구간(leg)을 하나씩 넘어가며 추적한다.
/// 추적기·Live Activity·알림 예약·백그라운드 유지·센서·실시간 정보를 한데 묶는다.
@MainActor
@Observable
final class TripSession: Identifiable {
    let id = UUID()
    let journey: Journey
    /// 구간별 노선 (journey.legs와 같은 순서)
    let lines: [SubwayLine]

    private(set) var legIndex = 0
    /// 현재 구간의 노선. 급행·완행을 갈아타면 바뀐다.
    private(set) var line: SubwayLine
    private(set) var tracker: TripTracker
    private(set) var snapshot: TripSnapshot
    /// 1초마다 갱신 — 카운트다운 표시용
    private(set) var now = Date()
    private(set) var alightedAt: Date?
    /// 센서가 위치를 마지막으로 맞춘 시각
    private(set) var lastAutoDetection: Date?
    /// 실시간 열차 정보로 위치를 마지막으로 맞춘 시각
    private(set) var lastRealtimeSync: Date?
    /// 실시간으로 받은 탑승 열차의 마지막 위치 (표시용 — 보정과 달리 도착이 아닌 상태도 담는다)
    private(set) var livePosition: TrainPosition?
    /// 급행·완행 계통을 바꾼 시각
    private(set) var lastServiceSwitch: (date: Date, isExpress: Bool)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let variants: [SubwayLine]
    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private let keepAlive: LocationKeepAlive?
    @ObservationIgnored private var motion: MotionMonitor?
    @ObservationIgnored private var realtime: RealtimeTracker?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// - Parameter variants: 첫 구간 노선의 다른 운행 계통 (급행 ↔ 완행 전환)
    init(journey: Journey, lines: [SubwayLine], settings: AppSettings, variants: [SubwayLine] = []) {
        self.journey = journey
        self.lines = lines
        self.settings = settings
        self.variants = variants
        line = lines[0]
        let tracker = TripTracker(
            trip: journey.legs[0].trip, policy: settings.alertPolicy, timeScale: settings.demoSpeed)
        self.tracker = tracker
        snapshot = tracker.snapshot(at: .now)
        keepAlive = settings.keepAliveEnabled ? LocationKeepAlive() : nil

        if settings.autoDetectEnabled {
            motion = MotionMonitor { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
        }
        rebuildRealtime()
    }

    // MARK: - 상태

    var trip: Trip { tracker.trip }
    var hasDeparted: Bool { tracker.departedAt != nil }
    var arrivalDate: Date? { tracker.arrivalDate }
    var directionName: String { line.directionName(trip.direction) }
    var currentStop: Trip.Stop { trip.stops[snapshot.currentIndex] }
    var isLastLeg: Bool { legIndex == journey.legs.count - 1 }
    var finalDestination: Station { journey.destination }
    var nextLine: SubwayLine? { isLastLeg ? nil : lines[legIndex + 1] }
    /// 환승역에 도착해 다음 열차를 기다리는 상태
    var isTransferPending: Bool { snapshot.phase == .arrived && !isLastLeg }
    var isAutoDetecting: Bool { motion?.isAvailable == true }

    var previousStop: Trip.Stop? {
        let index = snapshot.currentIndex - 1
        return index >= 0 && hasDeparted ? trip.stops[index] : nil
    }

    var nextStop: Trip.Stop? {
        let index = snapshot.currentIndex + 1
        return trip.stops.indices.contains(index) ? trip.stops[index] : nil
    }

    var rideDuration: TimeInterval? {
        guard let start = tracker.departedAt else { return nil }
        return (alightedAt ?? now).timeIntervalSince(start)
    }

    // MARK: - 진행

    /// 탑승 화면이 뜰 때 — Live Activity와 백그라운드 유지를 시작한다
    func begin() {
        keepAlive?.start()
        motion?.start()
        realtime?.start()
        liveActivity.start(activityAttributes, state: activityState)
        startTicking()
    }

    /// 열차 출발 (버튼, 또는 센서·실시간 정보가 대신한다)
    func depart(at date: Date = .now) {
        tracker.depart(at: date)
        refresh()
        reschedule()
    }

    /// "지금 이 역이에요" 보정
    func correct(arrivedAt index: Int) {
        tracker.correct(arrivedAt: index, at: .now)
        refresh()
        reschedule()
    }

    /// 환승역에서 다음 열차에 탔을 때
    func advanceToNextLeg() {
        guard !isLastLeg else { return }
        legIndex += 1
        line = lines[legIndex]
        tracker = TripTracker(
            trip: journey.legs[legIndex].trip, policy: settings.alertPolicy, timeScale: settings.demoSpeed)
        rebuildRealtime()
        realtime?.start()
        refresh()
        reschedule()
    }

    func confirmAlighted() {
        alightedAt = .now
        stopServices()
        liveActivity.end(after: 5)
    }

    func end() {
        stopServices()
        liveActivity.endImmediately()
    }

    // MARK: - 관측

    /// 가속도계가 감지한 정차·출발
    private func handle(_ event: MotionEvent) {
        guard tracker.observe(event) else { return }
        lastAutoDetection = .now
        refresh()
        reschedule()
    }

#if DEBUG
    /// 스크린샷·디버그용. 네트워크 없이 실시간 표시를 확인하려고 둔다.
    func injectLivePosition(_ position: TrainPosition) { livePosition = position }
#endif

    /// 실시간 열차위치를 쓸 수 있는 상태인지 (설정이 켜져 있고, API가 주는 노선이고)
    var isRealtimeAvailable: Bool {
        settings.realtimeEnabled && TrainPositionAPI.apiLineName(forLineID: line.id) != nil
    }

    /// 실시간 열차 정보. 역을 특정할 수 있어 시간 모델보다 우선하고, 급행 여부도 함께 본다.
    private func handleRealtime(_ position: TrainPosition) {
        // 위치 보정은 '도착'일 때만 하지만, 화면에는 진입·출발도 그대로 보여 준다
        livePosition = position
        if position.isExpress != line.name.contains("급행") {
            switchService(toExpress: position.isExpress, at: position.stationName)
        }
        guard position.status == .arrived else { return }

        let target = RealtimeTracker.normalize(position.stationName)
        guard let stop = trip.stops.first(where: { RealtimeTracker.normalize($0.station.name) == target }),
              tracker.observe(arrivedAt: stop.station.id, at: position.receivedAt)
        else { return }
        lastRealtimeSync = .now
        refresh()
        reschedule()
    }

    /// 탄 열차가 급행(또는 완행)이면 그 계통으로 경로를 다시 짠다
    private func switchService(toExpress: Bool, at stationName: String) {
        let target = RealtimeTracker.normalize(stationName)
        guard let candidate = variants.first(where: { $0.name.contains("급행") == toExpress && $0.id != line.id }),
              let from = candidate.stations.first(where: { RealtimeTracker.normalize($0.name) == target }),
              let to = candidate.station(named: trip.destination.name),
              let newTrip = try? TripPlanner.plan(on: candidate, from: from.id, to: to.id)
        else { return }

        line = candidate
        var replaced = TripTracker(trip: newTrip, policy: settings.alertPolicy, timeScale: settings.demoSpeed)
        replaced.depart(at: .now)  // 지금 이 역을 출발하는 것으로 본다
        tracker = replaced
        lastServiceSwitch = (.now, toExpress)
        refresh()
        reschedule()
    }

    // MARK: - Private

    private func rebuildRealtime() {
        realtime?.stop()
        guard settings.realtimeEnabled else { return }
        realtime = RealtimeTracker(
            key: settings.effectiveRealtimeKey,
            lineID: line.id,
            stationNames: trip.stops.map(\.station.name)
        ) { [weak self] position in
            self?.handleRealtime(position)
        }
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    private func stopServices() {
        ticker?.cancel()
        ticker = nil
        keepAlive?.stop()
        motion?.stop()
        realtime?.stop()
        NotificationScheduler.cancelAll()
    }

    private func refresh() {
        now = .now
        snapshot = tracker.snapshot(at: now)
        realtime?.expectedStation = currentStop.station.name
        liveActivity.update(activityState)
    }

    private func reschedule() {
        NotificationScheduler.schedule(
            tracker.scheduledAlerts, trip: trip, policy: tracker.policy,
            soundEnabled: settings.soundEnabled, isTransfer: !isLastLeg)
    }

    private var activityAttributes: TripActivityAttributes {
        TripActivityAttributes(
            lineShortName: line.shortName,
            lineColorHex: line.colorHex,
            directionName: directionName,
            origin: journey.origin.name,
            destination: finalDestination.name)
    }

    private var activityState: TripActivityAttributes.ContentState {
        TripActivityAttributes.ContentState(
            phase: TripActivityAttributes.ContentState.Phase(rawValue: snapshot.phase.rawValue) ?? .riding,
            currentStation: currentStop.station.name,
            nextStation: nextStop?.station.name,
            isDwelling: snapshot.isDwelling,
            stopsRemaining: snapshot.stopsRemaining,
            departedAt: tracker.departedAt,
            arrivalAt: tracker.arrivalDate,
            isEstimated: snapshot.confidence == .estimated)
    }
}
