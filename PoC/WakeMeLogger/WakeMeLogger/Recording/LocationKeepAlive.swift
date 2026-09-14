import CoreLocation

/// 백그라운드 위치 업데이트로 앱을 살려둔다 — iOS 우선 전략의 Go/No-go 대상.
/// 위치도 기록하지만(지상 구간·승하차 추정용), 주 목적은 잠금 상태에서 앱이 정지되지 않게 하는 것.
@MainActor
final class LocationKeepAlive: NSObject {
    enum Accuracy: String, CaseIterable, Identifiable, Sendable {
        case kilometer = "1km"
        case hundredMeters = "100m"
        case best = "최고"

        var id: String { rawValue }

        var value: CLLocationAccuracy {
            switch self {
            case .kilometer: kCLLocationAccuracyKilometer
            case .hundredMeters: kCLLocationAccuracyHundredMeters
            case .best: kCLLocationAccuracyBest
            }
        }
    }

    var onLocation: ((CLLocation) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation             // 기차·배 등 자동차가 아닌 이동수단
        manager.pausesLocationUpdatesAutomatically = false  // 정차 중 자동 일시정지 → 앱 정지 방지 (핵심)
        manager.showsBackgroundLocationIndicator = true
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// 반드시 포그라운드에서 호출해야 백그라운드로 이어진다.
    func start(accuracy: Accuracy) {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.desiredAccuracy = accuracy.value
        manager.allowsBackgroundLocationUpdates = true  // Info.plist UIBackgroundModes: location 필요
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }
}

extension LocationKeepAlive: CLLocationManagerDelegate {
    // 델리게이트는 매니저를 만든 메인 스레드에서 호출된다
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            locations.forEach { onLocation?($0) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            onAuthorizationChange?(status)
        }
    }
}
