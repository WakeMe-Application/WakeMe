import SwiftUI
import WakeMeEngine

/// 탑승 중 전광판. 시스템 테마와 관계없이 다크 전광판으로 고정한다.
struct TripView: View {
    @Environment(AppModel.self) private var model
    let session: TripSession
    @State private var correctionIndex: Int?
    @State private var confirmEnd = false

    var body: some View {
        ZStack {
            BoardPalette.background.ignoresSafeArea()
            if session.alightedAt != nil {
                ArrivalView(session: session)
                    .transition(.opacity)
            } else {
                content
            }
        }
        .animation(.snappy, value: session.alightedAt)
        .preferredColorScheme(.dark)
        .sensoryFeedback(trigger: session.snapshot.phase) { _, phase in
            switch phase {
            case .prepare: .warning
            case .alightNow: .impact(weight: .heavy, intensity: 1)
            case .arrived: .success
            default: nil
            }
        }
    }

    private var snapshot: TripSnapshot { session.snapshot }

    private var content: some View {
        VStack(spacing: 0) {
            topBar
            // 전광판이 주인공이라 역이 바뀌어도 자동 스크롤하지 않는다
            ScrollView {
                VStack(spacing: 16) {
                    PhaseBanner(session: session)
                    BoardCard(session: session)
                    liveTrainRow
                    DestinationCard(session: session)
                    if let switched = session.lastServiceSwitch, session.now.timeIntervalSince(switched.date) < 120 {
                        notice(
                            switched.isExpress ? "급행 열차예요. 급행 기준으로 다시 계산했어요"
                                               : "완행 열차예요. 완행 기준으로 다시 계산했어요",
                            systemImage: "hare.fill", tint: BoardPalette.prepare)
                    } else if let synced = session.lastRealtimeSync, session.now.timeIntervalSince(synced) < 90 {
                        notice("실시간 열차 정보로 위치를 맞췄어요", systemImage: "dot.radiowaves.up.forward", tint: BoardPalette.current)
                    } else if let detected = session.lastAutoDetection, session.now.timeIntervalSince(detected) < 90 {
                        notice("정차를 감지해 위치를 맞췄어요", systemImage: "waveform", tint: BoardPalette.current)
                    } else if snapshot.confidence == .estimated, snapshot.phase != .arrived {
                        estimateNotice
                    }
                    RouteTimeline(
                        stops: session.trip.stops,
                        lineColor: session.line.color,
                        currentIndex: session.hasDeparted ? snapshot.currentIndex : 0,
                        currentTag: !session.hasDeparted ? "탑승 대기" : (snapshot.isDwelling ? "정차 중" : "이번 역"),
                        trainProgress: session.livePositionProgress,
                        onSelect: { correctionIndex = $0 })
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(BoardPalette.surface, in: .rect(cornerRadius: 24))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            bottomAction
        }
        .confirmationDialog(
            correctionTitle, isPresented: .init(get: { correctionIndex != nil }, set: { if !$0 { correctionIndex = nil } }),
            titleVisibility: .visible, presenting: correctionIndex
        ) { index in
            Button("네, 여기로 맞출게요") { session.correct(arrivedAt: index) }
        } message: { _ in
            Text("이 역에 정차한 시각을 기준으로 남은 시간과 알림을 다시 계산해요.")
        }
        .confirmationDialog("안내를 종료할까요?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("종료", role: .destructive) { model.closeTrip(feedback: nil) }
        } message: {
            Text("예약된 하차 알림도 함께 취소돼요.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            LineBadge(shortName: session.line.shortName, colorHex: session.line.colorHex, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(session.line.name) \(session.directionName)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BoardPalette.text)
                Text(session.isLastLeg
                     ? "\(session.finalDestination.name)에서 내려요"
                     : "\(session.trip.destination.name)에서 환승 · \(session.finalDestination.name)까지")
                    .font(.caption)
                    .foregroundStyle(BoardPalette.secondaryText)
            }
            Spacer()
            Button {
                confirmEnd = true
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(BoardPalette.text)
                    .frame(width: 44, height: 44)
                    .background(BoardPalette.surface, in: .circle)
            }
            .accessibilityLabel("안내 종료")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// 실시간 열차위치 — 우리가 시간으로 추정한 위치가 아니라, API가 말하는 실제 열차 위치다.
    /// 둘이 다를 수 있고, 그 차이를 숨기지 않는 편이 사용자가 화면을 믿을지 판단하는 데 낫다.
    @ViewBuilder
    private var liveTrainRow: some View {
        if session.isRealtimeAvailable {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .foregroundStyle(session.livePosition == nil ? BoardPalette.secondaryText : BoardPalette.current)
                if let position = session.livePosition {
                    Text(position.locationText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BoardPalette.text)
                    Text("\(position.trainNumber)번 열차")
                        .font(.caption)
                        .foregroundStyle(BoardPalette.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(freshness(of: position.receivedAt))
                        .font(.caption)
                        .foregroundStyle(isStale(position.receivedAt)
                                         ? BoardPalette.prepare : BoardPalette.secondaryText)
                } else {
                    Text(session.realtimeStatus)
                        .font(.footnote)
                        .foregroundStyle(BoardPalette.secondaryText)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(BoardPalette.surface, in: .rect(cornerRadius: 16))
        }
    }

    /// 마지막 수신이 얼마나 지났는지. 30초마다 받으므로 1분을 넘으면 끊긴 것으로 읽힌다.
    /// 이 값을 **받은 지** 얼마나 됐는지.
    ///
    /// "받은 지"를 빼면 바로 왼쪽의 "선릉 도착"과 한 줄로 붙어
    /// "선릉에 59초 뒤 도착"이라는 카운트다운으로 읽힌다. 뜻이 정반대고,
    /// 시간이 갈수록 숫자가 커져서 거꾸로 세는 것처럼 보인다.
    private func freshness(of date: Date) -> String {
        let seconds = Int(session.now.timeIntervalSince(date))
        if seconds < 15 { return "방금 받음" }
        if seconds < 60 { return "받은 지 \(seconds)초" }
        return "받은 지 \(seconds / 60)분"
    }

    /// 30초마다 받으므로 이보다 오래됐으면 실시간이 끊긴 것으로 본다
    private func isStale(_ date: Date) -> Bool {
        session.now.timeIntervalSince(date) > 90
    }

    private func notice(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(text)
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(14)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 16))
        .transition(.opacity)
    }

    private var estimateNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
            Text("시간으로 추정한 위치예요. 지금 역을 누르면 바로잡을 수 있어요.")
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(BoardPalette.secondaryText)
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BoardPalette.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    @ViewBuilder
    private var bottomAction: some View {
        Group {
            if !session.hasDeparted {
                VStack(spacing: 10) {
                    Button("열차가 출발했어요") { session.depart() }
                        .buttonStyle(.cta(session.line.color))
                    Text(session.isAutoDetecting
                         ? "열차가 출발하면 자동으로 시작돼요. 지금 바로 시작하려면 눌러 주세요."
                         : "출발하는 순간 눌러 주세요.")
                        .font(.caption)
                        .foregroundStyle(BoardPalette.secondaryText)
                }
            } else if session.isTransferPending {
                VStack(spacing: 10) {
                    Button("환승 열차 탔어요") { session.advanceToNextLeg() }
                        .buttonStyle(.cta(session.nextLine?.color ?? BoardPalette.current))
                    if let next = session.nextTransferTrain {
                        Label(
                            next.seconds < 45
                            ? "\(next.isExpress ? "급행 " : "")열차가 곧 들어와요"
                            : "다음 \(next.isExpress ? "급행 " : "")열차 약 \(Int((next.seconds / 60).rounded()))분 · \(next.stationsAway)정거장 전",
                            systemImage: "train.side.front.car")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(session.nextLine?.color ?? BoardPalette.current)
                    }
                    Text("\(session.nextLine?.name ?? "다음 노선")으로 갈아타면 눌러 주세요")
                        .font(.caption)
                        .foregroundStyle(BoardPalette.secondaryText)
                }
            } else if snapshot.phase == .alightNow || snapshot.phase == .arrived {
                Button("내렸어요") { session.confirmAlighted() }
                    .buttonStyle(.cta(BoardPalette.current))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var correctionTitle: String {
        guard let index = correctionIndex else { return "" }
        return "지금 \(session.trip.stops[index].station.name)역에 정차 중인가요?"
    }
}

// MARK: - Components

private struct PhaseBanner: View {
    let session: TripSession

    var body: some View {
        switch session.snapshot.phase {
        case .prepare:
            banner(
                icon: "bell.badge.fill", title: "곧 내릴 준비하세요",
                detail: "\(session.trip.destination.name)까지 \(session.snapshot.stopsRemaining)정거장",
                color: BoardPalette.prepare, prominent: false)
        case .alightNow:
            banner(
                icon: "figure.walk.departure", title: "이번 역에서 내리세요",
                detail: "\(session.trip.destination.name) · 문 앞으로 이동하세요",
                color: BoardPalette.current, prominent: true)
        case .arrived:
            banner(
                icon: "checkmark.circle.fill", title: "\(session.trip.destination.name) 도착",
                detail: "지금 내리세요",
                color: BoardPalette.current, prominent: true)
        case .waiting, .riding:
            EmptyView()
        }
    }

    private func banner(icon: String, title: String, detail: String, color: Color, prominent: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 30 : 22, weight: .bold))
                .symbolEffect(.pulse, isActive: prominent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: prominent ? 26 : 19, weight: .heavy))
                Text(detail)
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(prominent ? BoardPalette.background : color)
        .padding(prominent ? 20 : 16)
        .background(prominent ? color : color.opacity(0.14), in: .rect(cornerRadius: 22))
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

private struct BoardCard: View {
    let session: TripSession

    var body: some View {
        let snapshot = session.snapshot
        let current = session.currentStop.station
        VStack(spacing: 14) {
            HStack {
                if let previous = session.previousStop {
                    Label(previous.station.name, systemImage: "chevron.left")
                } else {
                    // 출발 전에는 이전 역이 없다 — 높이만 유지
                    Label("이전 역", systemImage: "chevron.left").hidden()
                }
                Spacer()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(BoardPalette.secondaryText)

            VStack(spacing: 4) {
                Text(label(snapshot))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(snapshot.phase.tint)
                Text(current.name)
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(BoardPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(current.nameEn)
                    .font(.subheadline)
                    .foregroundStyle(BoardPalette.secondaryText)
                    .lineLimit(1)
            }
            .animation(.snappy, value: current)

            HStack {
                Spacer()
                if let next = session.nextStop {
                    HStack(spacing: 6) {
                        Text("다음 \(next.station.name)")
                        if next.station == session.trip.destination {
                            Image(systemName: "flag.fill").foregroundStyle(BoardPalette.current)
                        }
                        Image(systemName: "chevron.right")
                    }
                } else {
                    HStack(spacing: 6) {
                        Text("내릴 역")
                        Image(systemName: "flag.fill").foregroundStyle(BoardPalette.current)
                    }
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(BoardPalette.secondaryText)
        }
        .padding(20)
        .background(BoardPalette.surface, in: .rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(snapshot.phase == .alightNow ? BoardPalette.current : BoardPalette.stroke, lineWidth: snapshot.phase == .alightNow ? 2 : 1)
        }
    }

    private func label(_ snapshot: TripSnapshot) -> String {
        if !session.hasDeparted { return "승차역 · 출발 대기" }
        return snapshot.isDwelling ? "정차 중" : "이번 역"
    }
}

private struct DestinationCard: View {
    let session: TripSession

    var body: some View {
        let snapshot = session.snapshot
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.stopsRemaining > 0 ? "\(session.trip.destination.name)까지" : session.trip.destination.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BoardPalette.secondaryText)
                    Text(snapshot.stopsRemaining > 0 ? TripFormat.stops(snapshot.stopsRemaining) : "도착")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(BoardPalette.text)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(!session.hasDeparted ? "예상 소요" : (snapshot.stopsRemaining > 0 ? "도착 예정" : "도착 시각"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BoardPalette.secondaryText)
                    Text(trailingValue)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(BoardPalette.text)
                    if session.hasDeparted, snapshot.stopsRemaining > 0 {
                        Text(TripFormat.minutes(snapshot.secondsToArrival) + " 남음")
                            .font(.caption)
                            .foregroundStyle(BoardPalette.secondaryText)
                    }
                }
            }
            .animation(.snappy, value: snapshot.stopsRemaining)
            ProgressView(value: snapshot.progress)
                .tint(session.line.color)
                .animation(.linear(duration: 1), value: snapshot.progress)
        }
        .padding(20)
        .background(BoardPalette.surface, in: .rect(cornerRadius: 24))
    }

    private var trailingValue: String {
        guard let arrival = session.arrivalDate else { return TripFormat.minutes(session.snapshot.secondsToArrival) }
        return TripFormat.clock(arrival)
    }
}
