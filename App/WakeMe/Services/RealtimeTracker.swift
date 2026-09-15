import Foundation

/// 실시간 열차위치로 탑승 열차를 찾아 따라간다.
///
/// 매칭: 우리 위치나 그 뒤에 있는 열차 중 가장 가까운 것을 잡고, 이후 그 번호만 따라간다.
/// 순번은 **경로가 아니라 노선 전체**로 매긴다. 출발역에 서 있는 열차만 보면
/// 한 번 조회에 잡힐 확률이 40%도 안 돼(실측) 몇 분씩 아무것도 못 띄운다.
/// 아직 출발역에 오지 않은 뒤쪽 열차까지 봐야 곧 탈 열차를 잡을 수 있다.
///
/// **방향은 경로 순번으로 판단한다.** "경로에 있는 역인가"만으로는 방향을 못 가린다 —
/// 반대 방향 열차도 똑같은 역들을 지나기 때문이다. (2026-09 실측: 선릉→사당 경로 위
/// 9대 중 6대가 반대 방향이었다.) 순번이 뒤로 가면 반대 방향이므로 놓아준다.
///
/// `updnLine` 값의 의미는 노선마다 다르다 — 실측으로 확인했다(2호선은 0이 순번 증가,
/// 3·4호선은 0이 순번 감소). 그래서 전역 규칙을 두지 않고 **실제 움직임에서 배운다.**
///
/// 배우기 전까지는 잡은 열차를 **화면에 내보내지 않는다.** 방향을 모르는 채 내보내면
/// 절반은 반대 방향 열차다. 틀린 걸 보여주느니 한 폴링(30초) 늦게 보여주는 편이 낫고,
/// 그 지연은 대개 승강장에서 기다리는 동안 지나간다. 한 번 배운 뒤로는 즉시 표시한다.
///
/// 잡은 열차가 두 번 연속 보이지 않거나 경로를 벗어나도 놓아준다.
@MainActor
final class RealtimeTracker {
    private let api: TrainPositionAPI
    private let lineName: String
    /// **노선 전체** 역 이름 → 순번. 방향 판단의 근거다.
    private let routeIndex: [String: Int]
    /// 승차역·목적지의 노선상 순번
    private let boardingIndex: Int
    private let destinationIndex: Int
    /// 우리 진행이 노선 순번이 **늘어나는** 쪽인지. `Trip.Direction.forward`가 그쪽이다.
    private let goesForward: Bool
    private let lineLength: Int
    private let onUpdate: (TrainPosition) -> Void

    private var task: Task<Void, Never>?
    private var missedPolls = 0
    /// 잡은 열차를 마지막으로 본 경로 순번 — 이보다 뒤로 가면 반대 방향이다
    private var lastSeenIndex: Int?
    /// 우리가 가는 방향의 `updnLine` 값. 실제 움직임에서 배운다.
    private var forwardIsUpLine: Bool?
    /// 잡은 열차가 우리 방향임이 확인됐는지. 확인 전에는 화면에 내보내지 않는다.
    private var isConfirmed = false

    private(set) var matchedTrain: String?
    private(set) var lastError: String?
    /// 진단용 — 폴링이 돌고 있는지, 응답에 열차가 몇 대나 오는지
    private(set) var pollCount = 0
    private(set) var lastTrainCount = 0
    /// 세션이 알려 주는 현재 추정 역 — 중간에 탔거나 매칭이 끊겼을 때 다시 잡는 실마리
    var expectedStation: String?

    /// 실시간 정보를 제공하지 않는 노선이면 만들어지지 않는다.
    /// - Parameters:
    ///   - lineStations: 노선 전체 역 이름 (순서대로)
    ///   - origin: 승차역, - destination: 이번 구간 목적지
    ///   - goesForward: 노선 순번이 늘어나는 쪽으로 가는지
    init?(
        key: String,
        lineID: String,
        lineStations: [String],
        origin: String,
        destination: String,
        goesForward: Bool,
        onUpdate: @escaping (TrainPosition) -> Void
    ) {
        guard !key.isEmpty, let name = TrainPositionAPI.apiLineName(forLineID: lineID) else { return nil }
        api = TrainPositionAPI(key: key)
        lineName = name
        let index = Dictionary(
            lineStations.enumerated().map { (Self.normalize($1), $0) },
            uniquingKeysWith: { earlier, _ in earlier })
        guard let from = index[Self.normalize(origin)], let to = index[Self.normalize(destination)] else {
            return nil
        }
        routeIndex = index
        boardingIndex = from
        destinationIndex = to
        self.goesForward = goesForward
        lineLength = lineStations.count
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
        pollCount += 1
        do {
            let positions = try await api.positions(line: lineName)
            lastTrainCount = positions.count
            apply(positions)
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// 화면에 그대로 띄우는 현재 상태.
    /// 실패해도 "찾는 중"만 보이던 탓에 원인을 알 수 없었다 — 이유를 그대로 적는다.
    var statusText: String {
        if let lastError { return "실시간 오류 · \(lastError)" }
        if pollCount == 0 { return "실시간 조회를 시작하는 중…" }
        if matchedTrain == nil {
            return "실시간 열차를 찾는 중… (\(lineName) \(lastTrainCount)대 · \(pollCount)회 조회)"
        }
        return "열차 방향 확인 중… (\(matchedTrain ?? "")번)"
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? TrainPositionError {
            switch error {
            case .missingKey: return "인증키 없음"
            case .badResponse(let code): return "HTTP \(code)"
            case .service(let message): return message
            }
        }
        if let error = error as? URLError {
            return "네트워크 (\(error.code.rawValue))"
        }
        return String(describing: error)
    }

    /// `origin` 에서 **우리 진행 방향으로** 몇 정거장 떨어져 있는지.
    /// 음수면 아직 `origin` 에 오지 않은 뒤쪽이다.
    ///
    /// 방향(`goesForward`)과 순환선의 배열 끝 넘어감을 한 번에 흡수한다.
    /// 순번이 주는 쪽으로 가는 경로(`.backward`)가 전체의 절반이라, 순번 증가만
    /// 전진으로 보면 그 절반에서 아무것도 못 띄운다.
    private func offset(of index: Int, from origin: Int) -> Int {
        let delta = goesForward ? index - origin : origin - index
        let wrapped = (delta % lineLength + lineLength) % lineLength
        return wrapped > lineLength / 2 ? wrapped - lineLength : wrapped
    }

    private func apply(_ positions: [TrainPosition]) {
        if matchedTrain == nil { match(from: positions) }
        guard let train = matchedTrain else { return }

        guard let position = positions.first(where: { $0.trainNumber == train }) else {
            // 잠깐 빠지는 경우가 있어 한 번은 봐주고, 두 번 연속이면 다시 찾는다
            missedPolls += 1
            if missedPolls >= 2 { release() }
            return
        }
        missedPolls = 0

        guard let index = routeIndex[Self.normalize(position.stationName)] else {
            release()  // 경로를 벗어났다 — 다른 열차를 탄 것으로 본다
            return
        }

        if let last = lastSeenIndex {
            let moved = offset(of: index, from: last)
            if moved < 0 {
                // 뒤로 갔다 = 반대 방향 열차였다. 우리 방향은 이 값의 반대다.
                forwardIsUpLine = !position.isUpLine
                release()
                return
            }
            if moved > 0 {
                forwardIsUpLine = position.isUpLine
                isConfirmed = true
            }
        }
        lastSeenIndex = index
        guard isConfirmed else { return }
        onUpdate(position)
    }

    /// 탑승 열차 후보를 고른다.
    ///
    /// 우리 위치(추정)나 그 **뒤**에 있는 열차만 본다. 앞서간 열차는 우리를 태울 수 없고,
    /// 특히 목적지에 있는 열차는 우리를 두고 떠나는 중이라 잡으면 안 된다.
    /// 후보가 여럿이면 우리에게 가장 가까운(순번이 가장 큰) 것을 고른다.
    private func match(from positions: [TrainPosition]) {
        let anchor = expectedStation.flatMap { routeIndex[Self.normalize($0)] } ?? boardingIndex
        let best = positions
            .compactMap { position -> (train: TrainPosition, index: Int, gap: Int)? in
                guard position.status != .departed,
                      let index = routeIndex[Self.normalize(position.stationName)],
                      forwardIsUpLine.map({ $0 == position.isUpLine }) ?? true
                else { return nil }
                let gap = offset(of: index, from: anchor)
                // 우리 위치나 그 뒤(아직 안 온 열차)만. 목적지에 닿은 열차는 우리를 두고 떠난다.
                guard gap <= 0, offset(of: index, from: destinationIndex) < 0 else { return nil }
                return (position, index, gap)
            }
            .max { $0.gap < $1.gap }   // 우리에게 가장 가까운(0에 가까운) 것
        guard let best else { return }
        matchedTrain = best.train.trainNumber
        lastSeenIndex = best.index
        // 방향을 이미 배웠다면 후보를 거를 때 이미 썼으므로 바로 믿어도 된다
        isConfirmed = forwardIsUpLine != nil
    }

    private func release() {
        matchedTrain = nil
        lastSeenIndex = nil
        missedPolls = 0
        isConfirmed = false
    }

    /// API와 우리 데이터의 역 이름 표기를 맞춘다.
    /// 순수 함수라 격리가 필요 없다 (다른 서비스에서도 표기를 맞출 때 쓴다)
    nonisolated static func normalize(_ name: String) -> String {
        var value = name
        if let range = value.range(of: "(") { value = String(value[value.startIndex..<range.lowerBound]) }
        // 공백과 가운뎃점·마침표를 지운다.
        // 같은 역을 API는 "4.19민주묘지", 우리 데이터는 "4·19민주묘지"로 적는다.
        // (부호를 떼도 이름이 겹치는 역은 1,134개 중 없음을 확인했다)
        value = String(value.filter { !$0.isWhitespace && $0 != "·" && $0 != "." })
        // API가 붙이는 꼬리표를 떼고, 끝의 "역"만 없앤다.
        // ("역"을 전부 지우면 역삼·역곡·역촌이 깨진다)
        for suffix in ["지선", "종착", "행"] where value.count > suffix.count + 1 {
            if value.hasSuffix(suffix) { value.removeLast(suffix.count) }
        }
        if value.hasSuffix("역"), value.count > 2 { value.removeLast() }
        return aliases[value] ?? value
    }

    /// 실시간 API가 아직 개명 전 이름으로 보고하는 역들.
    /// 값은 `network.json` 이름을 위 규칙으로 정규화한 결과와 같아야 한다
    /// (예: "자양(뚝섬한강공원)" → 괄호를 떼면 "자양").
    /// API가 새 이름으로 바뀌어도 그때는 별칭을 안 타고 그대로 맞으므로 둬도 무해하다.
    private nonisolated static let aliases: [String: String] = [
        "뚝섬유원지": "자양",      // 7호선 0728
        "지제": "평택지제",        // 1호선
    ]
}
