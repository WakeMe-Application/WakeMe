import AlarmKit
import Foundation
import SwiftUI

/// 하차 알림에 붙이는 부가 정보. AlarmKit이 요구하는 형식이다.
struct AlightAlarmMetadata: AlarmMetadata {
    let destination: String
}

/// 하차 알림을 **시스템 알람**으로도 건다.
///
/// 일반 로컬 알림(`NotificationScheduler`)은 무음 스위치나 집중 모드에서 막힐 수 있다.
/// 이 앱의 약속은 "잠이 들어도 됩니다"인데, 막히면 그 약속이 통째로 깨진다.
/// AlarmKit은 시계 앱 알람과 같은 취급이라 무음에서도 울린다.
///
/// 로컬 알림을 대체하지 않고 **겹쳐서** 쓴다. 1차 준비 알림처럼 가벼운 것까지
/// 알람으로 울리면 시끄러우므로, **2차 하차 알림 하나에만** 건다.
@MainActor
enum AlarmScheduler {
    /// 탑승 1회에 하나만 쓴다. 다시 예약하면 이 id로 덮어쓴다.
    private static let alightID = UUID(uuidString: "A1A1A1A1-0000-4000-8000-00000000A11E")!

    static var isAuthorized: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    /// 권한은 실제로 알람을 걸기 직전에만 묻는다 (온보딩에서 한꺼번에 묻지 않는다)
    @discardableResult
    static func requestAuthorization() async -> Bool {
        if isAuthorized { return true }
        return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
    }

    /// - Parameter seconds: 지금부터 하차 알림까지 남은 시간
    static func scheduleAlight(in seconds: TimeInterval, destination: String, tint: Color) async {
        cancel()
        guard seconds > 0, await requestAuthorization() else { return }

        let alert = AlarmPresentation.Alert(
            title: "\(destination)에서 내리세요",
            stopButton: AlarmButton(
                text: "일어났어요", textColor: .white, systemImageName: "checkmark"))
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: AlightAlarmMetadata(destination: destination),
            tintColor: tint)

        // 남은 시간을 세는 타이머로 건다. 절대 시각이 아니라 남은 시간이라
        // 위치 보정으로 도착 예정이 바뀌면 다시 걸어 주면 된다.
        let configuration = AlarmManager.AlarmConfiguration.timer(
            duration: seconds, attributes: attributes)
        _ = try? await AlarmManager.shared.schedule(id: alightID, configuration: configuration)
    }

    static func cancel() {
        try? AlarmManager.shared.cancel(id: alightID)
    }
}
