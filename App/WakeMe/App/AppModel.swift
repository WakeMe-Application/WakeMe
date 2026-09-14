import Foundation
import Observation
import WakeMeEngine
import UserNotifications

/// 경로 확인 시트에 띄울 탑승 계획. 환승이 있으면 구간이 여러 개다.
/// 순환선 단일 구간이면 반대 방향 대안도 함께 들고 있다.
struct TripDraft: Identifiable, Hashable {
    let id = UUID()
    /// 구간별 노선 (journey.legs와 같은 순서)
    var lines: [SubwayLine]
    var journey: Journey
    var alternative: Journey?
    /// 이 경로를 어떤 기준으로 골랐는지
    var preference: JourneyPlanner.Options.Preference = .fastest

    /// 첫 구간 — 기존 화면들이 쓰는 값
    var line: SubwayLine { lines[0] }
    var trip: Trip { journey.legs[0].trip }
    var hasTransfer: Bool { journey.transferCount > 0 }

    func line(of leg: Journey.Leg) -> SubwayLine? {
        lines.first { $0.id == leg.lineID }
    }

    mutating func switchDirection() {
        guard let alternative, let line = lines.first else { return }
        self.alternative = journey
        journey = alternative
        lines = Array(repeating: line, count: journey.legs.count)
    }
}

@MainActor
@Observable
final class AppModel {
    let network: SubwayNetwork
    let store: AppStore

    var setupDraft: TripDraft?
    var session: TripSession?
    /// 이름이 같은 역을 하나로 묶은 목록 — 역 선택 화면이 쓴다
    let stationGroups: [StationGroup]
    var showSettings = false
    var showOnboarding: Bool
    /// 한 노선으로 갈 수 없을 때의 안내
    var routeNotice: String?
    /// 스크린샷 하네스에서 역 선택 시트를 바로 띄울 때 쓴다
    var debugShowPicker = false

    /// 경로 시트가 닫힌 뒤 탑승 화면을 띄우기 위해 잠시 보관한다
    @ObservationIgnored private var pendingSession: TripSession?
    @ObservationIgnored private let notificationDelegate = ForegroundNotificationDelegate()

    init(store: AppStore = AppStore()) {
        do {
            network = try SubwayNetwork.bundled()
        } catch {
            fatalError("번들 노선 데이터를 읽을 수 없습니다: \(error)")
        }
        stationGroups = network.searchGrouped("")
        self.store = store
        showOnboarding = !store.settings.hasOnboarded
        store.prune { lineID, stationIDs in
            guard let line = network.line(id: lineID) else { return false }
            return stationIDs.allSatisfy { line.station(id: $0) != nil }
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        #if DEBUG
        applyDebugLaunchState()
        #endif
    }

    func draft(lineID: String, originID: String, destinationID: String, direction: Direction? = nil) -> TripDraft? {
        guard let line = network.line(id: lineID),
              let trip = try? TripPlanner.plan(on: line, from: originID, to: destinationID, direction: direction)
        else { return nil }
        let other: Direction = trip.direction == .forward ? .backward : .forward
        let alternative = line.isCircular
            ? (try? TripPlanner.plan(on: line, from: originID, to: destinationID, direction: other))
                .map { Journey(legs: [Journey.Leg(lineID: line.id, trip: $0)]) }
            : nil
        return TripDraft(
            lines: [line],
            journey: Journey(legs: [Journey.Leg(lineID: line.id, trip: trip)]),
            alternative: alternative)
    }

    /// 환승을 포함해 가장 빠른 경로를 찾는다.
    /// 한 노선으로 갈 수 있으면 환승 없는 경로가 나온다.
    func openSetup(origin: StationGroup, destination: StationGroup) {
        guard origin.name != destination.name else {
            routeNotice = "출발역과 도착역이 같아요."
            return
        }
        guard let draft = plannedDraft(from: origin.name, to: destination.name) else {
            routeNotice = "\(origin.name)에서 \(destination.name)까지 가는 경로를 찾지 못했어요."
            return
        }
        setupDraft = draft
    }

    /// 경로를 계산해 시트용 초안을 만든다. 선호 기준을 바꿔 다시 부를 수 있다.
    func plannedDraft(
        from originName: String, to destinationName: String,
        preference: JourneyPlanner.Options.Preference = .fastest
    ) -> TripDraft? {
        let options = JourneyPlanner.Options(preference: preference)
        guard let journey = try? JourneyPlanner.plan(
            on: network, from: originName, to: destinationName, options: options)
        else { return nil }
        let lines = journey.legs.compactMap { network.line(id: $0.lineID) }
        guard lines.count == journey.legs.count else { return nil }

        var draft = TripDraft(lines: lines, journey: journey, alternative: nil, preference: preference)
        // 순환선 한 구간이면 반대 방향도 보여 준다
        if journey.legs.count == 1, lines[0].isCircular {
            let trip = journey.legs[0].trip
            let other: Direction = trip.direction == .forward ? .backward : .forward
            draft.alternative = (try? TripPlanner.plan(
                on: lines[0], from: trip.origin.id, to: trip.destination.id, direction: other))
                .map { Journey(legs: [Journey.Leg(lineID: lines[0].id, trip: $0)]) }
        }
        return draft
    }

    func group(named name: String) -> StationGroup? {
        stationGroups.first { $0.name == name }
    }

    /// 경로 시트에서 출발 — 시트가 닫힌 뒤(`presentPendingTrip`) 탑승 화면을 띄운다
    func startFromSetup(_ draft: TripDraft) {
        pendingSession = makeSession(draft)
        setupDraft = nil
    }

    func presentPendingTrip() {
        guard let pending = pendingSession else { return }
        pendingSession = nil
        present(pending)
    }

    /// 홈 루틴 카드의 원탭 출발
    func startRoutine(_ routine: Routine) {
        guard let draft = draft(
            lineID: routine.lineID, originID: routine.originID,
            destinationID: routine.destinationID, direction: routine.direction)
        else { return }
        present(makeSession(draft))
    }

    func saveRoutine(named name: String, for draft: TripDraft) {
        store.routines.append(Routine(
            name: name, lineID: draft.line.id, originID: draft.trip.origin.id,
            destinationID: draft.trip.destination.id, direction: draft.trip.direction))
    }

    func closeTrip(feedback timing: AlertTimingFeedback?) {
        guard let session else { return }
        session.end()
        if let timing {
            store.addFeedback(TripFeedback(
                date: .now, lineID: session.line.id, originID: session.trip.origin.id,
                destinationID: session.trip.destination.id, stopCount: session.trip.stopCount, timing: timing))
        }
        self.session = nil
    }

    func completeOnboarding() {
        store.settings.hasOnboarded = true
        showOnboarding = false
    }

    private func makeSession(_ draft: TripDraft) -> TripSession {
        store.addRecent(RecentTrip(
            lineID: draft.line.id, originID: draft.trip.origin.id,
            destinationID: draft.trip.destination.id, direction: draft.trip.direction, date: .now))
        return TripSession(
            journey: draft.journey, lines: draft.lines, settings: store.settings,
            variants: variants(of: draft.line))
    }

    /// 같은 노선의 다른 운행 계통 (급행 ↔ 완행 전환에 쓴다)
    private func variants(of line: SubwayLine) -> [SubwayLine] {
        let prefix = (line.id.split(separator: "-").first.map(String.init) ?? line.id) + "-"
        return network.lines.filter { $0.id.hasPrefix(prefix) && $0.id != line.id }
    }

    private func present(_ session: TripSession) {
        Task { _ = await NotificationScheduler.requestAuthorization() }
        session.begin()
        self.session = session
    }
}

#if DEBUG
extension AppModel {
    /// 시뮬레이터 스크린샷용 상태 주입.
    /// `-uiState home|onboarding|setup|settings|trip-waiting|trip-riding|trip-estimated|trip-prepare|trip-alight|trip-arrived|trip-done`
    fileprivate func applyDebugLaunchState() {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-uiState"), flag + 1 < args.count else { return }
        let state = args[flag + 1]
        seedDemoData()
        showOnboarding = state == "onboarding"

        // 선릉 → 역삼 → 강남 → 교대 → 서초 → 방배 → 사당
        guard let demo = draft(lineID: "L2-본선", originID: "0220", destinationID: "0226") else { return }
        let stops = demo.trip.stops
        switch state {
        case "setup":
            setupDraft = demo
        case "setup-transfer":
            if let origin = group(named: "강남"), let destination = group(named: "명동") {
                openSetup(origin: origin, destination: destination)
            }
        case "settings":
            showSettings = true
        case "picker":
            debugShowPicker = true
        case let trip where trip.hasPrefix("trip-"):
            var settings = store.settings
            settings.keepAliveEnabled = false  // 위치 권한 팝업 없이 캡처
            settings.demoSpeed = 1
            let session = TripSession(journey: demo.journey, lines: demo.lines, settings: settings)
            let offset: TimeInterval? = switch trip {
            case "trip-riding": stops[2].arrivalOffset - 40
            case "trip-estimated": stops[4].arrivalOffset - 30
            case "trip-prepare": stops[4].departureOffset + 20
            case "trip-alight": stops[5].departureOffset + 15
            case "trip-arrived", "trip-done": stops[6].arrivalOffset + 5
            default: nil
            }
            if let offset { session.depart(at: .now - offset) }
            session.begin()
            // 실시간 위치 줄을 네트워크 없이 확인하려고 현재 역 기준으로 한 건 넣는다
            let here = min(session.snapshot.currentIndex, stops.count - 1)
            session.injectLivePosition(TrainPosition(
                trainNumber: "2054",
                stationName: stops[here].station.name,
                nextStationName: stops[min(here + 1, stops.count - 1)].station.name,
                status: .approaching,
                isUpLine: true,
                isExpress: false,
                receivedAt: .now - 8))
            if trip == "trip-done" { session.confirmAlighted() }
            self.session = session
        default:
            break
        }
    }

    private func seedDemoData() {
        guard store.routines.isEmpty else { return }
        store.routines = [
            Routine(name: "출근", lineID: "L2-본선", originID: "0230", destinationID: "0222", direction: .backward),
            Routine(name: "퇴근", lineID: "L2-본선", originID: "0222", destinationID: "0230", direction: .forward),
        ]
        store.addRecent(RecentTrip(lineID: "L2-본선", originID: "0239", destinationID: "0201", direction: .forward, date: .now))
        store.addRecent(RecentTrip(lineID: "L2-본선", originID: "0220", destinationID: "0226", direction: .forward, date: .now))
    }
}
#endif
