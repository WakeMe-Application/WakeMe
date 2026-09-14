import CoreLocation
import Observation
import UIKit

enum PhonePosition: String, CaseIterable, Identifiable, Sendable {
    case pocket = "주머니"
    case hand = "손"
    case bag = "가방"
    case mount = "거치"

    var id: String { rawValue }
}

enum MarkKind: String, Sendable {
    case stop = "STOP"              // 역 정차 (문 열림)
    case depart = "DEPART"          // 출발
    case tunnelStop = "TUNNEL_STOP" // 역이 아닌 곳에서 정차 (신호대기)
    case note = "NOTE"

    var label: String {
        switch self {
        case .stop: "정차"
        case .depart: "출발"
        case .tunnelStop: "터널 정차"
        case .note: "메모"
        }
    }
}

struct RideSetup: Sendable {
    var line = ""
    var fromStation = ""
    var toStation = ""
    var direction = ""
    var phonePosition: PhonePosition = .pocket
    var accuracy: LocationKeepAlive.Accuracy = .kilometer
    var motionHz = 25
}

/// 탑승 기록 세션을 제어한다. UI와 App Intent(액션 버튼)가 같은 인스턴스를 공유한다.
@MainActor
@Observable
final class RideRecorder {
    static let shared = RideRecorder()

    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var currentFileURL: URL?
    private(set) var snapshot = SensorHub.Snapshot()
    private(set) var markCount = 0
    private(set) var lastMark: MarkKind?
    private(set) var locationCount = 0
    private(set) var batteryAtStart: Double = -1
    private(set) var battery: Double = -1
    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastError: String?

    private let location = LocationKeepAlive()
    private var hub: SensorHub?
    private var tickTask: Task<Void, Never>?

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        authorization = location.authorizationStatus
        location.onAuthorizationChange = { [weak self] status in
            self?.authorizationChanged(status)
        }
        location.onLocation = { [weak self] location in
            self?.record(location)
        }
    }

    func start(_ setup: RideSetup) {
        guard !isRecording else { return }
        let now = Date()
        let fileURL = RideStore.newFileURL(startedAt: now)
        let hub: SensorHub
        do {
            hub = try SensorHub(fileURL: fileURL)
        } catch {
            lastError = "로그 파일을 만들 수 없어요: \(error.localizedDescription)"
            return
        }

        let battery = Self.currentBattery
        var line = LogLine("session_start", t: now.timeIntervalSince1970)
        line.add("line", setup.line)
        line.add("from", setup.fromStation)
        line.add("to", setup.toStation)
        line.add("direction", setup.direction)
        line.add("phone_position", setup.phonePosition.rawValue)
        line.add("location_accuracy", setup.accuracy.rawValue)
        line.add("motion_hz", setup.motionHz)
        line.add("device", Self.deviceModel)
        line.add("os", UIDevice.current.systemVersion)
        line.add("app_version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
        line.add("low_power_mode", ProcessInfo.processInfo.isLowPowerModeEnabled)
        line.add("battery", battery, digits: 2)
        hub.log(line)

        hub.start(motionHz: Double(setup.motionHz))
        location.start(accuracy: setup.accuracy)

        self.hub = hub
        isRecording = true
        startedAt = now
        currentFileURL = fileURL
        snapshot = SensorHub.Snapshot()
        markCount = 0
        lastMark = nil
        locationCount = 0
        batteryAtStart = battery
        self.battery = battery
        lastError = nil
        startTicking()
    }

    func stop(reason: String = "user") {
        guard isRecording, let hub else { return }
        tickTask?.cancel()
        tickTask = nil
        location.stop()
        hub.heartbeat(battery: Self.currentBattery, appState: Self.appStateName)
        hub.stop(reason: reason)
        self.hub = nil
        isRecording = false
        currentFileURL = nil
    }

    /// 정차·출발 등 정답 라벨. 앱 버튼과 액션 버튼(App Intent) 양쪽에서 호출된다.
    /// - Returns: 마크 순번. 기록 중이 아니면 nil.
    @discardableResult
    func mark(_ kind: MarkKind, source: String, note: String? = nil) -> Int? {
        guard isRecording, let hub else { return nil }
        markCount += 1
        lastMark = kind
        var line = LogLine("mark", t: LogLine.now)
        line.add("kind", kind.rawValue)
        line.add("seq", markCount)
        line.add("source", source)
        if let note, !note.isEmpty { line.add("note", note) }
        hub.log(line)
        return markCount
    }

    func logAppState(_ state: String) {
        guard let hub else { return }
        var line = LogLine("app_state", t: LogLine.now)
        line.add("state", state)
        hub.log(line)
    }

    // MARK: - Private

    private func record(_ location: CLLocation) {
        guard let hub else { return }
        locationCount += 1
        var line = LogLine("location", t: location.timestamp.timeIntervalSince1970)
        line.add("lat", location.coordinate.latitude, digits: 6)
        line.add("lon", location.coordinate.longitude, digits: 6)
        line.add("h_acc", location.horizontalAccuracy, digits: 1)
        line.add("speed", location.speed, digits: 2)
        hub.log(line)
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        authorization = status
        guard let hub else { return }
        var line = LogLine("authorization", t: LogLine.now)
        line.add("location", Int(status.rawValue))
        hub.log(line)
    }

    /// 1초마다 화면 통계 갱신, 10초마다 하트비트 기록.
    private func startTicking() {
        tickTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, let hub = self.hub else { return }
                self.battery = Self.currentBattery
                if tick % 10 == 0 {
                    hub.heartbeat(battery: self.battery, appState: Self.appStateName)
                }
                self.snapshot = hub.snapshot()
                tick += 1
            }
        }
    }

    private static var currentBattery: Double {
        Double(UIDevice.current.batteryLevel)  // 시뮬레이터에서는 -1
    }

    private static var appStateName: String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
