import SwiftUI
import WakeMeEngine

extension SubwayLine {
    var color: Color { Color(hex: colorHex) }
}

extension TripPhase {
    /// 전광판 강조색
    var tint: Color {
        switch self {
        case .waiting: BoardPalette.secondaryText
        case .riding, .alightNow, .arrived: BoardPalette.current
        case .prepare: BoardPalette.prepare
        }
    }
}

enum TripFormat {
    static func stops(_ count: Int) -> String { "\(count)정거장" }

    static func minutes(_ seconds: TimeInterval) -> String {
        "약 \(max(1, Int((seconds / 60).rounded())))분"
    }

    static func summary(stops count: Int, seconds: TimeInterval) -> String {
        "\(stops(count)) · \(minutes(seconds))"
    }

    /// 앱 문구가 한국어라 시각도 한국어 형식으로 고정한다 (예: 오후 6:48)
    static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(korean))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes < 60 ? "\(minutes)분" : "\(minutes / 60)시간 \(minutes % 60)분"
    }

    private static let korean = Locale(identifier: "ko_KR")
}

// MARK: - Station components

struct TransferChips: View {
    let transfers: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(transfers, id: \.self) { name in
                Text(name)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.secondary)
                    .background(.fill.tertiary, in: .capsule)
            }
        }
    }
}

/// 역 선택 목록의 한 줄 — 역 이름과 그 역을 지나는 노선 배지
struct StationGroupLabel: View {
    let group: StationGroup

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(DS.headline)
                    .foregroundStyle(.primary)
                if !group.nameEn.isEmpty {
                    Text(group.nameEn)
                        .font(DS.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(group.lines.prefix(4)) { line in
                    LineBadge(shortName: line.shortName, colorHex: line.colorHex, size: 22)
                }
                if group.lines.count > 4 {
                    Text("+\(group.lines.count - 4)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 출발역 → 도착역 한 줄 요약 (홈 카드·설정 시트 공용)
struct RouteHeadline: View {
    let origin: String
    let destination: String
    var font: Font = .title3.weight(.bold)

    var body: some View {
        HStack(spacing: 8) {
            Text(origin)
            Image(systemName: "arrow.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            Text(destination)
        }
        .font(font)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
