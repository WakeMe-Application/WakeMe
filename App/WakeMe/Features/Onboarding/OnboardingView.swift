import SwiftUI

struct OnboardingView: View {
    @State private var didFireTest = false
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            BoardPalette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                heroBoard
                    .padding(.top, 32)

                VStack(alignment: .leading, spacing: 10) {
                    Text("방송을 못 들어도,\n잠이 들어도.")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(BoardPalette.text)
                    Text("내릴 역은 깨워줘가 챙길게요.")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BoardPalette.secondaryText)
                }
                .padding(.top, 36)

                VStack(alignment: .leading, spacing: 20) {
                    feature(icon: "lock.iphone", title: "잠금화면 전광판", detail: "폰을 열지 않고 남은 정거장을 확인해요")
                    feature(icon: "bell.badge.waveform.fill", title: "3단계 하차 알림", detail: "2역 전 준비, 전역 출발 때 하차, 도착하면 한 번 더")
                    feature(icon: "hand.tap.fill", title: "원탭 출발", detail: "출퇴근 루틴을 저장하면 한 번에 시작해요")
                }
                .padding(.top, 36)

                Spacer(minLength: 24)

                Button("알림 허용하고 시작하기") {
                    Task {
                        let granted = await NotificationScheduler.requestAuthorization()
                        // 알람 권한도 여기서 함께 받는다.
                        // 탑승 중에 물으면 하필 전광판을 봐야 할 순간에 팝업이 덮는다.
                        await AlarmScheduler.requestAuthorization()
                        // 약속만 하고 증명하지 않으면 믿기 어렵다.
                        // 허용한 그 자리에서 한 번 울려 "이렇게 울린다"를 보여 준다.
                        if granted {
                            await NotificationScheduler.fireTest(soundEnabled: true)
                            didFireTest = true
                            try? await Task.sleep(for: .seconds(3))
                        }
                        model.completeOnboarding()
                    }
                }
                .buttonStyle(.cta(BoardPalette.current))

                if didFireTest {
                    Label("지금 한 번 울려 볼게요", systemImage: "bell.badge.waveform.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BoardPalette.current)
                        .padding(.top, 10)
                        .transition(.opacity)
                }

                Text("하차 알림을 보내려면 알림 권한이 필요해요. 무음·집중 모드에서도 울리게 하려면 알람 권한도 함께 받아요. 위치는 탑승 중에만 사용해요.")
                    .font(.caption)
                    .foregroundStyle(BoardPalette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }

    /// 전광판 미니어처 — 앱의 핵심 화면을 첫인상으로
    private var heroBoard: some View {
        VStack(spacing: 6) {
            Text("이번 역")
                .font(.caption.weight(.bold))
                .foregroundStyle(BoardPalette.current)
            Text("강남")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(BoardPalette.text)
            HStack(spacing: 6) {
                Text("다음 교대")
                Image(systemName: "flag.fill").foregroundStyle(BoardPalette.current)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(BoardPalette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(BoardPalette.surface, in: .rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(BoardPalette.current.opacity(0.6), lineWidth: 2))
        .shadow(color: BoardPalette.current.opacity(0.25), radius: 24)
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(BoardPalette.current)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(BoardPalette.text)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(BoardPalette.secondaryText)
            }
        }
    }
}
