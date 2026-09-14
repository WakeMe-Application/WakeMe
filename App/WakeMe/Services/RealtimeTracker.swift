import Foundation

/// 실시간 열차위치로 탑승 열차를 찾아 따라간다.
///
/// 매칭: 출발역(또는 지금 있을 것으로 보는 역)에 서 있는 열차를 잡고, 이후 그 번호만 따라간다.
/// 방향(updnLine)은 노선마다 의미가 달라(2호선 내·외선) 쓰지 않고, 경로에 있는 역인지로 판단한다.
/// 잡은 열차가 두 번 연속 보이지 않거나 경로를 벗어나면 놓아주고 다시 찾는다.
@MainActor
final class RealtimeTracker {
    private let api: TrainPositionAPI
    private let lineName: String
    private let origin: String
    private let routeStations: Set<String>
    private let onUpdate: (TrainPosition) -> Void

    private var task: Task<Void, Never>?
    private var missedPolls = 0

    private(set) var matchedTrain: String?
    private(set) var lastError: String?
    /// 세션이 알려 주는 현재 추정 역 — 중간에 탔거나 매칭이 끊겼을 때 다시 잡는 실마리
    var expectedStation: String?

    /// 실시간 정보를 제공하지 않는 노선이면 만들어지지 않는다.
    init?(
        key: String,
        lineID: String,
        stationNames: [String],
        onUpdate: @escaping (TrainPosition) -> Void
    ) {
        guard !key.isEmpty, let name = TrainPositionAPI.apiLineName(forLineID: lineID) else { return nil }
        api = TrainPositionAPI(key: key)
        lineName = name
        origin = Self.normalize(stationNames.first ?? "")
        routeStations = Set(stationNames.map(Self.normalize))
        self.onUpdate = onUpdate
    }

    func start(interval: TimeInterval = 30) {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() async {
        do {
            apply(try await api.positions(line: lineName))
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    private func apply(_ positions: [TrainPosition]) {
        if matchedTrain == nil {
            let anchors = Set([origin, expectedStation.map(Self.normalize)].compactMap { $0 })
            matchedTrain = positions.first {
                anchors.contains(Self.normalize($0.stationName)) && $0.status != .departed
            }?.trainNumber
        }
        guard let train = matchedTrain else { return }

        guard let position = positions.first(where: { $0.trainNumber == train }) else {
            // 잠깐 빠지는 경우가 있어 한 번은 봐주고, 두 번 연속이면 다시 찾는다
            missedPolls += 1
            if missedPolls >= 2 {
                matchedTrain = nil
                missedPolls = 0
            }
            return
        }
        missedPolls = 0

        guard routeStations.contains(Self.normalize(position.stationName)) else {
            matchedTrain = nil  // 다른 열차를 탄 것으로 보고 다시 찾는다
            return
        }
        onUpdate(position)
    }

    /// API와 우리 데이터의 역 이름 표기를 맞춘다.
    static func normalize(_ name: String) -> String {
        var value = name
        if let range = value.range(of: "(") { value = String(value[value.startIndex..<range.lowerBound]) }
        value = value.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
        // API가 붙이는 꼬리표를 떼고, 끝의 "역"만 없앤다.
        // ("역"을 전부 지우면 역삼·역곡·역촌이 깨진다)
        for suffix in ["지선", "종착", "행"] where value.count > suffix.count + 1 {
            if value.hasSuffix(suffix) { value.removeLast(suffix.count) }
        }
        if value.hasSuffix("역"), value.count > 2 { value.removeLast() }
        return value
    }
}
