import SwiftUI

/// 하차 완료 + 알림 타이밍 피드백 (성공 지표의 사용자 신호)
struct ArrivalView: View {
    @Environment(AppModel.self) private var model
    let session: TripSession
    @State private var timing: AlertTimingFeedback?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(BoardPalette.current)
                    .symbolEffect(.bounce, value: session.alightedAt)
                Text("\(session.trip.destination.name)에 잘 내렸어요")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(BoardPalette.text)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(BoardPalette.secondaryText)
            }
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Text("하차 알림 타이밍은 어땠나요?")
                    .font(.headline)
                    .foregroundStyle(BoardPalette.text)
                HStack(spacing: 8) {
                    ForEach(AlertTimingFeedback.allCases) { option in
                        Button {
                            timing = option
                        } label: {
                            Text(option.label)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(timing == option ? BoardPalette.background : BoardPalette.text)
                                .background(timing == option ? BoardPalette.current : BoardPalette.surface, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("알려주시면 알림 시점을 더 정확하게 맞출게요.")
                    .font(.caption)
                    .foregroundStyle(BoardPalette.secondaryText)
            }
            .sensoryFeedback(.selection, trigger: timing)

            Button("완료") { model.closeTrip(feedback: timing) }
                .buttonStyle(.cta(BoardPalette.current))
                .padding(.top, 24)
        }
        .padding(20)
    }

    private var summary: String {
        var parts = ["\(session.trip.origin.name)에서 \(session.trip.stopCount)정거장"]
        if let duration = session.rideDuration {
            parts.append(TripFormat.duration(duration))
        }
        return parts.joined(separator: " · ")
    }
}
