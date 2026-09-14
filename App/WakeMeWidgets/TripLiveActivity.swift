import ActivityKit
import SwiftUI
import WidgetKit

/// 잠금화면·다이내믹 아일랜드 전광판.
/// 카운트다운과 진행 막대는 `timerInterval`로 그려서 앱이 갱신하지 않아도 흐른다.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LockScreenTripView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(BoardPalette.background)
                .activitySystemActionForegroundColor(BoardPalette.text)
        } dynamicIsland: { context in
            let attributes = context.attributes
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        LineBadge(shortName: attributes.lineShortName, colorHex: attributes.lineColorHex, size: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(state.isDwelling ? "정차 중" : "이번 역")
                                .font(.caption2)
                                .foregroundStyle(BoardPalette.secondaryText)
                            Text(state.currentStation)
                                .font(.headline)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StopsRemainingLabel(state: state, destination: attributes.destination)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        PhaseMessage(state: state, destination: attributes.destination)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TripProgress(state: state, colorHex: attributes.lineColorHex)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                LineBadge(shortName: attributes.lineShortName, colorHex: attributes.lineColorHex, size: 20)
            } compactTrailing: {
                CompactStatus(state: state, showsIcon: true)
            } minimal: {
                CompactStatus(state: state)
            }
            .keylineTint(Color(hex: attributes.lineColorHex))
        }
    }
}

private struct LockScreenTripView: View {
    let attributes: TripActivityAttributes
    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LineBadge(shortName: attributes.lineShortName, colorHex: attributes.lineColorHex, size: 22)
                Text("\(attributes.directionName) · \(attributes.destination)행")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BoardPalette.secondaryText)
                Spacer()
                if state.isEstimated {
                    Text("추정")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BoardPalette.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(BoardPalette.stroke))
                }
            }

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    PhaseMessage(state: state, destination: attributes.destination)
                    Text(state.currentStation)
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(BoardPalette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 12)
                StopsRemainingLabel(state: state, destination: attributes.destination)
            }

            TripProgress(state: state, colorHex: attributes.lineColorHex)
        }
        .padding(16)
    }
}

/// 단계별 안내 문구 — 하차 단계에서는 강조색으로 바뀐다
private struct PhaseMessage: View {
    let state: TripActivityAttributes.ContentState
    let destination: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(state.phase == .alightNow || state.phase == .arrived ? .heavy : .semibold))
            .foregroundStyle(color)
    }

    private var text: String {
        switch state.phase {
        case .waiting: "열차 출발을 기다리는 중"
        case .riding: state.isDwelling ? "정차 중" : "이번 역"
        case .prepare: "곧 내릴 준비하세요"
        case .alightNow: "이번 역에서 내리세요"
        case .arrived: "\(destination) 도착 · 지금 내리세요"
        }
    }

    private var color: Color {
        switch state.phase {
        case .waiting, .riding: BoardPalette.secondaryText
        case .prepare: BoardPalette.prepare
        case .alightNow, .arrived: BoardPalette.current
        }
    }
}

private struct StopsRemainingLabel: View {
    let state: TripActivityAttributes.ContentState
    let destination: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if state.stopsRemaining > 0 {
                Text("\(destination)까지")
                    .font(.caption2)
                    .foregroundStyle(BoardPalette.secondaryText)
                Text("\(state.stopsRemaining)정거장")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(BoardPalette.text)
            } else {
                Text("도착")
                    .font(.headline)
                    .foregroundStyle(BoardPalette.current)
            }
            if let start = state.departedAt, let end = state.arrivalAt, state.stopsRemaining > 0 {
                Text(timerInterval: start...max(start, end), countsDown: true)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BoardPalette.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 64, alignment: .trailing)
            }
        }
    }
}

private struct TripProgress: View {
    let state: TripActivityAttributes.ContentState
    let colorHex: String

    var body: some View {
        Group {
            if let start = state.departedAt, let end = state.arrivalAt {
                ProgressView(timerInterval: start...max(start, end), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: 0)
            }
        }
        .tint(Color(hex: colorHex))
    }
}

private struct CompactStatus: View {
    let state: TripActivityAttributes.ContentState
    var showsIcon = false

    var body: some View {
        switch state.phase {
        case .alightNow:
            Text("내려요")
                .font(.caption.weight(.heavy))
                .foregroundStyle(BoardPalette.current)
        case .arrived:
            Text("도착")
                .font(.caption.weight(.heavy))
                .foregroundStyle(BoardPalette.current)
        default:
            HStack(spacing: 3) {
                if showsIcon {
                    Image(systemName: "tram.fill").font(.caption2)
                }
                Text("\(state.stopsRemaining)")
                    .font(.caption.weight(.heavy).monospacedDigit())
            }
            .foregroundStyle(state.phase == .prepare ? BoardPalette.prepare : BoardPalette.text)
            .accessibilityLabel("\(state.stopsRemaining)정거장 남음")
        }
    }
}
