import WakeMeEngine
import UserNotifications

/// 하차 알림을 로컬 알림으로 예약한다.
/// 시간 모델은 결정적이라 미리 예약해 두면 앱이 정지돼도 울린다. 보정·설정 변경 시 다시 예약한다.
enum NotificationScheduler {
    /// 3차(도착) 알림 반복 간격 — 졸음 페르소나용. 사용자가 "내렸어요"를 누르면 취소된다.
    private static let arrivedRepeats: [TimeInterval] = [0, 20, 40]
    private static let identifierPrefix = "trip-alert"

    static func requestAuthorization() async -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    }

    /// - Parameter isTransfer: 이 구간의 끝이 환승역이면 문구를 환승으로 바꾼다
    static func schedule(
        _ alerts: [ScheduledAlert], trip: Trip, policy: AlertPolicy,
        soundEnabled: Bool, isTransfer: Bool = false
    ) {
        cancelAll()
        let center = UNUserNotificationCenter.current()
        let now = Date()
        for item in alerts {
            let repeats = item.alert.kind == .arrived ? arrivedRepeats : [0]
            for (index, delay) in repeats.enumerated() {
                let fireDate = item.date.addingTimeInterval(delay)
                guard fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                (content.title, content.body) = copy(
                    for: item.alert.kind, trip: trip, policy: policy,
                    isRepeat: index > 0, isTransfer: isTransfer)
                content.interruptionLevel = .timeSensitive
                content.sound = soundEnabled ? .default : nil

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, fireDate.timeIntervalSince(now)), repeats: false)
                let request = UNNotificationRequest(
                    identifier: identifier(item.alert.kind, index), content: content, trigger: trigger)
                center.add(request, withCompletionHandler: nil)
            }
        }
    }

    /// 설정의 "알림 테스트" — 실제 하차 알림과 **같은 방식**으로 한 번 쏜다.
    ///
    /// 이 앱의 약속은 "잠들어도 된다"인데, 지금까지는 실제로 지하철을 타 봐야만
    /// 내 폰에서 알림이 뚫리는지 알 수 있었다. 자기 전에 확인할 수 있어야 한다.
    /// 그래서 `interruptionLevel`·소리·문구를 실제와 똑같이 맞춘다.
    static func fireTest(soundEnabled: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = "이번 역에서 내리세요"
        content.body = "실제 하차 알림은 이렇게 울려요"
        content.interruptionLevel = .timeSensitive
        content.sound = soundEnabled ? .default : nil
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)-test",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancelAll() {
        let ids = [identifier(.prepare, 0), identifier(.alightNow, 0)]
            + arrivedRepeats.indices.map { identifier(.arrived, $0) }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func identifier(_ kind: TripAlert.Kind, _ index: Int) -> String {
        "\(identifierPrefix)-\(kind.rawValue)-\(index)"
    }

    private static func copy(
        for kind: TripAlert.Kind, trip: Trip, policy: AlertPolicy, isRepeat: Bool, isTransfer: Bool
    ) -> (String, String) {
        let destination = trip.destination.name
        switch kind {
        case .prepare:
            let what = isTransfer ? "환승" : "하차"
            return ("곧 \(what) 준비하세요", "\(destination)까지 \(policy.prepareStopsBefore)정거장 남았어요")
        case .alightNow:
            return isTransfer
                ? ("다음 역에서 갈아타세요", "\(destination) 환승 · 문 앞으로 이동하세요")
                : ("다음 역에서 내리세요", "\(destination) · 문 앞으로 이동하세요")
        case .arrived:
            if isTransfer {
                return ("\(destination) 환승", "갈아탈 열차로 이동하세요")
            }
            return isRepeat
                ? ("아직 안 내리셨나요?", "\(destination)입니다. 지금 내리세요")
                : ("\(destination) 도착", "지금 내리세요")
        }
    }
}

/// 앱이 앞에 떠 있을 때는 전광판 화면과 햅틱이 알림을 대신한다 — 배너는 띄우지 않고 알림 센터에만 남긴다.
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.list]
    }
}
