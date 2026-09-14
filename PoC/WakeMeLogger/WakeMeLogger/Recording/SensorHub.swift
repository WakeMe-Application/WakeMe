import CoreMotion
import Foundation

/// 센서 수집과 파일 쓰기를 담당한다.
/// 모든 가변 상태는 `queue`에서만 접근하고, CoreMotion 콜백도 같은 큐(underlyingQueue)에서
/// 실행되도록 묶어 락 없이 직렬화한다.
final class SensorHub: @unchecked Sendable {
    struct Snapshot: Sendable {
        var motionSamples = 0
        var measuredHz = 0.0
        var maxGapSec = 0.0
        var pressureKPa: Double?
    }

    private let queue = DispatchQueue(label: "thisstop.logger.sensors", qos: .userInitiated)
    private let operationQueue = OperationQueue()
    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let activity = CMMotionActivityManager()
    private let writer: JSONLWriter
    /// CoreMotion 타임스탬프(부팅 후 경과 초) → Unix 시각 변환 오프셋
    private let bootOffset = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime

    private var motionSamples = 0
    private var lastMotionT: Double?
    private var maxGapSec = 0.0
    private var pressureKPa: Double?
    private var measuredHz = 0.0
    // 하트비트 구간 통계
    private var samplesSinceHeartbeat = 0
    private var maxGapSinceHeartbeat = 0.0
    private var lastHeartbeatT = LogLine.now

    init(fileURL: URL) throws {
        writer = try JSONLWriter(url: fileURL)
        operationQueue.underlyingQueue = queue
        operationQueue.maxConcurrentOperationCount = 1
    }

    func start(motionHz: Double) {
        motion.deviceMotionUpdateInterval = 1.0 / motionHz
        if motion.isDeviceMotionAvailable {
            motion.startDeviceMotionUpdates(to: operationQueue) { [weak self] data, _ in
                guard let self, let data else { return }
                self.record(data)
            }
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: operationQueue) { [weak self] data, _ in
                guard let self, let data else { return }
                self.record(data)
            }
        }
        if CMMotionActivityManager.isActivityAvailable() {
            activity.startActivityUpdates(to: operationQueue) { [weak self] data in
                guard let self, let data else { return }
                self.record(data)
            }
        }
    }

    func stop(reason: String) {
        motion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        activity.stopActivityUpdates()
        queue.async {
            var line = LogLine("session_end", t: LogLine.now)
            line.add("reason", reason)
            line.add("motion_samples", self.motionSamples)
            line.add("max_gap_s", self.maxGapSec, digits: 3)
            self.writer.append(line)
            self.writer.close()
        }
    }

    /// 어느 스레드에서든 호출 가능. 쓰기는 큐에서 직렬 처리된다.
    func log(_ line: LogLine) {
        queue.async { self.writer.append(line) }
    }

    /// 하트비트: 구간 샘플 수·실측 Hz·최대 공백을 기록하고 파일을 flush 한다.
    /// 앱이 정지(suspend)되면 하트비트 자체가 끊기므로, heartbeat 간격이 곧 생존 지표가 된다.
    func heartbeat(battery: Double, appState: String) {
        queue.async {
            let now = LogLine.now
            self.measuredHz = Double(self.samplesSinceHeartbeat) / max(now - self.lastHeartbeatT, 0.001)

            var line = LogLine("heartbeat", t: now)
            line.add("samples", self.samplesSinceHeartbeat)
            line.add("hz", self.measuredHz, digits: 1)
            line.add("max_gap_s", self.maxGapSinceHeartbeat, digits: 3)
            line.add("battery", battery, digits: 2)
            line.add("app_state", appState)
            self.writer.append(line)
            self.writer.flush()

            self.samplesSinceHeartbeat = 0
            self.maxGapSinceHeartbeat = 0
            self.lastHeartbeatT = now
        }
    }

    func snapshot() -> Snapshot {
        queue.sync {
            Snapshot(
                motionSamples: motionSamples,
                measuredHz: measuredHz,
                maxGapSec: maxGapSec,
                pressureKPa: pressureKPa)
        }
    }

    // MARK: - 센서 레코드 (queue에서 실행)

    private func record(_ data: CMDeviceMotion) {
        let t = bootOffset + data.timestamp
        if let last = lastMotionT {
            let gap = t - last
            maxGapSec = max(maxGapSec, gap)
            maxGapSinceHeartbeat = max(maxGapSinceHeartbeat, gap)
        }
        lastMotionT = t
        motionSamples += 1
        samplesSinceHeartbeat += 1

        // userAcceleration: 중력 제거 가속도(g), gravity: 자세 추정용, rotationRate: 손에 든 움직임 구분용
        var line = LogLine("motion", t: t)
        line.add("ax", data.userAcceleration.x)
        line.add("ay", data.userAcceleration.y)
        line.add("az", data.userAcceleration.z)
        line.add("gx", data.gravity.x, digits: 3)
        line.add("gy", data.gravity.y, digits: 3)
        line.add("gz", data.gravity.z, digits: 3)
        line.add("rx", data.rotationRate.x, digits: 3)
        line.add("ry", data.rotationRate.y, digits: 3)
        line.add("rz", data.rotationRate.z, digits: 3)
        writer.append(line)
    }

    private func record(_ data: CMAltitudeData) {
        let kPa = data.pressure.doubleValue
        pressureKPa = kPa
        var line = LogLine("pressure", t: bootOffset + data.timestamp)
        line.add("kpa", kPa, digits: 5)
        line.add("rel_alt_m", data.relativeAltitude.doubleValue, digits: 3)
        writer.append(line)
    }

    private func record(_ data: CMMotionActivity) {
        var line = LogLine("activity", t: bootOffset + data.timestamp)
        line.add("automotive", data.automotive)
        line.add("stationary", data.stationary)
        line.add("walking", data.walking)
        line.add("running", data.running)
        line.add("cycling", data.cycling)
        line.add("unknown", data.unknown)
        line.add("confidence", data.confidence.rawValue)
        writer.append(line)
    }
}
