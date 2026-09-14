import SwiftUI
import WakeMeEngine

/// 도착역을 먼저 고르고, 이어서 출발역을 고른다 (기획서: "목적지만 입력"에 가까운 순서).
/// 같은 이름의 역은 노선이 달라도 한 줄로 보여 주고, 노선 선택은 앱이 알아서 한다.
struct RoutePickerFlow: View {
    let onComplete: (_ origin: StationGroup, _ destination: StationGroup) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var destination: StationGroup?

    var body: some View {
        NavigationStack {
            StationList(title: "어디서 내리세요?", suggestions: []) { group in
                destination = group
            }
            .navigationDestination(item: $destination) { destination in
                StationList(
                    title: "어디서 타세요?",
                    subtitle: "\(destination.name) 방면",
                    excluded: destination,
                    suggestions: recentOrigins(excluding: destination)
                ) { origin in
                    onComplete(origin, destination)
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    /// 루틴·최근 경로에서 쓰던 출발역
    private func recentOrigins(excluding destination: StationGroup) -> [StationGroup] {
        let ids = model.store.routines.map { ($0.lineID, $0.originID) }
            + model.store.recents.map { ($0.lineID, $0.originID) }
        var seen = Set<String>()
        return ids.compactMap { lineID, stationID in
            guard let station = model.network.line(id: lineID)?.station(id: stationID),
                  let group = model.group(named: station.name),
                  group != destination,
                  seen.insert(group.name).inserted
            else { return nil }
            return group
        }
    }
}

private struct StationList: View {
    let title: String
    var subtitle: String?
    var excluded: StationGroup?
    let suggestions: [StationGroup]
    let onSelect: (StationGroup) -> Void

    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        List {
            if let subtitle {
                Section {
                    Label(subtitle, systemImage: "flag.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .listRowBackground(DS.surface)
                }
            }
            if query.isEmpty, !suggestions.isEmpty {
                Section("최근 출발역") {
                    ForEach(suggestions) { row($0) }
                }
            }
            Section(query.isEmpty ? "전체 역 \(results.count)개" : "검색 결과") {
                ForEach(results) { row($0) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.background)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "역 이름 검색")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }

    private var results: [StationGroup] {
        let groups = query.isEmpty ? model.stationGroups : model.network.searchGrouped(query)
        return groups.filter { $0 != excluded }
    }

    private func row(_ group: StationGroup) -> some View {
        Button {
            onSelect(group)
        } label: {
            StationGroupLabel(group: group)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(DS.surface)
    }
}
