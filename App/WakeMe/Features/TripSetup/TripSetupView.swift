import SwiftUI
import WakeMeEngine

/// 경로 확인 — 구간·환승·알림 시점을 보여 주고 출발 준비로 넘어간다.
struct TripSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: TripDraft
    @State private var saveAsRoutine = false
    @State private var routineName = "출근"

    private var journey: Journey { draft.journey }
    private var finalTrip: Trip { journey.legs[journey.legs.count - 1].trip }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summary
                    preferencePicker
                    legsCard
                    alertsCard
                    if let alternative = draft.alternative { directionSwitch(alternative) }
                    if !draft.hasTransfer { routineCard }
                }
                .padding(20)
            }
            .background(DS.background)
            .bottomCTA {
                Button("승강장에서 출발 준비") { start() }
                    .buttonStyle(.cta(draft.line.color))
            }
            .navigationTitle("경로 확인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(draft.lines, id: \.id) { line in
                    LineBadge(shortName: line.shortName, colorHex: line.colorHex, size: 26)
                }
                Text(draft.hasTransfer ? "환승 \(journey.transferCount)회" : draft.line.directionName(draft.trip.direction))
                    .font(DS.label.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            RouteHeadline(
                origin: journey.origin.name, destination: journey.destination.name,
                font: .system(size: 30, weight: .heavy))
            HStack(spacing: 8) {
                Chip(text: TripFormat.stops(journey.stopCount), systemImage: "tram.fill", tint: draft.line.color)
                Chip(text: TripFormat.minutes(journey.duration), systemImage: "clock.fill", tint: draft.line.color)
            }
        }
    }

    /// 빠른 길 / 환승 적게
    private var preferencePicker: some View {
        Picker("", selection: Binding(
            get: { draft.preference },
            set: { preference in
                guard let replanned = model.plannedDraft(
                    from: journey.origin.name, to: journey.destination.name, preference: preference)
                else { return }
                withAnimation(.snappy) { draft = replanned }
            })) {
                Text("빠른 길").tag(JourneyPlanner.Options.Preference.fastest)
                Text("환승 적게").tag(JourneyPlanner.Options.Preference.fewestTransfers)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
    }

    /// 구간과 환승역
    private var legsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(journey.legs.enumerated()), id: \.offset) { index, leg in
                    if index > 0 {
                        transferRow(at: leg.trip.origin.name, seconds: leg.transferSeconds)
                    }
                    legRow(leg, line: draft.line(of: leg))
                }
            }
        }
    }

    private func legRow(_ leg: Journey.Leg, line: SubwayLine?) -> some View {
        HStack(spacing: 14) {
            if let line {
                LineBadge(shortName: line.shortName, colorHex: line.colorHex, size: 28)
            }
            VStack(alignment: .leading, spacing: 3) {
                RouteHeadline(
                    origin: leg.trip.origin.name, destination: leg.trip.destination.name, font: DS.bodyBold)
                Text([
                    line?.name,
                    line.map { $0.directionName(leg.trip.direction) },
                    TripFormat.summary(stops: leg.trip.stopCount, seconds: leg.trip.duration),
                ].compactMap { $0 }.joined(separator: " · "))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private func transferRow(at station: String, seconds: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.swap")
                .font(DS.caption.weight(.bold))
            Text("\(station)에서 환승 · 약 \(Int(seconds / 60))분")
                .font(DS.caption.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.primary)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(DS.primary.opacity(0.1), in: .rect(cornerRadius: 12))
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("하차 알림", systemImage: "bell.badge.fill")
                .font(DS.headline)
            ForEach(alertRows, id: \.title) { row in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 10, height: 10)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(DS.label.weight(.bold))
                        Text(row.detail).font(DS.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(DS.surface, in: .rect(cornerRadius: DS.cardRadius))
    }

    private func directionSwitch(_ alternative: Journey) -> some View {
        Button {
            withAnimation(.snappy) { draft.switchDirection() }
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("\(draft.line.directionName(alternative.legs[0].trip.direction))으로 가기")
                Spacer()
                Text(TripFormat.stops(alternative.stopCount))
                    .foregroundStyle(.secondary)
            }
            .font(DS.label.weight(.semibold))
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(DS.surface, in: .rect(cornerRadius: DS.controlRadius))
        }
        .buttonStyle(.plain)
    }

    private var routineCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $saveAsRoutine.animation(.snappy)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("루틴으로 저장").font(DS.bodyBold)
                        Text("다음부터 홈에서 한 번에 출발해요")
                            .font(DS.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if saveAsRoutine {
                    Picker("이름", selection: $routineName) {
                        ForEach(["출근", "퇴근", "등교", "하교", "자주 가는 길"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private struct AlertRow {
        let title: String
        let detail: String
        let color: Color
    }

    /// 알림은 마지막 구간(실제 하차) 기준으로 보여 준다
    private var alertRows: [AlertRow] {
        let trip = finalTrip
        let policy = model.store.settings.alertPolicy
        let dest = trip.destinationIndex
        return trip.alerts(policy: policy).map { alert in
            switch alert.kind {
            case .prepare:
                let station = trip.stops[dest - policy.prepareStopsBefore].station.name
                return AlertRow(title: "곧 내릴 준비", detail: "\(station) 출발 후 · 진동 1회", color: BoardPalette.prepare)
            case .alightNow:
                let from = dest - 1 == 0 ? "출발 직후" : "\(trip.stops[dest - 1].station.name) 출발 후"
                return AlertRow(title: "다음 역에서 내리세요", detail: "\(from) · 문 열림 약 1분 30초 전", color: BoardPalette.current)
            case .arrived:
                return AlertRow(
                    title: "\(trip.destination.name) 도착",
                    detail: "확인할 때까지 20초 간격으로 반복", color: BoardPalette.current)
            }
        }
    }

    private func start() {
        if saveAsRoutine, !draft.hasTransfer { model.saveRoutine(named: routineName, for: draft) }
        model.startFromSetup(draft)
    }
}
