import Foundation

/// 환승을 포함한 전체 여정. 구간(leg) 하나는 한 노선을 계속 타는 구간이다.
public struct Journey: Hashable, Sendable {
    public struct Leg: Hashable, Sendable {
        public let lineID: String
        public let trip: Trip
        /// 이 구간을 타기 전 환승에 걸리는 시간(초). 첫 구간은 0.
        public let transferSeconds: TimeInterval

        public init(lineID: String, trip: Trip, transferSeconds: TimeInterval = 0) {
            self.lineID = lineID
            self.trip = trip
            self.transferSeconds = transferSeconds
        }
    }

    public let legs: [Leg]

    public init(legs: [Leg]) {
        self.legs = legs
    }

    public var origin: Station { legs[0].trip.origin }
    public var destination: Station { legs[legs.count - 1].trip.destination }
    public var transferCount: Int { legs.count - 1 }
    public var stopCount: Int { legs.reduce(0) { $0 + $1.trip.stopCount } }
    /// 타는 시간 + 환승 시간
    public var duration: TimeInterval {
        legs.reduce(0) { $0 + $1.trip.duration + $1.transferSeconds }
    }
    /// 환승역 이름
    public var transferStations: [String] {
        legs.dropFirst().map(\.trip.origin.name)
    }
}

/// 노선을 갈아타는 경로를 찾는다. 역 이름으로 노선 사이를 잇고, 시간이 가장 짧은 길을 고른다.
public enum JourneyPlanner {
    public struct Options: Hashable, Sendable {
        /// 무엇을 우선할지
        public enum Preference: String, Hashable, Sendable {
            /// 시간이 가장 짧은 길
            case fastest
            /// 환승이 적은 길 (조금 돌아가더라도)
            case fewestTransfers
        }

        /// 실측 도보 시간이 없는 환승역에 쓰는 기본값(걷기)
        public var transferSeconds: TimeInterval
        /// 환승 후 열차를 기다리는 시간 추정치 (실측 데이터에 없는 부분)
        public var transferWaitSeconds: TimeInterval
        public var maxTransfers: Int
        /// 급행 계통도 후보에 넣을지 (기본은 제외 — 사용자가 급행을 탈지 알 수 없다)
        public var includeExpress: Bool
        public var preference: Preference

        /// 환승을 적게 하려 할 때 환승 1회에 더 매기는 가상 비용.
        /// 실제 소요시간에는 들어가지 않고 경로를 고를 때만 쓴다.
        var transferPenalty: TimeInterval { preference == .fewestTransfers ? 1200 : 0 }

        public init(
            transferSeconds: TimeInterval = 150,
            transferWaitSeconds: TimeInterval = 120,
            maxTransfers: Int = 2,
            includeExpress: Bool = false,
            preference: Preference = .fastest
        ) {
            self.transferSeconds = transferSeconds
            self.transferWaitSeconds = transferWaitSeconds
            self.maxTransfers = maxTransfers
            self.includeExpress = includeExpress
            self.preference = preference
        }
    }

    public enum PlanError: Error, Equatable {
        case stationNotFound(String)
        case sameStation
        case noRoute
    }

    private struct Node: Hashable {
        let line: Int
        let index: Int
    }

    public static func plan(
        on network: SubwayNetwork, from origin: String, to destination: String, options: Options = Options()
    ) throws -> Journey {
        guard origin != destination else { throw PlanError.sameStation }

        let lines = network.lines.filter { options.includeExpress || !$0.name.contains("급행") }
        var starts: [Node] = []
        var goals: Set<Node> = []
        var byStation: [String: [Node]] = [:]

        for (lineIndex, line) in lines.enumerated() {
            for (stationIndex, station) in line.stations.enumerated() {
                let node = Node(line: lineIndex, index: stationIndex)
                byStation[station.name, default: []].append(node)
                if station.name == origin { starts.append(node) }
                if station.name == destination { goals.insert(node) }
            }
        }
        guard !starts.isEmpty else { throw PlanError.stationNotFound(origin) }
        guard !goals.isEmpty else { throw PlanError.stationNotFound(destination) }

        var cost: [Node: TimeInterval] = [:]
        var transfers: [Node: Int] = [:]
        var parent: [Node: Node] = [:]
        var frontier: Set<Node> = []
        for node in starts {
            cost[node] = 0
            transfers[node] = 0
            frontier.insert(node)
        }

        var goal: Node?
        while let current = frontier.min(by: { (cost[$0] ?? .infinity) < (cost[$1] ?? .infinity) }) {
            frontier.remove(current)
            let currentCost = cost[current] ?? .infinity
            if goals.contains(current) {
                goal = current
                break
            }

            let line = lines[current.line]
            let station = line.stations[current.index]

            // 같은 노선에서 앞뒤 역으로
            for next in neighbours(of: current.index, in: line) {
                let node = Node(line: current.line, index: next)
                let move = line.runSeconds(from: current.index, to: next) + line.defaultDwellSeconds
                relax(node, from: current, newCost: currentCost + move,
                      newTransfers: transfers[current] ?? 0,
                      cost: &cost, transfers: &transfers, parent: &parent, frontier: &frontier)
            }

            // 같은 이름의 역에서 다른 노선으로 갈아타기
            let used = transfers[current] ?? 0
            guard used < options.maxTransfers else { continue }
            for node in byStation[station.name] ?? [] where node.line != current.line {
                let seconds = transferSeconds(
                    on: network, at: station.name,
                    from: line.lineName, to: lines[node.line].lineName, options: options)
                relax(node, from: current,
                      newCost: currentCost + seconds + options.transferPenalty,
                      newTransfers: used + 1,
                      cost: &cost, transfers: &transfers, parent: &parent, frontier: &frontier)
            }
        }

        guard let end = goal else { throw PlanError.noRoute }
        return try journey(to: end, parent: parent, lines: lines, network: network, options: options)
    }

    /// 실측 도보 시간이 있으면 그것에 대기 시간을 더하고, 없으면 기본값을 쓴다
    private static func transferSeconds(
        on network: SubwayNetwork, at station: String, from: String, to: String, options: Options
    ) -> TimeInterval {
        let walk = network.transferWalkSeconds(at: station, from: from, to: to) ?? options.transferSeconds
        return walk + options.transferWaitSeconds
    }

    private static func neighbours(of index: Int, in line: SubwayLine) -> [Int] {
        let count = line.stations.count
        guard count > 1 else { return [] }
        if line.isCircular {
            return [(index + 1) % count, (index - 1 + count) % count]
        }
        return [index - 1, index + 1].filter { $0 >= 0 && $0 < count }
    }

    private static func relax(
        _ node: Node, from current: Node, newCost: TimeInterval, newTransfers: Int,
        cost: inout [Node: TimeInterval], transfers: inout [Node: Int],
        parent: inout [Node: Node], frontier: inout Set<Node>
    ) {
        if newCost < (cost[node] ?? .infinity) {
            cost[node] = newCost
            transfers[node] = newTransfers
            parent[node] = current
            frontier.insert(node)
        }
    }

    /// 경로를 노선별 구간으로 묶어 여정을 만든다
    private static func journey(
        to end: Node, parent: [Node: Node], lines: [SubwayLine],
        network: SubwayNetwork, options: Options
    ) throws -> Journey {
        var path = [end]
        var cursor = end
        while let previous = parent[cursor] {
            path.append(previous)
            cursor = previous
        }
        path.reverse()

        var legs: [Journey.Leg] = []
        var index = 0
        while index < path.count {
            let line = lines[path[index].line]
            var last = index
            while last + 1 < path.count, path[last + 1].line == path[index].line { last += 1 }

            if last > index {
                let from = path[index].index
                let to = path[last].index
                let step = path[index + 1].index
                let count = line.stations.count
                let forward = step == (from + 1) % count
                let trip = try TripPlanner.plan(
                    on: line,
                    from: line.stations[from].id,
                    to: line.stations[to].id,
                    direction: forward ? .forward : .backward)
                let transfer = legs.isEmpty ? 0 : transferSeconds(
                    on: network, at: line.stations[from].name,
                    from: lines[path[index - 1].line].lineName, to: line.lineName, options: options)
                legs.append(Journey.Leg(lineID: line.id, trip: trip, transferSeconds: transfer))
            }
            index = last + 1
        }

        guard !legs.isEmpty else { throw PlanError.noRoute }
        return Journey(legs: legs)
    }
}
