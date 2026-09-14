import SwiftUI

/// 디자인 토큰.
/// 국내 금융앱에서 익숙한 규칙을 우리 팔레트로 옮겼다:
/// 한 화면에 한 과업, 크고 굵은 제목 + 회색 설명, 하단 고정 CTA, 숫자 강조, 넉넉한 여백.
enum DS {
    // MARK: - 색

    /// 주요 액션
    static let primary = Color(hex: "#2F6BFF")
    static let primaryPressed = Color(hex: "#2457D6")
    /// 진행·완료
    static let success = Color(hex: "#10B981")
    static let warning = Color(hex: "#F59E0B")
    static let danger = Color(hex: "#EF4444")

    /// 배경은 탑승 전광판과 같은 톤을 쓴다 — 온보딩 → 홈 → 탑승이 한 통으로 이어지도록.
    /// 원본 값은 `BoardPalette`이고 여기서는 그대로 가져다 쓴다.
    /// 앱은 Info.plist의 `UIUserInterfaceStyle`로 다크에 고정되어 있어,
    /// `.primary`·`.secondary` 같은 시스템 의미색도 이 배경 위에서 읽힌다.
    static let background = BoardPalette.background
    static let surface = BoardPalette.surface
    static let surfacePressed = Color(hex: "#1B2740")
    static let separator = BoardPalette.stroke.opacity(0.6)

    // MARK: - 타이포 (Pretendard, SIL Open Font License)
    // 커스텀 폰트는 .weight() 수정자가 먹지 않으므로 굵기별 토큰을 따로 둔다.

    enum Pretendard {
        static let regular = "Pretendard-Regular"
        static let medium = "Pretendard-Medium"
        static let semibold = "Pretendard-SemiBold"
        static let bold = "Pretendard-Bold"
    }

    /// 화면 제목 (한 줄에 하나의 질문)
    static let display = Font.custom(Pretendard.bold, size: 30, relativeTo: .largeTitle)
    static let title = Font.custom(Pretendard.bold, size: 22, relativeTo: .title2)
    static let headline = Font.custom(Pretendard.semibold, size: 17, relativeTo: .headline)
    static let headlineBold = Font.custom(Pretendard.bold, size: 17, relativeTo: .headline)
    static let body = Font.custom(Pretendard.medium, size: 16, relativeTo: .body)
    static let bodyBold = Font.custom(Pretendard.semibold, size: 16, relativeTo: .body)
    static let label = Font.custom(Pretendard.medium, size: 14, relativeTo: .subheadline)
    static let labelBold = Font.custom(Pretendard.semibold, size: 14, relativeTo: .subheadline)
    static let caption = Font.custom(Pretendard.medium, size: 13, relativeTo: .caption)
    static let captionBold = Font.custom(Pretendard.semibold, size: 13, relativeTo: .caption)
    /// 남은 정거장·시간처럼 눈에 먼저 들어와야 하는 숫자
    static func number(_ size: CGFloat) -> Font { .custom(Pretendard.bold, size: size, relativeTo: .title) }
    /// 역 이름처럼 크게 보여 주는 글자
    static func headline(_ size: CGFloat) -> Font { .custom(Pretendard.bold, size: size, relativeTo: .title) }

    // MARK: - 간격·모양

    static let screenPadding: CGFloat = 20
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 16
    static let controlHeight: CGFloat = 56

    // MARK: - 모션

    static let press = Animation.spring(response: 0.24, dampingFraction: 0.86)
    static let content = Animation.snappy(duration: 0.28)
}

// MARK: - 버튼

/// 하단 고정 CTA. 전체 너비, 누르면 살짝 줄어든다.
struct CTAButtonStyle: ButtonStyle {
    var tint: Color = DS.primary
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: DS.controlHeight)
            .background(
                (configuration.isPressed ? tint.opacity(0.86) : tint).opacity(isEnabled ? 1 : 0.4),
                in: .rect(cornerRadius: DS.controlRadius))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(DS.press, value: configuration.isPressed)
    }
}

/// 보조 액션. 회색 배경에 진한 글씨.
struct SubtleButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.body)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                configuration.isPressed ? DS.surfacePressed : DS.surface,
                in: .rect(cornerRadius: DS.controlRadius))
            .animation(DS.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CTAButtonStyle {
    static var cta: CTAButtonStyle { CTAButtonStyle() }
    static func cta(_ tint: Color, enabled: Bool = true) -> CTAButtonStyle {
        CTAButtonStyle(tint: tint, isEnabled: enabled)
    }
}

extension ButtonStyle where Self == SubtleButtonStyle {
    static var subtle: SubtleButtonStyle { SubtleButtonStyle() }
    static func subtle(_ tint: Color) -> SubtleButtonStyle { SubtleButtonStyle(tint: tint) }
}

// MARK: - 공통 조각

/// 화면 상단: 큰 제목 한 줄과 회색 설명 한 줄
struct ScreenHeader: View {
    let title: String
    var subtitle: String?
    var eyebrow: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                HStack(spacing: 6) {
                    Circle().fill(DS.success).frame(width: 7, height: 7)
                    Text(eyebrow).font(DS.caption.weight(.bold))
                }
                .foregroundStyle(.secondary)
            }
            Text(title)
                .font(DS.display)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(DS.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 목록 묶음 제목
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(DS.title)
            Spacer()
            if let trailing {
                Text(trailing).font(DS.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// 흰 카드 컨테이너 (리스트 묶음·정보 카드 공용)
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surface, in: .rect(cornerRadius: DS.cardRadius))
    }
}

/// 눌리는 목록 행 — 탭하면 배경이 반응한다
struct PressableRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(RowButtonStyle())
    }
}

private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.surfacePressed : .clear)
            .animation(DS.press, value: configuration.isPressed)
    }
}

/// 값 강조 칩 ("6정거장", "약 12분")
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = DS.primary

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(DS.label.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

extension View {
    /// 하단 고정 CTA 영역 (배경까지 함께 깔아 스크롤과 겹치지 않게)
    func bottomCTA<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                content()
            }
            .padding(.horizontal, DS.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DS.separator)
                    .frame(height: 0.5)
            }
        }
    }
}
