import CoreLocation
import SwiftUI

struct ContentView: View {
    @State private var recorder = RideRecorder.shared
    @State private var setup = RideSetup()

    var body: some View {
        NavigationStack {
            Group {
                if recorder.isRecording {
                    RecordingView(recorder: recorder)
                } else {
                    SetupView(setup: $setup, recorder: recorder)
                }
            }
            .navigationTitle("깨워줘 로거")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RideListView(recorder: recorder)
                    } label: {
                        Label("기록", systemImage: "folder")
                    }
                }
            }
        }
    }
}

// MARK: - 시작 전

private struct SetupView: View {
    @Binding var setup: RideSetup
    let recorder: RideRecorder

    var body: some View {
        Form {
            Section("탑승 정보") {
                TextField("노선 (예: 2호선)", text: $setup.line)
                TextField("승차역", text: $setup.fromStation)
                TextField("하차역", text: $setup.toStation)
                TextField("방향 (예: 내선, 상행)", text: $setup.direction)
            }

            Section("실험 조건") {
                Picker("폰 위치", selection: $setup.phonePosition) {
                    ForEach(PhonePosition.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("위치 정확도", selection: $setup.accuracy) {
                    ForEach(LocationKeepAlive.Accuracy.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("모션 샘플링", selection: $setup.motionHz) {
                    Text("25Hz").tag(25)
                    Text("50Hz").tag(50)
                }
            }

            Section {
                Button {
                    recorder.start(setup)
                } label: {
                    Label("기록 시작", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } footer: {
                Text("승강장에서 시작한 뒤 잠금 상태로 탑승하세요. 역에 정차해 문이 열리는 순간마다 액션 버튼을 누르면 정답 라벨이 남습니다.")
            }

            if let warning = authorizationWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            if let error = recorder.lastError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }

    private var authorizationWarning: String? {
        switch recorder.authorization {
        case .denied, .restricted:
            "위치 권한이 꺼져 있으면 잠금 상태에서 앱이 정지돼 기록이 끊겨요. 설정에서 '앱을 사용하는 동안'으로 허용해 주세요."
        default:
            nil
        }
    }
}

// MARK: - 기록 중

private struct RecordingView: View {
    let recorder: RideRecorder
    @State private var showStopConfirm = false
    @State private var showNote = false
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsed(at: context.date))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                stats

                Button {
                    recorder.mark(.stop, source: "button")
                } label: {
                    Label("정차", systemImage: "tram.fill")
                        .font(.title.bold())
                        .frame(maxWidth: .infinity, minHeight: 110)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 12) {
                    markButton(.depart, systemImage: "arrow.right.circle")
                    markButton(.tunnelStop, systemImage: "pause.circle")
                    Button {
                        showNote = true
                    } label: {
                        Label("메모", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    showStopConfirm = true
                } label: {
                    Label("기록 종료", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: recorder.markCount)
        .confirmationDialog("기록을 종료할까요?", isPresented: $showStopConfirm, titleVisibility: .visible) {
            Button("종료", role: .destructive) { recorder.stop() }
        }
        .alert("메모", isPresented: $showNote) {
            TextField("예: 신호대기, 급정거", text: $note)
            Button("기록") {
                recorder.mark(.note, source: "button", note: note)
                note = ""
            }
            Button("취소", role: .cancel) { note = "" }
        }
    }

    private var stats: some View {
        let snapshot = recorder.snapshot
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "모션 샘플", value: "\(snapshot.motionSamples)")
            StatTile(title: "실측 Hz (10초)", value: String(format: "%.1f", snapshot.measuredHz))
            StatTile(
                title: "최대 공백",
                value: String(format: "%.2f초", snapshot.maxGapSec),
                isWarning: snapshot.maxGapSec > 1)
            StatTile(title: "배터리", value: batteryText)
            StatTile(title: "마크", value: markText)
            StatTile(title: "위치 수신", value: "\(recorder.locationCount)")
        }
    }

    private var batteryText: String {
        guard recorder.batteryAtStart >= 0 else { return "측정 불가" }
        return "\(Int(recorder.batteryAtStart * 100))% → \(Int(recorder.battery * 100))%"
    }

    private var markText: String {
        guard let last = recorder.lastMark else { return "0" }
        return "\(recorder.markCount) (\(last.label))"
    }

    private func elapsed(at date: Date) -> String {
        guard let start = recorder.startedAt else { return "0:00:00" }
        return Duration.seconds(date.timeIntervalSince(start))
            .formatted(.time(pattern: .hourMinuteSecond))
    }

    private func markButton(_ kind: MarkKind, systemImage: String) -> some View {
        Button {
            recorder.mark(kind, source: "button")
        } label: {
            Label(kind.label, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var isWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(isWarning ? .red : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
    }
}
