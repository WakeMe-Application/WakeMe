// 깨워줘 로고 생성기 — 앱 아이콘(라이트·다크·틴티드)과 워드마크를 만든다.
//   swift tools/build_logo.swift          (저장소 루트에서 실행)
// 마크는 "노선 위의 역 노드에서 옆으로 빠져나가는 화살표" = 하차.
// 다크·틴티드는 애플 가이드대로 배경을 비워 두고 시스템이 배경을 입히게 한다.
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let brandTop: UInt32 = 0x5C8CFF, brandBottom: UInt32 = 0x2F6BFF

func ctx(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255,
            blue: CGFloat(hex & 255)/255, alpha: a)
}
func gradient(_ g: CGContext, _ top: UInt32, _ bottom: UInt32, height: CGFloat) {
    let grad = CGGradient(colorsSpace: sRGB, colors: [c(top), c(bottom)] as CFArray, locations: [0, 1])!
    g.drawLinearGradient(grad, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])
}
func capsule(_ g: CGContext, _ r: CGRect) {
    let k = min(r.width, r.height)/2
    g.addPath(CGPath(roundedRect: r, cornerWidth: k, cornerHeight: k, transform: nil)); g.fillPath()
}

// 마크 기하 — 1024 캔버스 기준
let ringCX: CGFloat = 306, cy: CGFloat = 512
let bar: CGFloat = 84, ringR: CGFloat = 112
let shaftFrom: CGFloat = 506, tip: CGFloat = 830, arm: CGFloat = 110

func mark(_ g: CGContext, ink: UInt32, lineAlpha: CGFloat) {
    g.setFillColor(c(ink, lineAlpha))
    capsule(g, CGRect(x: ringCX - bar/2, y: 214, width: bar, height: 596))
    g.setStrokeColor(c(ink)); g.setFillColor(c(ink))
    g.setLineWidth(bar - 4)
    g.addEllipse(in: CGRect(x: ringCX - ringR, y: cy - ringR, width: ringR*2, height: ringR*2))
    g.strokePath()
    capsule(g, CGRect(x: shaftFrom, y: cy - bar/2, width: tip - shaftFrom, height: bar))
    g.setLineWidth(bar); g.setLineCap(.round); g.setLineJoin(.round)
    g.move(to: CGPoint(x: tip - arm, y: cy + arm))
    g.addLine(to: CGPoint(x: tip, y: cy))
    g.addLine(to: CGPoint(x: tip - arm, y: cy - arm))
    g.strokePath()
}

func save(_ img: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
}

let icons = "App/WakeMe/Assets.xcassets/AppIcon.appiconset"

// 라이트 — 브랜드 파랑 배경 위 흰 마크 (배경 불투명: 앱 아이콘 필수)
let light = ctx(Int(S), Int(S))
gradient(light, brandTop, brandBottom, height: S)
mark(light, ink: 0xFFFFFF, lineAlpha: 0.38)
let lightImage = light.makeImage()!
save(lightImage, "\(icons)/AppIcon-light.png")
save(lightImage, "brand/icon-1024.png")

// 다크 — 배경은 시스템이 깐다. 마크만 브랜드 파랑으로.
let dark = ctx(Int(S), Int(S))
mark(dark, ink: 0x6D99FF, lineAlpha: 0.34)
save(dark.makeImage()!, "\(icons)/AppIcon-dark.png")

// 틴티드 — 시스템이 휘도로 색을 입히므로 회색조로만 그린다.
let tinted = ctx(Int(S), Int(S))
mark(tinted, ink: 0xFFFFFF, lineAlpha: 0.34)
save(tinted.makeImage()!, "\(icons)/AppIcon-tinted.png")

// 워드마크 — README·기획서용
let W: CGFloat = 1600, H: CGFloat = 460
let lock = ctx(Int(W), Int(H))
lock.setFillColor(c(0xFFFFFF)); lock.fill(CGRect(x: 0, y: 0, width: W, height: H))
let side: CGFloat = 260
let box = CGRect(x: 120, y: (H - side)/2, width: side, height: side)
lock.saveGState()
lock.addPath(CGPath(roundedRect: box, cornerWidth: side*0.2237, cornerHeight: side*0.2237, transform: nil))
lock.clip(); lock.draw(lightImage, in: box); lock.restoreGState()

func text(_ g: CGContext, _ s: String, font: String, size: CGFloat, color: CGColor, x: CGFloat, y: CGFloat) {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: f,
        kCTForegroundColorAttributeName as NSAttributedString.Key: color]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    g.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, g)
}
text(lock, "깨워줘", font: "AppleSDGothicNeoB00", size: 150, color: c(0x111827), x: 450, y: 236)
text(lock, "지하철 하차 알림", font: "AppleSDGothicNeoM00", size: 62, color: c(0x8E8E93), x: 458, y: 150)
save(lock.makeImage()!, "brand/wordmark.png")
print("로고 생성 완료")
