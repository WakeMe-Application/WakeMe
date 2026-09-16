import SwiftUI
import WakeMeEngine

struct SettingsView: View {
    @State private var testFired = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = model.store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    alertSection(store: store)
                    trackingSection(store: store)
                    realtimeSection(store: store)
                    routineSection(store: store)
                    developerSection(store: store)
                    infoSection
                }
                .padding(.horizontal, DS.screenPadding)
                .padding(.vertical, 12)
            }
            .background(DS.background)
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                        .font(DS.body.weight(.bold))
                }
            }
        }
    }

    // MARK: - 섹션

    private func alertSection(store: AppStore) -> some View {
        CardSection(title: "하차 알림", footnote: "2차 알림은 목적지 바로 전 역을 출발할 때 울려요. \"무음에서도 울리기\"를 켜면 시계 앱 알람처럼 울려서 무음·집중 모드를 뚫습니다(마지막 구간에만). 하차 피드백을 주시면 앞당김을 스스로 맞춰 갑니다.") {
            SettingRow(title: "1차 준비 알림") {
                Picker("", selection: Binding(get: { store.settings.prepareStopsBefore }, set: { store.settings.prepareStopsBefore = $0 })) {
                    Text("끔").tag(0)
                    Text("2정거장").tag(2)
                    Text("3정거장").tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            Divider().background(DS.separator)
            SettingRow(title: "2차 알림 앞당기기") {
                Picker("", selection: Binding(get: { store.settings.alightEarlierBy }, set: { store.settings.alightEarlierBy = $0 })) {
                    Text("안 함").tag(TimeInterval(0))
                    Text("30초").tag(TimeInterval(30))
                    Text("1분").tag(TimeInterval(60))
                    Text("1분 30초").tag(TimeInterval(90))
                    Text("2분").tag(TimeInterval(120))
                }
                // 피드백 자동 보정이 2분까지 닿아 선택지가 다섯이다.
                // 세그먼트로는 좁아 글자가 잘리므로 메뉴로 둔다.
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if let adjustment = store.settings.lastTimingAdjustment {
                Divider().background(DS.separator)
                Label(
                    """
                    하차 피드백을 반영해 \(adjustment.delta > 0 ? "30초 앞당겼어요" : "30초 늦췄어요"). \
                    지금은 \(TripFormat.duration(adjustment.resulting)) 앞당겨 울려요.
                    """,
                    systemImage: "wand.and.sparkles")
                    .font(DS.caption)
                    .foregroundStyle(DS.primary)
            }
            Divider().background(DS.separator)
            SettingRow(title: "무음에서도 울리기") {
                Toggle("", isOn: Binding(get: { store.settings.alarmEnabled }, set: { store.settings.alarmEnabled = $0 }))
                    .labelsHidden()
            }
            Divider().background(DS.separator)
            SettingRow(title: "이어폰 음성 안내") {
                Toggle("", isOn: Binding(get: { store.settings.voiceEnabled }, set: { store.settings.voiceEnabled = $0 }))
                    .labelsHidden()
            }
            Divider().background(DS.separator)
            SettingRow(title: "알림 소리") {
                Toggle("", isOn: Binding(get: { store.settings.soundEnabled }, set: { store.settings.soundEnabled = $0 }))
                    .labelsHidden()
            }
            Divider().background(DS.separator)
            Button {
                Task {
                    _ = await NotificationScheduler.requestAuthorization()
                    await NotificationScheduler.fireTest(soundEnabled: store.settings.soundEnabled)
                    testFired = true
                }
            } label: {
                Label("지금 알림 테스트", systemImage: "bell.badge.waveform.fill")
                    .font(DS.label.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if testFired {
                Text("2초 뒤에 울려요. 화면을 끄거나 무음으로 두고 실제로 들리는지 확인해 보세요.")
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trackingSection(store: AppStore) -> some View {
        CardSection(title: "탑승 추적", footnote: "위치는 탑승 중에만 써서 앱이 잠들지 않게 해요. 자동 감지는 가속도계로 정차·출발을 읽어 위치를 스스로 맞춥니다. 아직 실험 중이라 틀리면 노선도에서 역을 눌러 바로잡아 주세요.") {
            SettingRow(title: "잠금 중에도 전광판 갱신") {
                Toggle("", isOn: Binding(get: { store.settings.keepAliveEnabled }, set: { store.settings.keepAliveEnabled = $0 }))
                    .labelsHidden()
            }
            Divider().background(DS.separator)
            SettingRow(title: "정차 자동 감지 (실험)") {
                Toggle("", isOn: Binding(get: { store.settings.autoDetectEnabled }, set: { store.settings.autoDetectEnabled = $0 }))
                    .labelsHidden()
            }
        }
    }

    private func realtimeSection(store: AppStore) -> some View {
        CardSection(
            title: "실시간 열차위치",
            footnote: "기본 인증키가 앱에 들어 있어 따로 넣지 않아도 동작합니다. 서울 열린데이터광장에서 직접 발급받은 키를 넣으면 그 키를 씁니다(호출량이 본인 키로 잡힙니다)."
        ) {
            SettingRow(title: "실시간 정보로 보정") {
                Toggle("", isOn: Binding(get: { store.settings.realtimeEnabled }, set: { store.settings.realtimeEnabled = $0 }))
                    .labelsHidden()
            }
            Divider().background(DS.separator)
            VStack(alignment: .leading, spacing: 8) {
                Text("인증키")
                    .font(DS.body)
                TextField("기본 키 사용 중 — 직접 쓰려면 붙여넣으세요", text: Binding(
                    get: { store.settings.realtimeKey },
                    set: { store.settings.realtimeKey = $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
                    .font(DS.caption.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(DS.background, in: .rect(cornerRadius: 12))
            }
            .padding(.vertical, 12)
        }
    }

    private func routineSection(store: AppStore) -> some View {
        CardSection(title: "루틴") {
            if store.routines.isEmpty {
                Text("경로 확인 화면에서 루틴으로 저장할 수 있어요")
                    .font(DS.label)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            ForEach(Array(store.routines.enumerated()), id: \.element.id) { index, routine in
                if index > 0 { Divider().background(DS.separator) }
                HStack(spacing: 12) {
                    if let line = model.network.line(id: routine.lineID) {
                        LineBadge(shortName: line.shortName, colorHex: line.colorHex, size: 26)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.name).font(DS.body.weight(.bold))
                        Text(routeText(routine)).font(DS.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("삭제", systemImage: "trash") {
                        store.routines.removeAll { $0.id == routine.id }
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(DS.danger)
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func developerSection(store: AppStore) -> some View {
        CardSection(title: "개발", footnote: "시뮬레이터에서 탑승 한 번을 빠르게 확인할 때 써요. 다음 탑승부터 적용돼요.") {
            SettingRow(title: "데모 배속") {
                Picker("", selection: Binding(get: { store.settings.demoSpeed }, set: { store.settings.demoSpeed = $0 })) {
                    Text("실시간").tag(1.0)
                    Text("10배").tag(10.0)
                    Text("30배").tag(30.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
        }
    }

    private var infoSection: some View {
        CardSection(title: "정보") {
            InfoRow(label: "지원 노선", value: "수도권 \(model.network.lines.count)개 계통")
            Divider().background(DS.separator)
            InfoRow(label: "지원 역", value: "\(model.network.stationCount)개")
            Divider().background(DS.separator)
            InfoRow(label: "노선 데이터", value: model.network.version)
            Divider().background(DS.separator)
            InfoRow(label: "역간 소요시간", value: "1~8호선 실측 · 그 외 추정")
            Divider().background(DS.separator)
            InfoRow(label: "버전", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
        }
    }

    private func routeText(_ routine: Routine) -> String {
        guard let line = model.network.line(id: routine.lineID),
              let origin = line.station(id: routine.originID),
              let destination = line.station(id: routine.destinationID)
        else { return "" }
        return "\(origin.name) → \(destination.name) · \(line.directionName(routine.direction))"
    }
}

// MARK: - 조각

private struct CardSection<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DS.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            SurfaceCard(padding: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
            }
            if let footnote {
                Text(footnote)
                    .font(DS.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            Text(title).font(DS.body)
            Spacer(minLength: 12)
            control
        }
        .frame(minHeight: 44)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(DS.body)
            Spacer(minLength: 12)
            Text(value).font(DS.body).foregroundStyle(.secondary)
        }
        .frame(minHeight: 40)
    }
}
