import SwiftUI

/// 탑승 기록 목록. 탭하면 공유 시트(AirDrop 등)로 Mac에 보낼 수 있다.
struct RideListView: View {
    let recorder: RideRecorder
    @State private var files: [RideStore.RideFile] = []

    var body: some View {
        List {
            if files.isEmpty {
                ContentUnavailableView(
                    "기록 없음", systemImage: "tram",
                    description: Text("탑승 기록이 여기에 쌓여요"))
            }
            ForEach(files) { file in
                ShareLink(item: file.url) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.body.monospaced())
                        Text(detail(for: file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .deleteDisabled(file.url == recorder.currentFileURL)
            }
            .onDelete { offsets in
                offsets.map { files[$0] }.forEach(RideStore.delete)
                files = RideStore.list()
            }
        }
        .navigationTitle("탑승 기록")
        .onAppear { files = RideStore.list() }
        .refreshable { files = RideStore.list() }
    }

    private func detail(for file: RideStore.RideFile) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)
        let recording = file.url == recorder.currentFileURL ? " · 기록 중" : ""
        return "\(file.modified.formatted(date: .abbreviated, time: .shortened)) · \(size)\(recording)"
    }
}
