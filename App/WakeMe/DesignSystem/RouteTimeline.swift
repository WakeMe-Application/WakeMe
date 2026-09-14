import SwiftUI
import WakeMeEngine

/// 세로 노선도. 탑승 화면에서 진행 표시와 위치 보정에 쓴다.
/// 앞으로 갈 구간은 노선색, 지나온 구간은 흐리게 그린다.
struct RouteTimeline: View {
    let stops: [Trip.Stop]
    let lineColor: Color
    /// nil이면 진행 없이 경로만 보여 준다
    var currentIndex: Int?
    /// 현재 역 옆 태그 (예: "이번 역", "정차 중", "탑승 대기")
    var currentTag = "이번 역"
    var onSelect: ((Int) -> Void)?

    private enum Progress { case passed, current, upcoming }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                row(index: index, stop: stop)
                    .id(index)
            }
        }
    }

    private func row(index: Int, stop: Trip.Stop) -> some View {
        let progress = progress(of: index)
        let isDestination = index == stops.count - 1
        return HStack(spacing: 14) {
            ZStack {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(index == 0 ? .clear : segmentColor(traveled: isTraveled(arrivingAt: index)))
                    Rectangle()
                        .fill(isDestination ? .clear : segmentColor(traveled: isTraveled(arrivingAt: index + 1)))
                }
                .frame(width: 4)
                dot(progress: progress, isDestination: isDestination)
            }
            .frame(width: 28)

            Text(stop.station.name)
                .font(progress == .current ? .headline : .subheadline.weight(.medium))
                .foregroundStyle(nameColor(progress))

            Spacer(minLength: 8)

            if isDestination {
                tag("하차", color: BoardPalette.current)
            } else if progress == .current {
                tag(currentTag, color: lineColor)
            } else if index == 0 {
                tag("승차", color: secondaryColor)
            }
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
        .onTapGesture {
            if index > 0 { onSelect?(index) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(onSelect != nil && index > 0 ? "지금 이 역이라면 눌러서 위치를 바로잡으세요" : "")
    }

    @ViewBuilder
    private func dot(progress: Progress, isDestination: Bool) -> some View {
        if isDestination {
            Image(systemName: "flag.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(BoardPalette.current, in: .circle)
        } else {
            switch progress {
            case .passed:
                Circle().fill(dimColor).frame(width: 10, height: 10)
            case .current:
                ZStack {
                    Circle()
                        .fill(lineColor.opacity(0.5))
                        .phaseAnimator([false, true]) { circle, expanded in
                            circle.scaleEffect(expanded ? 1.9 : 1).opacity(expanded ? 0 : 0.7)
                        } animation: { _ in .easeOut(duration: 1.4) }
                    Circle().fill(.white)
                    Circle().strokeBorder(lineColor, lineWidth: 5)
                }
                .frame(width: 22, height: 22)
            case .upcoming:
                Circle()
                    .fill(BoardPalette.background)
                    .overlay(Circle().strokeBorder(lineColor, lineWidth: 3))
                    .frame(width: 14, height: 14)
            }
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
    }

    private func progress(of index: Int) -> Progress {
        guard let currentIndex else { return .upcoming }
        if index < currentIndex { return .passed }
        return index == currentIndex ? .current : .upcoming
    }

    /// `index` 역으로 들어오는 구간을 이미 달렸는지 (진입 중이면 달린 것으로 본다)
    private func isTraveled(arrivingAt index: Int) -> Bool {
        guard let currentIndex else { return false }
        return index <= currentIndex
    }

    private func segmentColor(traveled: Bool) -> Color {
        traveled ? dimColor : lineColor
    }

    private var dimColor: Color {
        BoardPalette.stroke
    }

    private var secondaryColor: Color {
        BoardPalette.secondaryText
    }

    private func nameColor(_ progress: Progress) -> Color {
        progress == .passed ? BoardPalette.secondaryText.opacity(0.6) : BoardPalette.text
    }
}
