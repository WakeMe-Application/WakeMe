import Foundation
import WakeMeEngine

/// 두 엔진(Swift·Kotlin)이 함께 돌릴 **테스트 계약**을 뽑아낸다.
///
/// 로직을 두 번 구현하면 한쪽에서 고친 버그가 다른 쪽에 남는다. 그걸 막으려면
/// 같은 입력에 같은 답을 내는지 기계적으로 견줄 수 있어야 한다.
/// 기댓값은 **이미 검증된 Swift 엔진**에서 뽑는다 — 실제 지하철에서 확인한 쪽이다.
///
/// `swift run spec-dump > ../spec/engine-cases.json`

struct Spec: Encodable {
    var networkVersion: String
    var tripPlans: [TripPlanCase]
    var alerts: [AlertCase]
    var travelTimes: [TravelCase]
    var journeys: [JourneyCase]
}

struct TripPlanCase: Encodable {
    var lineID: String, originID: String, destinationID: String
    var direction: String
    var stopIDs: [String]
    var arrivalOffsets: [TimeInterval]
    var departureOffsets: [TimeInterval]
    var durationSeconds: TimeInterval
}

struct AlertCase: Encodable {
    var lineID: String, originID: String, destinationID: String
    var prepareStopsBefore: Int, alightEarlierBy: TimeInterval
    var alerts: [[String: String]]
}

struct TravelCase: Encodable {
    var lineID: String, fromID: String, toID: String
    var forward: Bool
    var seconds: TimeInterval
}

struct JourneyCase: Encodable {
    var from: String, to: String, preference: String
    var legLineIDs: [String]
    var legOriginIDs: [String]
    var legDestinationIDs: [String]
    var transferCount: Int, stopCount: Int
    var durationSeconds: TimeInterval
}

let network = try SubwayNetwork.bundled()

// 순환선·직선·환승·급행을 고루 덮는다
let tripInputs: [(String, String, String)] = [
    ("L2-본선", "0220", "0226"),   // 선릉 → 사당 (순환선 forward)
    ("L2-본선", "0226", "0220"),   // 사당 → 선릉 (순환선 backward) — 방향 버그가 났던 자리
    ("L2-본선", "0201", "0243"),   // 시청 → 충정로 (배열 끝 넘어감)
    ("L4-본선", "0426", "0409"),   // 4호선 한 방향
    ("L9-본선", "4102", "4138"),   // 김포공항 → 중앙보훈병원
    ("L9-급행", "4102", "4138"),   // 같은 구간의 급행 계통 — 정차역이 달라야 한다
]

var tripPlans: [TripPlanCase] = []
var alerts: [AlertCase] = []
for (lineID, from, to) in tripInputs {
    guard let line = network.line(id: lineID),
          let trip = try? TripPlanner.plan(on: line, from: from, to: to) else { continue }
    tripPlans.append(TripPlanCase(
        lineID: lineID, originID: from, destinationID: to,
        direction: trip.direction.rawValue,
        stopIDs: trip.stops.map(\.station.id),
        arrivalOffsets: trip.stops.map(\.arrivalOffset),
        departureOffsets: trip.stops.map(\.departureOffset),
        durationSeconds: trip.duration))

    for (prepare, earlier) in [(2, 0.0), (3, 30.0), (0, 60.0)] {
        let policy = AlertPolicy(prepareStopsBefore: prepare, alightEarlierBy: earlier)
        alerts.append(AlertCase(
            lineID: lineID, originID: from, destinationID: to,
            prepareStopsBefore: prepare, alightEarlierBy: earlier,
            alerts: trip.alerts(policy: policy).map {
                ["kind": $0.kind.rawValue, "offset": String($0.offset)]
            }))
    }
}

// 구간 합산 — 이번에 runSeconds 를 잘못 써서 틀렸던 계산이다
var travelTimes: [TravelCase] = []
for (lineID, from, to, forward) in [
    ("L2-본선", "0220", "0221", true),   // 이웃
    ("L2-본선", "0220", "0226", true),   // 여러 역
    ("L2-본선", "0226", "0220", false),  // 반대 방향
    ("L2-본선", "0201", "0243", false),  // 배열 끝 넘어감
    ("L4-본선", "0426", "0409", false),
] as [(String, String, String, Bool)] {
    guard let line = network.line(id: lineID),
          let a = line.index(of: from), let b = line.index(of: to) else { continue }
    travelTimes.append(TravelCase(
        lineID: lineID, fromID: from, toID: to, forward: forward,
        seconds: line.travelSeconds(from: a, to: b, forward: forward)))
}

var journeys: [JourneyCase] = []
for (from, to) in [("선릉", "사당"), ("서울역", "고속터미널"), ("인천", "수원"), ("강남", "홍대입구")] {
    for preference in [JourneyPlanner.Options.Preference.fastest, .fewestTransfers] {
        let options = JourneyPlanner.Options(preference: preference)
        guard let journey = try? JourneyPlanner.plan(
            on: network, from: from, to: to, options: options) else { continue }
        journeys.append(JourneyCase(
            from: from, to: to, preference: preference.rawValue,
            legLineIDs: journey.legs.map(\.lineID),
            legOriginIDs: journey.legs.map { $0.trip.origin.id },
            legDestinationIDs: journey.legs.map { $0.trip.destination.id },
            transferCount: journey.transferCount,
            stopCount: journey.stopCount,
            durationSeconds: journey.duration))
    }
}

let spec = Spec(
    networkVersion: network.version,
    tripPlans: tripPlans, alerts: alerts, travelTimes: travelTimes, journeys: journeys)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(spec))
