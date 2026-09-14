import ActivityKit
import Foundation

/// 잠금화면·다이내믹 아일랜드 전광판. 앱이 살아 있는 동안 로컬로 갱신하므로 APNs가 필요 없다.
@MainActor
final class LiveActivityController {
    private var activity: Activity<TripActivityAttributes>?
    private var lastState: TripActivityAttributes.ContentState?

    func start(_ attributes: TripActivityAttributes, state: TripActivityAttributes.ContentState) {
        endImmediately()
        Self.endOrphanedActivities()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil)
        lastState = state
    }

    /// 상태가 바뀐 경우에만 갱신한다 (갱신 예산 절약)
    func update(_ state: TripActivityAttributes.ContentState) {
        guard let activity, state != lastState else { return }
        lastState = state
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// 도착 후 잠시 남겨 뒀다가 사라지게 한다
    func end(after seconds: TimeInterval = 60) {
        guard let activity else { return }
        let state = lastState
        self.activity = nil
        lastState = nil
        Task {
            let content = state.map { ActivityContent(state: $0, staleDate: nil) }
            await activity.end(content, dismissalPolicy: .after(.now + seconds))
        }
    }

    func endImmediately() {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 앱 프로세스가 강제 종료돼도 Live Activity는 남는다 — 새 탑승을 시작할 때 이전 것을 정리한다
    static func endOrphanedActivities() {
        for activity in Activity<TripActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
