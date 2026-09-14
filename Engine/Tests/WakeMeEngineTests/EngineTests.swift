import Foundation
import Testing
@testable import WakeMeEngine

// 역 코드는 공공 역번호 (2호선: 0201 시청 … 0243 충정로)
private let 시청 = "0201", 선릉 = "0220", 역삼 = "0221", 강남 = "0222", 교대 = "0223", 서초 = "0224",
            사당 = "0226", 충정로 = "0243"

private func line2() throws -> SubwayLine {
    try #require(try SubwayNetwork.bundled().line(id: "L2-본선"))
}

struct NetworkTests {
    @Test func coversMetropolitanLines() throws {
        let network = try SubwayNetwork.bundled()
        #expect(network.lines.count == 41)
        for id in ["L1-인천", "L1-신창", "L2-본선", "L9-본선", "KG-본선", "SB-본선",
                   "SIN-본선", "AREX-본선", "EVER-본선", "I1-본선", "SILLIM-본선"] {
            #expect(network.line(id: id) != nil, "\(id) 노선이 없습니다")
        }
    }

    /// 급행은 별도 운행 계통으로 들어 있다
    @Test func coversExpressServices() throws {
        let network = try SubwayNetwork.bundled()
        for id in ["L9-급행", "L1-경인급행", "L1-경원급행", "L1-경부급행",
                   "KG-경의선급행", "KG-중앙선급행", "KG-서울역급행",
                   "SB-분당선급행", "SB-수인선급행"] {
            #expect(network.line(id: id) != nil, "\(id) 급행 계통이 없습니다")
        }
    }

    @Test func line2IsACompleteLoop() throws {
        let line = try line2()
        #expect(line.isCircular)
        #expect(line.stations.count == 43)
        #expect(Set(line.stations.map(\.id)).count == 43)
        #expect(line.stations.first?.name == "시청")
        #expect(line.stations.last?.name == "충정로(경기대입구)")
        #expect(line.directionName(.forward) == "내선순환")
    }

    @Test func transfersPointAtOtherLines() throws {
        let line = try line2()
        let gangnam = try #require(line.station(id: 강남))
        #expect(gangnam.transfers == ["신분당선"])
        #expect(gangnam.nameEn == "Gangnam")
        #expect(try #require(line.station(id: 사당)).transfers == ["4호선"])
    }

    /// 1호선처럼 갈라지는 노선은 운행 계통별로 나뉜다 (공통 구간은 양쪽에 모두 들어 있다)
    @Test func forkedLinesShareTheTrunk() throws {
        let network = try SubwayNetwork.bundled()
        let incheon = try #require(network.line(id: "L1-인천"))
        let sinchang = try #require(network.line(id: "L1-신창"))
        #expect(incheon.stations.first?.name == sinchang.stations.first?.name)
        #expect(incheon.stations.last?.name == "인천")
        #expect(sinchang.stations.last?.name == "신창(순천향대)")
        #expect(incheon.stations.contains { $0.name == "구로" })
        #expect(sinchang.stations.contains { $0.name == "구로" })
    }

    /// 지선은 분기역에서 바깥으로 나가는 순서여야 한다
    @Test func spurStartsAtItsJunction() throws {
        let network = try SubwayNetwork.bundled()
        let seongsu = try #require(network.line(id: "L2-성수지선"))
        #expect(seongsu.stations.map(\.name) == ["성수", "용답", "신답", "용두(동대문구청)", "신설동"])
        let sinjeong = try #require(network.line(id: "L2-신정지선"))
        #expect(sinjeong.stations.map(\.name) == ["신도림", "도림천", "양천구청", "신정네거리", "까치산"])
    }

    /// 급행은 본선 역 일부만 서고, 구간 시간은 건너뛴 본선 구간의 합이다
    @Test func expressSkipsStations() throws {
        let network = try SubwayNetwork.bundled()
        let express = try #require(network.line(id: "L9-급행"))
        let local = try #require(network.line(id: "L9-본선"))
        #expect(express.stations.count == 16)
        #expect(express.stations.first?.name == "김포공항")
        #expect(express.stations.last?.name == "중앙보훈병원")
        #expect(express.stations.count < local.stations.count)

        let gimpo = try #require(local.index(of: express.stations[0].id))
        let magok = try #require(local.index(of: express.stations[1].id))
        let skipped = (gimpo..<magok).reduce(0.0) { $0 + local.runSeconds(from: $1, to: $1 + 1) }
        // 급행은 통과역 정차를 건너뛸 뿐 아니라 더 빠르게 달린다 (추정 계수 0.75)
        #expect(express.runSeconds(from: 0, to: 1) == (skipped * 0.75).rounded())
        #expect(express.runSeconds(from: 0, to: 1) < skipped)
    }

    /// 같은 이름의 역은 노선이 달라도 한 줄로 묶인다
    @Test func groupsStationsByName() throws {
        let network = try SubwayNetwork.bundled()
        let groups = network.searchGrouped("사당")
        #expect(groups.filter { $0.name == "사당" }.count == 1)
        #expect(try #require(groups.first { $0.name == "사당" }).lines.map(\.shortName).sorted() == ["2", "4"])

        // 1호선 인천행·신창행처럼 같은 노선의 계통은 배지 하나로 합친다
        let yeoncheon = try #require(network.searchGrouped("연천").first { $0.name == "연천" })
        #expect(yeoncheon.entries.count == 2)
        #expect(yeoncheon.lines.count == 1)
    }

    @Test func searchPrefersPrefixMatches() throws {
        let results = try SubwayNetwork.bundled().search("신림")
        #expect(results.first?.station.name.hasPrefix("신림") == true)
        #expect(results.contains { $0.line.id == "L2-본선" })
        #expect(results.contains { $0.line.id == "SILLIM-본선" })
    }
}

struct PlannerTests {
    @Test func choosesShorterDirectionOnCircularLine() throws {
        let line = try line2()
        let trip = try TripPlanner.plan(on: line, from: 강남, to: 서초)
        #expect(trip.direction == .forward)
        #expect(trip.stops.map(\.station.name) == ["강남", "교대(법원·검찰청)", "서초"])

        let back = try TripPlanner.plan(on: line, from: 강남, to: 역삼)
        #expect(back.direction == .backward)
        #expect(back.stopCount == 1)
    }

    @Test func wrapsAroundTheLoop() throws {
        let line = try line2()
        #expect(try TripPlanner.plan(on: line, from: 충정로, to: 시청).stopCount == 1)
        #expect(try TripPlanner.plan(on: line, from: 시청, to: 충정로).direction == .backward)
    }

    @Test func explicitDirectionTakesTheLongWay() throws {
        #expect(try TripPlanner.plan(on: try line2(), from: 강남, to: 역삼, direction: .forward).stopCount == 42)
    }

    /// 구간 시간은 노선 데이터의 실측값을 따르고, 정차 시간이 더해진다
    @Test func offsetsFollowMeasuredRunAndDwellTimes() throws {
        let line = try line2()
        let trip = try TripPlanner.plan(on: line, from: 강남, to: 서초)
        let gangnam = try #require(line.index(of: 강남))
        let gyodae = try #require(line.index(of: 교대))

        // 서울교통공사 실측 (강남 → 교대)
        #expect(line.runSeconds(from: gangnam, to: gyodae) == 90)
        #expect(trip.stops[1].arrivalOffset == line.runSeconds(from: gangnam, to: gyodae))
        #expect(trip.stops[1].departureOffset == trip.stops[1].arrivalOffset + line.defaultDwellSeconds)
        #expect(trip.duration == trip.stops[1].departureOffset + line.runSeconds(from: gyodae, to: gyodae + 1))
    }

    @Test func rejectsSameStation() throws {
        let line = try line2()
        #expect(throws: TripPlanner.PlanError.sameStation) {
            try TripPlanner.plan(on: line, from: 강남, to: 강남)
        }
    }
}

struct AlertTests {
    /// 선릉 → 역삼 → 강남 → 교대 → 서초 → 방배 → 사당
    private func seolleungToSadang() throws -> Trip {
        try TripPlanner.plan(on: try line2(), from: 선릉, to: 사당)
    }

    @Test func threeStageAlerts() throws {
        let trip = try seolleungToSadang()
        let alerts = trip.alerts(policy: AlertPolicy())
        #expect(alerts.map(\.kind) == [.prepare, .alightNow, .arrived])
        #expect(alerts[0].offset == trip.stops[4].departureOffset)  // 서초 출발
        #expect(alerts[1].offset == trip.stops[5].departureOffset)  // 방배 출발
        #expect(alerts[2].offset == trip.duration)
    }

    @Test func oneStopTripAlertsRightAfterDeparture() throws {
        let alerts = try TripPlanner.plan(on: try line2(), from: 강남, to: 역삼).alerts(policy: AlertPolicy())
        #expect(alerts.map(\.kind) == [.alightNow, .arrived])
        #expect(alerts[0].offset == 0)
    }

    @Test func alightEarlierByMovesSecondAlert() throws {
        let trip = try seolleungToSadang()
        let alerts = trip.alerts(policy: AlertPolicy(alightEarlierBy: 30))
        #expect(alerts[1].offset == trip.stops[5].departureOffset - 30)
    }

    @Test func prepareCanBeTurnedOff() throws {
        let alerts = try seolleungToSadang().alerts(policy: AlertPolicy(prepareStopsBefore: 0))
        #expect(alerts.map(\.kind) == [.alightNow, .arrived])
    }
}

struct TrackerTests {
    private let t0 = Date(timeIntervalSince1970: 0)

    private func tracker(timeScale: Double = 1) throws -> TripTracker {
        TripTracker(trip: try TripPlanner.plan(on: try line2(), from: 선릉, to: 사당), timeScale: timeScale)
    }

    @Test func waitsUntilDeparture() throws {
        #expect(try tracker().snapshot(at: t0).phase == .waiting)
    }

    @Test func runningTowardFirstStop() throws {
        var tracker = try tracker()
        tracker.depart(at: t0)
        let snap = tracker.snapshot(at: t0 + tracker.trip.stops[1].arrivalOffset - 5)
        #expect(snap.phase == .riding)
        #expect(snap.currentIndex == 1)
        #expect(snap.isDwelling == false)
        #expect(snap.stopsRemaining == 6)
    }

    @Test func dwellingAtStop() throws {
        var tracker = try tracker()
        tracker.depart(at: t0)
        let snap = tracker.snapshot(at: t0 + tracker.trip.stops[1].arrivalOffset + 1)
        #expect(snap.currentIndex == 1)
        #expect(snap.isDwelling)
        #expect(snap.stopsRemaining == 5)
    }

    @Test func phasesAdvanceWithAlerts() throws {
        var tracker = try tracker()
        tracker.depart(at: t0)
        let stops = tracker.trip.stops

        #expect(tracker.snapshot(at: t0 + stops[4].departureOffset + 1).phase == .prepare)

        let alight = tracker.snapshot(at: t0 + stops[5].departureOffset + 1)
        #expect(alight.phase == .alightNow)
        #expect(alight.currentIndex == 6)
        #expect(alight.stopsRemaining == 1)

        let arrived = tracker.snapshot(at: t0 + tracker.trip.duration + 1)
        #expect(arrived.phase == .arrived)
        #expect(arrived.stopsRemaining == 0)
    }

    @Test func becomesEstimatedAfterThreeStopsWithoutAnchor() throws {
        var tracker = try tracker()
        tracker.depart(at: t0)
        let stops = tracker.trip.stops
        #expect(tracker.snapshot(at: t0 + stops[2].arrivalOffset + 1).confidence == .anchored)
        #expect(tracker.snapshot(at: t0 + stops[3].arrivalOffset + 1).confidence == .estimated)
    }

    @Test func correctionReanchorsTheClock() throws {
        var tracker = try tracker()
        tracker.depart(at: t0)
        let now = t0 + 900
        tracker.correct(arrivedAt: 2, at: now)
        let snap = tracker.snapshot(at: now)
        #expect(snap.currentIndex == 2)
        #expect(snap.isDwelling)
        #expect(snap.confidence == .anchored)
    }

    @Test func timeScaleSpeedsUpDemoTrips() throws {
        var tracker = try tracker(timeScale: 10)
        tracker.depart(at: t0)
        let duration = tracker.trip.duration
        #expect(tracker.snapshot(at: t0 + 10).secondsToArrival == (duration - 100) / 10)
        #expect(tracker.snapshot(at: t0 + duration / 10 + 1).phase == .arrived)
        #expect(tracker.arrivalDate == t0 + duration / 10)
    }
}

struct JourneyTests {
    private func network() throws -> SubwayNetwork { try SubwayNetwork.bundled() }

    /// 갈아탈 이유가 없으면 한 구간으로 끝난다
    @Test func planWithoutTransfer() throws {
        let journey = try JourneyPlanner.plan(on: try network(), from: "선릉", to: "사당")
        #expect(journey.transferCount == 0)
        #expect(journey.legs.count == 1)
        #expect(journey.legs[0].lineID.hasPrefix("L2"))
        #expect(journey.destination.name == "사당")
    }

    /// 플래너는 "같은 노선"이 아니라 시간을 기준으로 고른다.
    /// 환승을 비싸게 매기면 돌아가더라도 직통을 택한다.
    /// (도보 시간은 실측이 덮어쓰므로, 모든 환승에 붙는 대기 시간으로 비싸게 만든다)
    @Test func expensiveTransfersFavourTheDirectRoute() throws {
        let network = try network()
        let quick = try JourneyPlanner.plan(on: network, from: "강남", to: "시청")
        let direct = try JourneyPlanner.plan(
            on: network, from: "강남", to: "시청",
            options: JourneyPlanner.Options(transferWaitSeconds: 1200))
        #expect(quick.duration <= direct.duration)
        #expect(direct.transferCount == 0)
        #expect(direct.legs[0].lineID.hasPrefix("L2"))
    }

    /// 다른 노선이면 환승역을 끼워 넣는다
    @Test func planWithTransfer() throws {
        let journey = try JourneyPlanner.plan(on: try network(), from: "강남", to: "명동")
        #expect(journey.transferCount >= 1)
        #expect(journey.legs.first?.trip.origin.name == "강남")
        #expect(journey.destination.name == "명동")
        // 환승역은 두 구간이 만나는 역이어야 한다
        for (before, after) in zip(journey.legs, journey.legs.dropFirst()) {
            #expect(before.trip.destination.name == after.trip.origin.name)
        }
    }

    /// 환승 시간이 전체 소요시간에 더해진다
    @Test func transferTimeCountsTowardDuration() throws {
        let journey = try JourneyPlanner.plan(on: try network(), from: "강남", to: "명동")
        let riding = journey.legs.reduce(0.0) { $0 + $1.trip.duration }
        let transfers = journey.legs.reduce(0.0) { $0 + $1.transferSeconds }
        #expect(journey.duration == riding + transfers)
        #expect(transfers > 0)
    }

    /// 환승 도보 시간표는 양방향으로 들어 있다 (서울교통공사 실측)
    @Test func transferWalkTimesAreMeasured() throws {
        let network = try network()
        #expect(network.transferWalkSeconds(at: "서울역", from: "1호선", to: "4호선") == 133)
        #expect(network.transferWalkSeconds(at: "서울역", from: "4호선", to: "1호선") == 133)
        #expect(network.transferWalkSeconds(at: "총신대입구(이수)", from: "4호선", to: "7호선") == 143)
        // 서울교통공사 구간이 아닌 환승은 데이터가 없다 → 기본값으로 떨어진다
        #expect(network.transferWalkSeconds(at: "부평", from: "1호선", to: "인천 1호선") == nil)
    }

    /// 각 환승 구간은 실측 도보시간(없으면 기본값)에 대기 시간을 더해 쓴다
    @Test func usesMeasuredTransferWalkTimes() throws {
        let network = try network()
        let options = JourneyPlanner.Options(transferWaitSeconds: 120)
        let journey = try JourneyPlanner.plan(on: network, from: "종각", to: "명동", options: options)
        #expect(journey.transferCount >= 1)

        var measured = 0
        for (before, leg) in zip(journey.legs, journey.legs.dropFirst()) {
            let from = try #require(network.line(id: before.lineID)).lineName
            let to = try #require(network.line(id: leg.lineID)).lineName
            let walk = network.transferWalkSeconds(at: leg.trip.origin.name, from: from, to: to)
            #expect(leg.transferSeconds == (walk ?? options.transferSeconds) + 120)
            if walk != nil { measured += 1 }
        }
        // 도심 환승이므로 적어도 한 번은 실측이 쓰여야 한다
        #expect(measured >= 1)
    }

    /// "환승 적게"를 고르면 조금 돌아가더라도 환승이 줄어든다
    @Test func fewestTransfersPreference() throws {
        let network = try network()
        let fastest = try JourneyPlanner.plan(on: network, from: "강남", to: "명동")
        let simple = try JourneyPlanner.plan(
            on: network, from: "강남", to: "명동",
            options: JourneyPlanner.Options(preference: .fewestTransfers))
        #expect(simple.transferCount <= fastest.transferCount)
        #expect(simple.duration >= fastest.duration)
        // 환승 가상 비용은 실제 소요시간에 들어가지 않는다
        let riding = simple.legs.reduce(0.0) { $0 + $1.trip.duration }
        let transfers = simple.legs.reduce(0.0) { $0 + $1.transferSeconds }
        #expect(simple.duration == riding + transfers)
    }

    /// 급행 계통은 기본적으로 후보에서 뺀다
    @Test func excludesExpressLinesByDefault() throws {
        let journey = try JourneyPlanner.plan(on: try network(), from: "김포공항", to: "중앙보훈병원")
        #expect(journey.legs.allSatisfy { !$0.lineID.contains("급행") })
    }

    @Test func rejectsSameStation() throws {
        let network = try network()
        #expect(throws: JourneyPlanner.PlanError.sameStation) {
            try JourneyPlanner.plan(on: network, from: "강남", to: "강남")
        }
    }

    @Test func rejectsUnknownStation() throws {
        let network = try network()
        #expect(throws: JourneyPlanner.PlanError.stationNotFound("없는역")) {
            try JourneyPlanner.plan(on: network, from: "없는역", to: "강남")
        }
    }
}

struct StopDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 0)

    /// 폰이 어떻게 놓여 있든 수평 성분만 남는다
    @Test func horizontalAccelerationRemovesGravityDirection() {
        // 중력 방향(-z)으로만 흔들리면 수평 성분은 0
        let vertical = MotionSample(time: t0, userAcceleration: (0, 0, -0.5), gravity: (0, 0, -1))
        #expect(vertical.horizontalAcceleration < 0.001)

        // 같은 크기가 수평(x)이면 그대로 남는다 (g → m/s²)
        let horizontal = MotionSample(time: t0, userAcceleration: (0.5, 0, 0), gravity: (0, 0, -1))
        #expect(abs(horizontal.horizontalAcceleration - 0.5 * 9.81) < 0.001)

        // 폰이 45도로 기울어져 있어도 크기는 같다
        let tilted = MotionSample(
            time: t0,
            userAcceleration: (0.5 * 0.70711, 0, 0.5 * 0.70711),
            gravity: (0.70711, 0, -0.70711))
        #expect(abs(tilted.horizontalAcceleration - 0.5 * 9.81) < 0.01)
    }

    /// 흔들리다 조용해지면 정차, 다시 흔들리면 출발
    private func feed(_ detector: inout StopDetector, from: TimeInterval, to: TimeInterval, level: Double) -> [MotionEvent] {
        var events: [MotionEvent] = []
        for tick in stride(from: from, to: to, by: 0.2) {
            if let event = detector.consume(MotionSample(time: t0 + tick, horizontalAcceleration: level)) {
                events.append(event)
            }
        }
        return events
    }

    @Test func detectsStopAfterQuietPeriod() {
        var detector = StopDetector()
        _ = feed(&detector, from: 0, to: 20, level: 0.9)   // 주행
        let stops = feed(&detector, from: 20, to: 40, level: 0.05)  // 정차
        #expect(detector.state == .stopped)
        #expect(stops.count == 1)
        if case .stopped(let at) = stops.first {
            // 조용해지기 시작한 시점을 정차 시각으로 본다.
            // 이동평균을 쓰기 때문에 창 길이(3초)만큼 늦게 잡힐 수 있다.
            #expect(abs(at.timeIntervalSince(t0 + 20)) < 4)
        } else {
            Issue.record("정차 이벤트가 없습니다")
        }
    }

    @Test func detectsDepartureAfterMoving() {
        var detector = StopDetector()
        _ = feed(&detector, from: 0, to: 20, level: 0.05)
        let departures = feed(&detector, from: 20, to: 30, level: 1.2)
        #expect(detector.state == .moving)
        #expect(departures.count == 1)
    }

    /// 짧게 흔들리거나 잠깐 조용한 정도로는 상태가 바뀌지 않는다
    @Test func ignoresBriefNoise() {
        var detector = StopDetector()
        _ = feed(&detector, from: 0, to: 20, level: 0.9)
        let events = feed(&detector, from: 20, to: 23, level: 0.05)  // 3초만 조용
        #expect(events.isEmpty)
        #expect(detector.state == .moving)
    }
}

struct MotionTrackingTests {
    private let t0 = Date(timeIntervalSince1970: 0)

    private func tracker() throws -> TripTracker {
        TripTracker(trip: try TripPlanner.plan(on: try line2(), from: 선릉, to: 사당))
    }

    /// 출발 전 감지된 움직임은 탑승 시점이 된다
    @Test func firstDepartureStartsTheTrip() throws {
        var tracker = try tracker()
        // #expect 안에서는 mutating 메서드를 부를 수 없어 결과를 먼저 받는다
        let started = tracker.observe(.departed(at: t0))
        #expect(started)
        #expect(tracker.snapshot(at: t0 + 10).phase == .riding)
    }

    /// 예상 시각 근처의 정차는 시계를 다시 맞춘다
    @Test func detectedStopReanchorsTheClock() throws {
        var tracker = try tracker()
        tracker.depart(at: t0)
        let expected = tracker.trip.stops[2].arrivalOffset
        let late = t0 + expected + 40  // 실제로는 40초 늦게 도착

        let reanchored = tracker.observe(.stopped(at: late))
        #expect(reanchored)
        let snap = tracker.snapshot(at: late)
        #expect(snap.currentIndex == 2)
        #expect(snap.isDwelling)
        #expect(snap.confidence == .anchored)
        // 남은 시간도 늦어진 만큼 다시 계산된다
        #expect(tracker.arrivalDate == late + (tracker.trip.duration - expected))
    }

    /// 터널 한가운데 신호대기처럼 예상과 동떨어진 정차는 무시한다
    @Test func ignoresStopsFarFromSchedule() throws {
        var tracker = try tracker()
        tracker.depart(at: t0)
        let anchorBefore = tracker.departedAt
        let ignored = tracker.observe(.stopped(at: t0 + 20))
        #expect(ignored == false)
        #expect(tracker.departedAt == anchorBefore)
    }

    /// 실시간 열차 정보는 어느 역인지 알기 때문에 시각과 무관하게 그 역으로 맞춘다
    @Test func realtimeArrivalReanchorsByStation() throws {
        var tracker = try tracker()
        tracker.depart(at: t0)
        let station = tracker.trip.stops[3].station.id
        let now = t0 + 500  // 시간 모델이 예상한 시각과 달라도 역 정보를 믿는다

        let updated = tracker.observe(arrivedAt: station, at: now)
        #expect(updated)
        let snap = tracker.snapshot(at: now)
        #expect(snap.currentIndex == 3)
        #expect(snap.isDwelling)
        #expect(snap.confidence == .anchored)
    }

    /// 경로에 없는 역이 오면 무시한다
    @Test func ignoresArrivalOutsideTheTrip() throws {
        var tracker = try tracker()
        tracker.depart(at: t0)
        let anchorBefore = tracker.departedAt
        let updated = tracker.observe(arrivedAt: 시청, at: t0 + 100)
        #expect(updated == false)
        #expect(tracker.departedAt == anchorBefore)
    }
}
