import Foundation
import WakeMeEngine

/// 환승역에서 **갈아탈 열차가 언제 오는지**.
struct NextTrain: Equatable {
    let trainNumber: String
    let stationsAway: Int
    /// 환승역까지 남은 시간. 노선의 실측 구간 시간을 더해서 낸다.
    let seconds: TimeInterval
    let isExpress: Bool
}

/// 지금까지 환승 대기는 **120초 고정 추정**이었다. 실시간 API가 갈아탈 노선의 열차 위치도
/// 같은 엔드포인트로 주므로 추정 대신 실제 값을 쓸 수 있다.
///
/// 방향은 `RealtimeTracker`와 같은 이유로 **움직임에서 배운다.** 종착역으로 가리는 방법은
/// 순환선에서 틀린 답을 준다 — 2호선 내선 열차는 선릉에서 사당 쪽(순번 증가)으로 가는데
/// 종착역인 성수는 순번이 더 작아서, 종착역만 보면 반대로 읽힌다.
///
/// 배우기 전까지는 아무것도 내보내지 않는다. 15초마다 보므로 대개 한 번 안에 정해진다.
@MainActor
final class TransferWatch {
    private let api: TrainPositionAPI
    private let lineName: String
    private let line: SubwayLine
    private let transferIndex: Int
    /// 다음 구간이 노선 순번이 늘어나는 쪽인지
    private let goesForward: Bool
    private let onUpdate: (NextTrain?) -> Void

    private var task: Task<Void, Never>?
    private var previous: [String: Int] = [:]
    private var forwardIsUpLine: Bool?

    init?(
        key: String,
        line: SubwayLine,
        transferStationID: String,
        goesForward: Bool,
        onUpdate: @escaping (NextTrain?) -> Void
    ) {
        guard !key.isEmpty,
              let name = TrainPositionAPI.apiLineName(forLineID: line.id),
              let index = line.index(of: transferStationID)
        else { return nil }
        api = TrainPositionAPI(key: key)
        lineName = name
        self.line = line
        transferIndex = index
        self.goesForward = goesForward
        self.onUpdate = onUpdate
    }

    func start(interval: TimeInterval = 15) {
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
        guard let positions = try? await api.positions(line: lineName) else { return }
        let indexed = positions.compactMap { position -> (TrainPosition, Int)? in
            guard let index = line.index(ofName: position.stationName) else { return nil }
            return (position, index)
        }
        learnDirection(from: indexed)
        previous = Dictionary(indexed.map { ($0.0.trainNumber, $0.1) }, uniquingKeysWith: { _, b in b })
        onUpdate(nearest(among: indexed))
    }

    /// 지난번과 이번 순번을 견줘 우리 방향의 `updnLine` 값을 알아낸다
    private func learnDirection(from indexed: [(TrainPosition, Int)]) {
        guard forwardIsUpLine == nil else { return }
        for (position, index) in indexed {
            guard let before = previous[position.trainNumber], before != index else { continue }
            let wrapped = abs(index - before) > line.stations.count / 2
            guard !wrapped else { continue }
            let increasing = index > before
            forwardIsUpLine = (increasing == goesForward) ? position.isUpLine : !position.isUpLine
            return
        }
    }

    /// 환승역 뒤쪽에서 이쪽으로 오고 있는 열차 중 가장 가까운 것
    private func nearest(among indexed: [(TrainPosition, Int)]) -> NextTrain? {
        guard let forwardIsUpLine else { return nil }
        let candidates = indexed.filter { position, index in
            guard position.isUpLine == forwardIsUpLine else { return false }
            return goesForward ? index <= transferIndex : index >= transferIndex
        }
        let best = candidates.min {
            abs($0.1 - transferIndex) < abs($1.1 - transferIndex)
        }
        guard let (position, index) = best else { return nil }
        let away = abs(transferIndex - index)
        return NextTrain(
            trainNumber: position.trainNumber,
            stationsAway: away,
            seconds: line.runSeconds(from: min(index, transferIndex), to: max(index, transferIndex)),
            isExpress: position.isExpress)
    }
}

extension SubwayLine {
    /// 실시간 API가 준 역 이름으로 순번을 찾는다 (표기를 맞춘 뒤 비교한다)
    func index(ofName name: String) -> Int? {
        let target = RealtimeTracker.normalize(name)
        return stations.firstIndex { RealtimeTracker.normalize($0.name) == target }
    }
}
