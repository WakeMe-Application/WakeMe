import SwiftUI

/// 브랜드 타일 + 이름. 화면 상단 브랜드 표시에 쓴다.
///
/// 타일은 앱 아이콘과 같은 모습(브랜드 파랑 그라데이션 위 흰 마크)이다.
/// 마크만 단색으로 놓으면 어두운 배경에서 대비가 약하고, 아이콘 기하가 캔버스의 70%만
/// 차지해 작은 크기에서 뭉개진다. 사용자가 홈 화면에서 눌러 들어온 그림과 같게 두는 편이
/// 알아보기도 쉽다.
///
/// 심볼(`WakeMeMark`)은 위젯도 쓰라고 `Shared/`에 있고, 이 조합은 앱 타이포(`DS.Pretendard`)에
/// 기대므로 앱 쪽에 둔다.
struct WakeMeWordmark: View {
    /// 타일 한 변의 길이
    var size: CGFloat = 30
    var ink: Color = .primary

    var body: some View {
        HStack(spacing: size * 0.34) {
            WakeMeMark(size: size, ink: .white)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#5C8CFF"), Color(hex: "#2F6BFF")],
                        startPoint: .top, endPoint: .bottom),
                    // iOS 아이콘과 같은 모서리 비율
                    in: .rect(cornerRadius: size * 0.2237))
            Text("깨워줘")
                .font(.custom(DS.Pretendard.bold, size: size * 0.66))
                .foregroundStyle(ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("깨워줘")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        WakeMeWordmark(size: 24)
        WakeMeWordmark(size: 30)
        WakeMeWordmark(size: 44)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DS.background)
}
