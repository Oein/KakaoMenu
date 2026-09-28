// KakaoMenu 앱 아이콘(AppIcon.icns) 생성: 노란 라운드 사각형 + 검은 말풍선 + N 배지 3개(삼각형)
// 사용: swift make-icon.swift <출력.icns>
import Cocoa

func drawIcon(_ ctx: CGContext, _ s: CGFloat) {
    // macOS 아이콘 그리드: 1024 캔버스에 824 본체, 모서리 반경 ≈ 185
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225

    // 그림자 + 노란 배경
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor(white: 0, alpha: 0.3).cgColor)
    let bg = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bg)
    ctx.setFillColor(NSColor(srgbRed: 1.0, green: 0.90, blue: 0.0, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bg); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        NSColor(srgbRed: 1.0, green: 0.93, blue: 0.25, alpha: 1).cgColor,
        NSColor(srgbRed: 1.0, green: 0.86, blue: 0.0, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // 말풍선 (몸통 타원 + 왼쪽 아래 꼬리)
    let u = body.width
    let bubble = CGRect(x: body.minX + u * 0.14, y: body.minY + u * 0.34, width: u * 0.62, height: u * 0.50)
    ctx.setFillColor(NSColor(srgbRed: 0.24, green: 0.12, blue: 0.12, alpha: 1).cgColor)
    ctx.fillEllipse(in: bubble)
    ctx.move(to: CGPoint(x: bubble.minX + bubble.width * 0.22, y: bubble.minY + bubble.height * 0.20))
    ctx.addLine(to: CGPoint(x: bubble.minX + bubble.width * 0.14, y: bubble.minY - u * 0.10))
    ctx.addLine(to: CGPoint(x: bubble.minX + bubble.width * 0.46, y: bubble.minY + bubble.height * 0.06))
    ctx.closePath(); ctx.fillPath()

    // N 배지 3개: 아래 오른쪽 빨강, 아래 왼쪽 파랑, 위 노랑 (메뉴바 '삼각형' 배치와 같음)
    let r = u * 0.13
    let badges: [(CGPoint, NSColor, NSColor)] = [
        (CGPoint(x: body.minX + u * 0.63, y: body.minY + u * 0.47), NSColor(srgbRed: 1.00, green: 0.78, blue: 0.00, alpha: 1), NSColor(white: 0.1, alpha: 1)),
        (CGPoint(x: body.minX + u * 0.52, y: body.minY + u * 0.25), NSColor(srgbRed: 0.10, green: 0.44, blue: 0.93, alpha: 1), .white),
        (CGPoint(x: body.minX + u * 0.76, y: body.minY + u * 0.25), NSColor(srgbRed: 0.93, green: 0.23, blue: 0.19, alpha: 1), .white),
    ]
    for (c, fill, letter) in badges {
        let ring = r + u * 0.025
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2))
        ctx.setFillColor(fill.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let font = NSFont.systemFont(ofSize: r * 1.35, weight: .black)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "N", attributes: [.font: font, .foregroundColor: letter]))
        let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: c.x - b.midX, y: c.y - b.midY)
        CTLineDraw(line, ctx)
    }
    ctx.restoreGState()
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        drawIcon(ctx, CGFloat(px))
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "생성됨: \(out)" : "iconutil 실패")
