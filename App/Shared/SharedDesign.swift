import SwiftUI

extension Color {
    /// "#RRGGBB"
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

/// 전광판 팔레트 — 기획서의 다크 전광판 톤. 앱의 탑승 화면과 Live Activity가 공유한다.
enum BoardPalette {
    static let background = Color(hex: "#090D16")
    static let surface = Color(hex: "#131C2E")
    static let stroke = Color(hex: "#23324D")
    static let text = Color(hex: "#F1F5F9")
    static let secondaryText = Color(hex: "#94A3B8")
    /// 이번 역·하차
    static let current = Color(hex: "#10B981")
    /// 1차 준비
    static let prepare = Color(hex: "#F59E0B")
    /// 경고
    static let warning = Color(hex: "#F87171")
}

/// 노선 배지 — 노선색 위에 짧은 노선 이름.
/// 숫자 노선은 원, "경의"·"수인"처럼 두 글자 이상이면 캡슐로 넓힌다.
struct LineBadge: View {
    let shortName: String
    let colorHex: String
    var size: CGFloat = 28

    private var isCompact: Bool { shortName.count <= 1 }

    var body: some View {
        Text(shortName)
            .font(.system(size: size * (isCompact ? 0.56 : 0.42), weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, isCompact ? 0 : size * 0.24)
            .frame(minWidth: size, minHeight: size)
            .background(Color(hex: colorHex), in: .capsule)
            .accessibilityLabel(Int(shortName) != nil ? "\(shortName)호선" : shortName)
    }
}
