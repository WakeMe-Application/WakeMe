import Foundation

/// 역. `id`는 공공 역코드 (예: 2호선 강남 "222").
public struct Station: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let nameEn: String
    /// 환승 노선 이름 (예: ["신분당"])
    public let transfers: [String]
}

public enum Direction: String, Codable, Hashable, Sendable {
    /// 역 목록 순서대로 (2호선 내선순환)
    case forward
    /// 역 목록 역순 (2호선 외선순환)
    case backward
}

public struct SubwayLine: Codable, Hashable, Identifiable, Sendable {
    public struct DirectionNames: Codable, Hashable, Sendable {
        public let forward: String
        public let backward: String
    }

    public let id: String
    public let name: String
    /// 노선 배지에 쓰는 짧은 이름 (예: "2")
    public let shortName: String
    /// 계통 이름에서 노선 부분만 ("1호선 인천" → "1호선"). 환승 데이터 조회에 쓴다.
    public let baseName: String?
    public let colorHex: String
    public let isCircular: Bool
    public let directionNames: DirectionNames
    /// 역간 주행 시간 추정치(초). 공공데이터·골든 라이드 실측으로 교체 예정.
    public let defaultRunSeconds: TimeInterval
    /// 역 정차 시간 추정치(초)
    public let defaultDwellSeconds: TimeInterval
    /// 구간별 주행 시간(초). 인덱스 i는 stations[i] → stations[i+1] 구간이고,
    /// 순환선이면 마지막 원소가 종점→기점 구간이다. 없으면 defaultRunSeconds를 쓴다.
    public let segmentSeconds: [TimeInterval]?
    public let stations: [Station]

    /// 이웃한 두 역 사이 주행 시간
    public func runSeconds(from: Int, to: Int) -> TimeInterval {
        // 순환선에서 종점↔기점으로 넘어가는 구간은 마지막 원소를 쓴다
        let index = abs(from - to) == 1 ? min(from, to) : stations.count - 1
        guard let segmentSeconds, segmentSeconds.indices.contains(index) else { return defaultRunSeconds }
        return segmentSeconds[index]
    }

    /// 계통이 아니라 노선 단위 이름
    public var lineName: String { baseName ?? name }

    public func directionName(_ direction: Direction) -> String {
        direction == .forward ? directionNames.forward : directionNames.backward
    }

    public func index(of stationID: String) -> Int? {
        stations.firstIndex { $0.id == stationID }
    }

    public func station(id: String) -> Station? {
        stations.first { $0.id == id }
    }

    public func station(named name: String) -> Station? {
        stations.first { $0.name == name }
    }
}

/// 이름이 같은 역을 노선에 상관없이 하나로 묶은 것 — 역 선택 화면이 다루는 단위.
/// 같은 역이 여러 노선·지선에 있어도 목록에는 한 번만 나온다.
public struct StationGroup: Hashable, Identifiable, Sendable {
    public let name: String
    public let nameEn: String
    public let entries: [StationEntry]

    public var id: String { name }
    /// 이 역을 지나는 노선. 같은 노선의 계통·지선(1호선 인천행/신창행 등)은 하나로 센다.
    public var lines: [SubwayLine] {
        var seen = Set<String>()
        return entries.map(\.line).filter { seen.insert("\($0.shortName)|\($0.colorHex)").inserted }
    }

    public static func == (lhs: StationGroup, rhs: StationGroup) -> Bool { lhs.name == rhs.name }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

/// 노선에 속한 역 한 곳 — 검색 결과·루틴 등 UI가 다루는 단위.
public struct StationEntry: Hashable, Identifiable, Sendable {
    public let line: SubwayLine
    public let station: Station

    public var id: String { "\(line.id)-\(station.id)" }

    public static func == (lhs: StationEntry, rhs: StationEntry) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 환승역에서 노선을 갈아탈 때 걷는 시간 (서울교통공사 실측, 열차 대기는 빠져 있다)
public struct TransferTime: Codable, Hashable, Sendable {
    public let station: String
    public let from: String
    public let to: String
    public let walkSeconds: TimeInterval
}

public struct SubwayNetwork: Codable, Sendable {
    public let version: String
    public let lines: [SubwayLine]
    public let transfers: [TransferTime]?

    /// 실측 환승 도보 시간. 데이터가 없으면 nil.
    public func transferWalkSeconds(at station: String, from: String, to: String) -> TimeInterval? {
        transfers?.first { $0.station == station && $0.from == from && $0.to == to }?.walkSeconds
    }

    /// 앱 번들에 포함된 노선 데이터 (Resources/network.json)
    public static func bundled() throws -> SubwayNetwork {
        guard let url = Bundle.module.url(forResource: "network", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(SubwayNetwork.self, from: Data(contentsOf: url))
    }

    public var stationCount: Int {
        lines.reduce(0) { $0 + $1.stations.count }
    }

    public func line(id: String) -> SubwayLine? {
        lines.first { $0.id == id }
    }

    public func entry(lineID: String, stationID: String) -> StationEntry? {
        guard let line = line(id: lineID), let station = line.station(id: stationID) else { return nil }
        return StationEntry(line: line, station: station)
    }

    public var allEntries: [StationEntry] {
        lines.flatMap { line in line.stations.map { StationEntry(line: line, station: $0) } }
    }

    /// 이름이 같은 역을 묶은 검색 결과. 역 선택 화면은 이 단위를 쓴다.
    public func searchGrouped(_ query: String) -> [StationGroup] {
        var grouped: [String: [StationEntry]] = [:]
        var order: [String] = []
        for entry in search(query) {
            if grouped[entry.station.name] == nil { order.append(entry.station.name) }
            grouped[entry.station.name, default: []].append(entry)
        }
        return order.map { name in
            let entries = grouped[name] ?? []
            return StationGroup(name: name, nameEn: entries.first?.station.nameEn ?? "", entries: entries)
        }
    }

    /// 역 이름·영문 이름 부분 일치 검색. 이름이 검색어로 시작하는 역을 먼저 보여준다.
    public func search(_ query: String) -> [StationEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allEntries }
        return allEntries
            .filter { $0.station.name.contains(q) || $0.station.nameEn.localizedCaseInsensitiveContains(q) }
            .sorted { lhs, rhs in
                let l = lhs.station.name.hasPrefix(q), r = rhs.station.name.hasPrefix(q)
                return l != r ? l : lhs.station.name < rhs.station.name
            }
    }
}
