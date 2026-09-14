import Foundation

/// 한 노선 위의 탑승 계획. `stops[0]`이 출발역, 마지막이 목적지다.
public struct Trip: Codable, Hashable, Sendable {
    public struct Stop: Codable, Hashable, Sendable {
        public let station: Station
        /// 출발역을 출발한 뒤 이 역에 도착(문 열림)하기까지(초). 출발역은 0.
        public let arrivalOffset: TimeInterval
        /// 출발역을 출발한 뒤 이 역을 출발하기까지(초). 출발역은 0.
        public let departureOffset: TimeInterval
    }

    public let lineID: String
    public let direction: Direction
    public let stops: [Stop]

    public var origin: Station { stops[0].station }
    public var destination: Station { stops[destinationIndex].station }
    public var destinationIndex: Int { stops.count - 1 }
    /// 목적지까지 정거장 수
    public var stopCount: Int { stops.count - 1 }
    /// 출발역 출발부터 목적지 도착까지(초)
    public var duration: TimeInterval { stops[destinationIndex].arrivalOffset }
}

public enum TripPlanner {
    public enum PlanError: Error, Equatable {
        case stationNotFound(String)
        case sameStation
    }

    /// - Parameter direction: 순환선에서만 의미가 있다. nil이면 정거장 수가 적은 쪽을 고른다.
    public static func plan(
        on line: SubwayLine, from originID: String, to destinationID: String, direction: Direction? = nil
    ) throws -> Trip {
        guard let from = line.index(of: originID) else { throw PlanError.stationNotFound(originID) }
        guard let to = line.index(of: destinationID) else { throw PlanError.stationNotFound(destinationID) }
        guard from != to else { throw PlanError.sameStation }

        let count = line.stations.count
        let resolved: Direction
        if line.isCircular {
            let forwardStops = (to - from + count) % count
            resolved = direction ?? (forwardStops <= count - forwardStops ? .forward : .backward)
        } else {
            resolved = to > from ? .forward : .backward
        }

        var indices = [from]
        var index = from
        while index != to {
            index = resolved == .forward ? (index + 1) % count : (index - 1 + count) % count
            indices.append(index)
        }

        var stops: [Trip.Stop] = []
        var clock: TimeInterval = 0
        for (k, stationIndex) in indices.enumerated() {
            let station = line.stations[stationIndex]
            if k == 0 {
                stops.append(Trip.Stop(station: station, arrivalOffset: 0, departureOffset: 0))
                continue
            }
            clock += line.runSeconds(from: indices[k - 1], to: stationIndex)
            let arrival = clock
            clock += line.defaultDwellSeconds
            stops.append(Trip.Stop(station: station, arrivalOffset: arrival, departureOffset: clock))
        }
        return Trip(lineID: line.id, direction: resolved, stops: stops)
    }
}
