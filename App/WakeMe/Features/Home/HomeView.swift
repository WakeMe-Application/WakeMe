import SwiftUI
import WakeMeEngine

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isPickingRoute = false
    @State private var pickedRoute: (origin: StationGroup, destination: StationGroup)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        WakeMeWordmark(size: 30)
                        ScreenHeader(
                            title: "어디서\n내리세요?",
                            subtitle: "내릴 역만 알려주시면 전역 출발 때부터 챙길게요")
                    }
                    if let session = model.session { ongoingBanner(session) }
                    searchButton
                    if !model.store.routines.isEmpty { routinesSection }
                    if !model.store.recents.isEmpty { recentsSection }
                    footnote
                }
                .padding(.horizontal, DS.screenPadding)
                .padding(.bottom, 40)
            }
            .background(DS.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("설정", systemImage: "gearshape") { model.showSettings = true }
                }
            }
            .onAppear {
                if model.debugShowPicker { isPickingRoute = true }
            }
            .sheet(isPresented: $isPickingRoute, onDismiss: openPickedRoute) {
                RoutePickerFlow { origin, destination in
                    pickedRoute = (origin, destination)
                }
            }
        }
    }

    /// 탑승 중에 다른 앱을 갔다 오거나 실수로 나가면 홈으로 떨어진다.
    /// 세션은 살아 있는데 돌아갈 입구가 없었다.
    private func ongoingBanner(_ session: TripSession) -> some View {
        Button {
            model.presentPendingTrip()
        } label: {
            HStack(spacing: 12) {
                LineBadge(shortName: session.line.shortName, colorHex: session.line.colorHex, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("안내 중")
                        .font(DS.caption.weight(.bold))
                        .foregroundStyle(DS.primary)
                    Text("\(session.finalDestination.name)까지 \(session.snapshot.stopsRemaining)정거장")
                        .font(DS.label.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(16)
            .background(DS.primary.opacity(0.12), in: .rect(cornerRadius: DS.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityHint("탑승 화면으로 돌아갑니다")
    }

    private var searchButton: some View {
        Button {
            isPickingRoute = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(DS.headline)
                Text("도착역 검색")
                    .font(DS.headline)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .frame(height: 62)
            .background(DS.surface, in: .rect(cornerRadius: DS.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "루틴")
            ForEach(model.store.routines) { routine in
                if let card = RoutineCardData(routine: routine, model: model) {
                    RoutineCard(data: card) { model.startRoutine(routine) }
                        .contextMenu {
                            Button("루틴 삭제", systemImage: "trash", role: .destructive) {
                                model.store.routines.removeAll { $0.id == routine.id }
                            }
                        }
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "최근")
            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(model.store.recents.prefix(5).enumerated()), id: \.offset) { index, recent in
                        if index > 0 {
                            Divider().background(DS.separator).padding(.leading, 62)
                        }
                        recentRow(recent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentRow(_ recent: RecentTrip) -> some View {
        if let draft = model.draft(
            lineID: recent.lineID, originID: recent.originID,
            destinationID: recent.destinationID, direction: recent.direction)
        {
            PressableRow {
                model.setupDraft = draft
            } content: {
                HStack(spacing: 14) {
                    LineBadge(shortName: draft.line.shortName, colorHex: draft.line.colorHex, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        RouteHeadline(
                            origin: draft.trip.origin.name, destination: draft.trip.destination.name,
                            font: DS.headline)
                        Text(TripFormat.summary(stops: draft.trip.stopCount, seconds: draft.trip.duration))
                            .font(DS.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(DS.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
    }

    private var footnote: some View {
        Text("수도권 \(model.network.lines.count)개 노선 · \(model.network.stationCount)개 역 · 소요시간은 추정치예요")
            .font(DS.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
    }

    private func openPickedRoute() {
        guard let route = pickedRoute else { return }
        pickedRoute = nil
        model.openSetup(origin: route.origin, destination: route.destination)
    }
}

private struct RoutineCardData {
    let routine: Routine
    let line: SubwayLine
    let trip: Trip

    @MainActor
    init?(routine: Routine, model: AppModel) {
        guard let draft = model.draft(
            lineID: routine.lineID, originID: routine.originID,
            destinationID: routine.destinationID, direction: routine.direction)
        else { return nil }
        self.routine = routine
        line = draft.line
        trip = draft.trip
    }
}

private struct RoutineCard: View {
    let data: RoutineCardData
    let start: () -> Void

    var body: some View {
        SurfaceCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        LineBadge(shortName: data.line.shortName, colorHex: data.line.colorHex, size: 24)
                        Text(data.routine.name)
                            .font(DS.label.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    RouteHeadline(
                        origin: data.trip.origin.name, destination: data.trip.destination.name,
                        font: DS.title)
                    Text("\(data.line.directionName(data.trip.direction)) · \(TripFormat.summary(stops: data.trip.stopCount, seconds: data.trip.duration))")
                        .font(DS.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(action: start) {
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(data.line.color, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(data.routine.name) 출발")
            }
        }
    }
}
