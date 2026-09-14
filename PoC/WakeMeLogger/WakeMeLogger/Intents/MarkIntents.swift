import AppIntents

/// 액션 버튼에 지정해 화면을 보지 않고 정답 라벨을 남긴다.
/// 설정 > 동작 버튼 > 단축어 > "깨워줘 로거 · 정차 마킹"
struct MarkStopIntent: AppIntent {
    static let title: LocalizedStringResource = "정차 마킹"
    static let description = IntentDescription("열차가 역에 정차해 문이 열린 순간을 기록합니다.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        markResult(.stop)
    }
}

struct MarkDepartIntent: AppIntent {
    static let title: LocalizedStringResource = "출발 마킹"
    static let description = IntentDescription("열차가 역을 출발한 순간을 기록합니다.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        markResult(.depart)
    }
}

@MainActor
private func markResult(_ kind: MarkKind) -> some IntentResult & ProvidesDialog {
    guard let seq = RideRecorder.shared.mark(kind, source: "intent") else {
        return .result(dialog: "기록 중인 탑승이 없어요")
    }
    return .result(dialog: "\(kind.label) #\(seq)")
}

struct LoggerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkStopIntent(),
            phrases: ["\(.applicationName) 정차 기록"],
            shortTitle: "정차 마킹",
            systemImageName: "tram.fill")
        AppShortcut(
            intent: MarkDepartIntent(),
            phrases: ["\(.applicationName) 출발 기록"],
            shortTitle: "출발 마킹",
            systemImageName: "arrow.right.circle.fill")
    }
}
