import SwiftUI

/// 깨워줘 심볼 — 노선 위의 역 노드에서 옆으로 빠져나가는 화살표 (= 하차).
///
/// 앱 아이콘과 같은 기하를 쓴다. 원본은 `tools/build_logo.swift`이고
/// 좌표는 1024 캔버스 기준이라, 여기서는 요청한 크기로 비례 축소한다.
/// 이미지가 아니라 그림이라 어느 크기·어느 색에서도 또렷하다.
struct WakeMeMark: View {
    var size: CGFloat = 28
    var ink: Color = .white
    /// 노선 선의 투명도. 마크가 아주 작을 때는 0으로 두면 더 또렷하다.
    var lineOpacity: Double = 0.38

    // 1024 캔버스 기준 좌표 (build_logo.swift와 같은 값)
    private let ringCX: CGFloat = 306, cy: CGFloat = 512
    private let bar: CGFloat = 84, ringR: CGFloat = 112
    private let shaftFrom: CGFloat = 506, tip: CGFloat = 830, arm: CGFloat = 110

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height) / 1024
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // 노선
            if lineOpacity > 0 {
                let line = CGRect(x: (ringCX - bar / 2) * s, y: 214 * s,
                                  width: bar * s, height: 596 * s)
                context.fill(Path(roundedRect: line, cornerRadius: bar / 2 * s),
                             with: .color(ink.opacity(lineOpacity)))
            }
            // 역 노드
            let ring = CGRect(x: (ringCX - ringR) * s, y: (cy - ringR) * s,
                              width: ringR * 2 * s, height: ringR * 2 * s)
            context.stroke(Path(ellipseIn: ring), with: .color(ink),
                           lineWidth: (bar - 4) * s)
            // 화살표
            let shaft = CGRect(x: shaftFrom * s, y: (cy - bar / 2) * s,
                               width: (tip - shaftFrom) * s, height: bar * s)
            context.fill(Path(roundedRect: shaft, cornerRadius: bar / 2 * s), with: .color(ink))

            var head = Path()
            head.move(to: p(tip - arm, cy + arm))
            head.addLine(to: p(tip, cy))
            head.addLine(to: p(tip - arm, cy - arm))
            context.stroke(head, with: .color(ink),
                           style: StrokeStyle(lineWidth: bar * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 24) {
        WakeMeMark(size: 96, ink: .white)
            .padding(24)
            .background(Color(hex: "#2F6BFF"), in: .rect(cornerRadius: 24))
        HStack(spacing: 20) {
            WakeMeMark(size: 48, ink: Color(hex: "#2F6BFF"))
            WakeMeMark(size: 28, ink: Color(hex: "#2F6BFF"))
            WakeMeMark(size: 16, ink: Color(hex: "#2F6BFF"), lineOpacity: 0)
        }
    }
    .padding(40)
}
