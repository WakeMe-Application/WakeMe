import CoreLocation

/// 탑승 중 백그라운드 위치 업데이트로 앱을 살려 둔다 (가설 H5).
/// 앱이 살아 있어야 잠금 상태에서도 Live Activity의 "이번 역"을 갱신할 수 있다.
@MainActor
final class LocationKeepAlive: NSObject {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation             // 기차·배 등 자동차가 아닌 이동수단
        manager.pausesLocationUpdatesAutomatically = false  // 정차 중 자동 일시정지 → 앱 정지 방지
        manager.showsBackgroundLocationIndicator = true
        manager.desiredAccuracy = kCLLocationAccuracyKilometer  // 지하에선 GPS 불가 → 배터리 절약
    }

    /// 반드시 포그라운드에서 호출해야 백그라운드로 이어진다.
    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }
}

extension LocationKeepAlive: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 위치 값 자체는 아직 쓰지 않는다 — 앱 생존이 목적
    }
}
