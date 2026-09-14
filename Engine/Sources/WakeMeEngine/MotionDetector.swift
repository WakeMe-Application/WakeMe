import Foundation

/// 가속도 한 샘플. 폰이 어느 방향으로 놓였는지와 무관하도록 **수평 가속도 크기**만 본다.
/// (중력 방향 성분을 뺀 나머지의 크기, m/s²)
public struct MotionSample: Hashable, Sendable {
    public let time: Date
    public let horizontalAcceleration: Double

    public init(time: Date, horizontalAcceleration: Double) {
        self.time = time
        self.horizontalAcceleration = horizontalAcceleration
    }
}

public enum MotionEvent: Hashable, Sendable {
    /// 열차가 멈춘 것으로 보이는 시각 (조용해지기 시작한 시점)
    case stopped(at: Date)
    /// 열차가 움직이기 시작한 것으로 보이는 시각
    case departed(at: Date)
}

/// 정차·출발 감지기.
///
/// 열차가 서면 수평 가속도가 조용해지고, 출발하면 한동안 흔들린다.
/// 신호대기·승객 움직임 같은 잡음에 흔들리지 않도록 이동평균과 지속시간 조건을 함께 본다.
/// OS를 모르는 순수 로직이라 기록한 탑승 로그로 그대로 재생·검증할 수 있다.
public struct StopDetector: Sendable {
    public struct Parameters: Hashable, Sendable {
        /// 조용함 판정 임계값 (m/s²)
        public var quietThreshold: Double
        /// 이 시간 이상 조용하면 정차로 본다
        public var quietDuration: TimeInterval
        /// 이 시간 이상 흔들리면 출발로 본다
        public var movingDuration: TimeInterval
        /// 이동평균 창
        public var window: TimeInterval

        public init(
            quietThreshold: Double = 0.25,
            quietDuration: TimeInterval = 8,
            movingDuration: TimeInterval = 4,
            window: TimeInterval = 3
        ) {
            self.quietThreshold = quietThreshold
            self.quietDuration = quietDuration
            self.movingDuration = movingDuration
            self.window = window
        }
    }

    public enum State: String, Hashable, Sendable {
        case unknown, moving, stopped
    }

    public let parameters: Parameters
    public private(set) var state: State = .unknown

    private var samples: [MotionSample] = []
    private var quietSince: Date?
    private var movingSince: Date?

    public init(parameters: Parameters = Parameters()) {
        self.parameters = parameters
    }

    /// 샘플 하나를 넣고, 상태가 바뀌었으면 이벤트를 돌려준다.
    public mutating func consume(_ sample: MotionSample) -> MotionEvent? {
        // self에 중복 접근하지 않도록 값을 먼저 꺼내 둔다
        let now = sample.time
        let span = parameters.window
        samples.append(sample)
        samples.removeAll { now.timeIntervalSince($0.time) > span }
        let level = samples.reduce(0.0) { $0 + $1.horizontalAcceleration } / Double(samples.count)

        if level < parameters.quietThreshold {
            movingSince = nil
            let since = quietSince ?? sample.time
            quietSince = since
            if state != .stopped, sample.time.timeIntervalSince(since) >= parameters.quietDuration {
                state = .stopped
                // 조용해지기 시작한 시각이 실제 정차 시각에 가깝다
                return .stopped(at: since)
            }
        } else {
            quietSince = nil
            let since = movingSince ?? sample.time
            movingSince = since
            if state != .moving, sample.time.timeIntervalSince(since) >= parameters.movingDuration {
                state = .moving
                return .departed(at: since)
            }
        }
        return nil
    }

    public mutating func reset() {
        state = .unknown
        samples.removeAll()
        quietSince = nil
        movingSince = nil
    }
}

public extension MotionSample {
    /// CoreMotion 값에서 수평 가속도 샘플을 만든다.
    ///
    /// 중력 방향 성분을 빼면 폰이 주머니에 어떻게 들어 있든 열차의 가감속만 남는다.
    /// 이 변환이 앱에만 있으면 기록한 로그를 재생할 때 같은 식을 다시 구현해야 하고,
    /// 그러면 튜닝한 임계값이 실제로 도는 코드와 어긋난다. 그래서 엔진에 둔다.
    ///
    /// - Parameters:
    ///   - userAcceleration: 중력이 제거된 가속도 (g 단위, `CMDeviceMotion.userAcceleration`)
    ///   - gravity: 중력 방향 벡터 (g 단위, `CMDeviceMotion.gravity`)
    init(
        time: Date,
        userAcceleration a: (x: Double, y: Double, z: Double),
        gravity g: (x: Double, y: Double, z: Double)
    ) {
        let norm = max(g.x * g.x + g.y * g.y + g.z * g.z, 0.0001)
        let along = (a.x * g.x + a.y * g.y + a.z * g.z) / norm
        let x = a.x - along * g.x
        let y = a.y - along * g.y
        let z = a.z - along * g.z
        self.init(time: time, horizontalAcceleration: (x * x + y * y + z * z).squareRoot() * 9.81)
    }
}
