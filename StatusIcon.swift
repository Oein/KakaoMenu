// 메뉴바 아이콘: 카카오톡 원본 에셋(Assets.car)으로 그린다.
//   말풍선 = MenuIcon / DarkMenuIcon (카카오톡이 꺼져 있으면 Loggedout…)
//   배지   = MenuIconWithNew 의 빨간 배지 모양(N 자리 포함)을 마스크로 뽑아 빨강/파랑/노랑으로 칠함
// 첫 배지(빨강)는 원본 위치에 고정하고, 더 있으면 왼쪽 뒤로 겹쳐 쌓는다. 3개면 말풍선을 가운데로.
// 배경화면 색에 상관없이 보이도록 N 은 뚫지 않고 채운다(흰색, 노랑 배지는 검정) + 진한 배지색 + 테두리.
import Cocoa

enum NBadge: String, CaseIterable {
    case red, blue, yellow

    // 흰/검정 N 과 대비가 나도록 원본(연한 살구색)보다 진한 색
    func fill(dark: Bool) -> NSColor {
        switch self {
        case .red: return NSColor(srgbRed: 0.93, green: 0.23, blue: 0.19, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.10, green: 0.44, blue: 0.93, alpha: 1)
        case .yellow: return NSColor(srgbRed: 1.00, green: 0.78, blue: 0.00, alpha: 1)
        }
    }

    /// N 색: 노랑 위 흰색은 안 보여서 검정
    var letter: NSColor { self == .yellow ? NSColor(white: 0.1, alpha: 1) : .white }
}

private enum KakaoAssets {
    static let bundle = Bundle(path: "/Applications/KakaoTalk.app")

    static func image(_ name: String) -> NSImage? { bundle?.image(forResource: name) }

    /// MenuIconWithNew(2x) 에서 빨간 배지 픽셀만 남긴 그레이스케일 마스크 (N 자리는 비어 있음)
    static let badgeMask: CGImage? = {
        guard let img = image("MenuIconWithNew"),
              let rep = img.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
              let cg = rep.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        guard let src = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        src.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var gray = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let r = Int(rgba[i * 4]), g = Int(rgba[i * 4 + 1]), a = Int(rgba[i * 4 + 3])
            // 빨강 계열(premultiplied 기준 r 이 g 보다 확연히 큼)만 배지로 본다
            if a > 0 && r * 10 > a * 6 && g * 10 < r * 6 { gray[i] = UInt8(a) }
        }
        guard let provider = CGDataProvider(data: Data(gray) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }()
}

/// N 배지가 여러 개일 때 배치 방식
enum BadgeStyle: String, CaseIterable {
    case row        // 가로로 겹쳐 쌓기 (빨강 원본 위치, 나머지 왼쪽 뒤로)
    case cascade    // 빨강 뒤로 왼쪽 위 대각선으로 살짝씩 비치게 (N 은 앞 배지만)
    case pie        // 원본 배지 하나를 색으로 나눠 칠하기
    case column     // 말풍선 오른쪽에 작은 배지를 세로로 쌓기 (1개일 땐 원본 위치)
    case dots       // 빨강 배지는 원본 그대로, 나머지 색은 작은 점으로
    case arcs       // 배지 하나 + 나머지 색을 바깥 링으로
    case triangle   // 작은 배지를 삼각형으로 모으기
    case peek       // 빨강 뒤로 위쪽에 다른 색 테두리만 살짝

    var title: String {
        switch self {
        case .row: return "가로로 겹치기"
        case .cascade: return "뒤로 겹치기"
        case .pie: return "한 배지 나눠 칠하기"
        case .column: return "오른쪽에 세로로 쌓기"
        case .dots: return "점으로 표시"
        case .arcs: return "바깥 링"
        case .triangle: return "삼각형으로 모으기"
        case .peek: return "위로 살짝 겹치기"
        }
    }
}

/// 어두운 메뉴바에서 배지 테두리
enum RingStyle: String, CaseIterable {
    case white, shade, none
}

enum StatusIcon {
    // 원본 에셋 기준(pt): 캔버스 20×20, 배지 지름 10 · 중심 (15, 8) · 둘레 1pt 도려냄
    static let size: CGFloat = 20
    static let badgeCenter = NSPoint(x: 15, y: 8)
    static let badgeRadius: CGFloat = 5
    static let gap: CGFloat = 1
    static let rowStep: CGFloat = 9                         // row: 왼쪽 뒤로 (정수: 1x 에서 선명)
    static let cascadeStep = CGVector(dx: -3, dy: 3)        // cascade: 왼쪽 위로

    /// badges 는 앞(맨 위)부터. 예: [.red, .blue, .yellow] → 빨강이 맨 앞.
    /// showBubble=false 면 알림이 있을 때 말풍선 없이 같은 배치의 N 배지만 (알림이 없으면 말풍선).
    static func image(badges: [NBadge], style: BadgeStyle = .row, ring: RingStyle = .white,
                      dimmed: Bool = false, showBubble: Bool = true) -> NSImage {
        let bubble = showBubble || badges.isEmpty
        let full = layoutImage(badges: badges, style: style, ring: ring, dimmed: dimmed, bubble: bubble)
        guard !bubble, let box = opaqueBounds(full) else { return full }
        // 말풍선이 빠진 만큼 배지 묶음을 메뉴바 높이에 맞춰 키운다 (최대 2배)
        let scale = min(badgesOnlyHeight / box.height, badgesOnlyMaxScale)
        let h: CGFloat = 22
        let size = NSSize(width: ceil(box.width * scale), height: h)
        let img = NSImage(size: size, flipped: false) { _ in
            let dest = NSRect(x: -box.minX * scale, y: ((h - box.height * scale) / 2).rounded() - box.minY * scale,
                              width: full.size.width * scale, height: full.size.height * scale)
            full.draw(in: dest)   // 드로잉 핸들러가 확대된 좌표계로 다시 그려져 선명
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = full.accessibilityDescription
        return img
    }

    /// 말풍선 끔일 때 배지 묶음 목표 높이(pt)와 최대 확대 배율
    /// (가로 배치 1줄 12pt → ×1.45 ≈ 17pt, 삼각형 17pt → 21pt)
    static let badgesOnlyHeight: CGFloat = 21
    static let badgesOnlyMaxScale: CGFloat = 1.45

    /// 이미지에서 불투명 픽셀이 있는 영역(pt, 0.5pt 단위)
    private static func opaqueBounds(_ image: NSImage) -> CGRect? {
        let scale = 2
        let w = Int(ceil(image.size.width)) * scale, h = Int(ceil(image.size.height)) * scale
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var x0 = w, x1 = -1, y0 = h, y1 = -1
        for y in 0..<h {
            for x in 0..<w where data[(y * w + x) * 4 + 3] > 8 {
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
        }
        guard x1 >= x0 else { return nil }
        // 비트맵 행 0 = 위쪽 → pt 좌표(아래가 0)로 변환
        let s = CGFloat(scale)
        return CGRect(x: CGFloat(x0) / s, y: CGFloat(h - 1 - y1) / s,
                      width: CGFloat(x1 - x0 + 1) / s, height: CGFloat(y1 - y0 + 1) / s)
    }

    private static func drawBubble(in rect: NSRect, dark: Bool, dimmed: Bool) {
        let name = (dimmed ? "Loggedout" : "") + (dark ? "DarkMenuIcon" : "MenuIcon")
        if let bubble = KakaoAssets.image(name) {
            bubble.draw(in: rect)
        } else {
            NSImage(systemSymbolName: "message.fill", accessibilityDescription: nil)?.draw(in: rect.insetBy(dx: 2, dy: 2))
        }
    }

    private static func layoutImage(badges: [NBadge], style: BadgeStyle, ring: RingStyle,
                                    dimmed: Bool, bubble: Bool) -> NSImage {
        if style == .column && badges.count >= 2 { return columnImage(badges: badges, ring: ring, dimmed: dimmed, bubble: bubble) }
        if [.dots, .arcs, .triangle, .peek].contains(style) && badges.count >= 2 {
            return clusterImage(badges: badges, style: style, ring: ring, dimmed: dimmed, bubble: bubble)
        }
        let n = badges.count
        // 배지별 중심 오프셋 (앞=0)
        let offsets: [CGVector] = (0..<n).map { i in
            switch style {
            case .row: return CGVector(dx: -CGFloat(i) * rowStep, dy: 0)
            case .cascade: return CGVector(dx: cascadeStep.dx * CGFloat(i), dy: cascadeStep.dy * CGFloat(i))
            default: return .zero
            }
        }
        let rr = badgeRadius + gap
        let minX = offsets.map { badgeCenter.x + $0.dx - rr }.min() ?? 0
        let shift = n == 0 ? 0 : ceil(max(0, -minX))                                 // 왼쪽으로 넘치면 민다
        let rightPad = n == 0 ? 0 : ceil(max(0, badgeCenter.x + rr - size))         // 앞 배지 테두리
        let width = size + shift + rightPad
        // row 로 3개 이상이면 말풍선을 캔버스 가운데(가운데 배지 위)에
        let bubbleX = (style == .row && n >= 3) ? ((width - size) / 2).rounded() - shift : 0

        let img = NSImage(size: NSSize(width: width, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ctx.translateBy(x: shift, y: 0)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)

            let bubbleRect = NSRect(x: bubbleX, y: 0, width: size, height: size)
            if bubble { drawBubble(in: bubbleRect, dark: dark, dimmed: dimmed) }

            let ring = ringColor(ring, dark: dark)
            switch style {
            case .pie, .column, .dots, .arcs, .triangle, .peek:
                if n > 0 {
                    drawBadge(ctx, center: badgeCenter, radius: badgeRadius, colors: badges.map { $0.fill(dark: dark) },
                              letter: n == 1 ? badges[0].letter : .white, withN: true, dark: dark, ring: ring)
                }
            case .row, .cascade:
                // 뒤(마지막)부터 그려서 앞 배지가 위로
                for (i, b) in badges.enumerated().reversed() {
                    let c = CGPoint(x: badgeCenter.x + offsets[i].dx, y: badgeCenter.y + offsets[i].dy)
                    drawBadge(ctx, center: c, radius: badgeRadius, colors: [b.fill(dark: dark)], letter: b.letter,
                              withN: style == .row || i == 0, dark: dark, ring: ring)
                }
            }
            ctx.endTransparencyLayer()
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = "카카오톡"
        return img
    }

    /// 배지 테두리. 어둡게 = 밝은/어두운 메뉴바 모두 배경과 배지를 가르는 옅은 그림자 테두리.
    static func ringColor(_ ring: RingStyle, dark: Bool) -> NSColor? {
        switch ring {
        case .white: return .white
        case .shade: return NSColor(white: 0, alpha: dark ? 0.45 : 0.28)
        case .none: return nil
        }
    }

    /// 배지 하나: 둘레 도려내기(+테두리) → 원본 배지 마스크(뚫린 N)를 radius 에 맞게 축소해 칠한다.
    /// colors 가 여러 개면 12시 방향부터 시계방향으로 등분.
    static func drawBadge(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat, colors: [NSColor],
                          letter: NSColor = .white, withN: Bool, dark: Bool, ring: NSColor?) {
        let rr = r + gap
        let ringRect = CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)
        ctx.setBlendMode(.clear); ctx.fillEllipse(in: ringRect); ctx.setBlendMode(.normal)
        if let ring { ctx.setFillColor(ring.cgColor); ctx.fillEllipse(in: ringRect) }

        // 1x 화면의 작은 배지: 원본 N 을 축소하면 뭉개지므로 픽셀 격자에 맞춘 4×4 N 을 찍는다
        if withN && r < badgeRadius && ctx.ctm.a < 1.5 && colors.count == 1 {
            ctx.setFillColor(colors[0].cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let px = [(0, 0), (0, 1), (0, 2), (0, 3), (3, 0), (3, 1), (3, 2), (3, 3), (1, 1), (2, 2)]   // (열, 행) 행0=위
            ctx.setFillColor(letter.cgColor)
            for (col, row) in px {
                ctx.fill(CGRect(x: c.x.rounded(.down) - 2 + CGFloat(col), y: c.y.rounded(.down) + 1 - CGFloat(row), width: 1, height: 1))
            }
            ctx.setBlendMode(.normal)
            return
        }

        // 원본 마스크(2px/pt)보다 크게 그리거나, 말풍선 끔처럼 정수가 아닌 배율로 확대될 때는
        // 마스크가 흐려지므로 원 + 벡터 N
        let px = ctx.ctm.a
        if withN && colors.count == 1 && (px * (r / badgeRadius) > 2.05 || abs(px - px.rounded()) > 0.01) {
            ctx.setFillColor(colors[0].cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let font = NSFont.systemFont(ofSize: r * 1.2, weight: .semibold)
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: "N", attributes: [.font: font, .foregroundColor: letter]))
            let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ctx.saveGState()
            ctx.textPosition = CGPoint(x: c.x - b.midX, y: c.y - b.midY)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
            return
        }

        ctx.saveGState()
        // 원본 배지 좌표계(중심 badgeCenter, 반지름 badgeRadius)로 변환
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: r / badgeRadius, y: r / badgeRadius)
        ctx.translateBy(x: -badgeCenter.x, y: -badgeCenter.y)
        let body = CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                          width: badgeRadius * 2, height: badgeRadius * 2)
        // N 구멍 아래에 N 색 원을 깔아 N 을 채운다
        if withN { ctx.setFillColor(letter.cgColor); ctx.fillEllipse(in: body) }
        if withN, let mask = KakaoAssets.badgeMask {
            ctx.clip(to: CGRect(x: 0, y: 0, width: size, height: size), mask: mask)
        } else {
            ctx.addEllipse(in: body); ctx.clip()
        }
        if colors.count == 1 {
            ctx.setFillColor(colors[0].cgColor); ctx.fill(body.insetBy(dx: -1, dy: -1))
        } else {
            let step = 2 * CGFloat.pi / CGFloat(colors.count)
            for (k, col) in colors.enumerated() {
                let start = CGFloat.pi / 2 - CGFloat(k) * step
                ctx.move(to: badgeCenter)
                ctx.addArc(center: badgeCenter, radius: badgeRadius + 1, startAngle: start, endAngle: start - step, clockwise: true)
                ctx.closePath()
                ctx.setFillColor(col.cgColor); ctx.fillPath()
            }
        }
        ctx.restoreGState()
    }

    // MARK: 2개 이상일 때 모아 그리는 디자인들 (캔버스 22pt, 말풍선은 y+1 에 원본 그대로)

    private struct Placement { let center: CGPoint; let radius: CGFloat; let badge: NBadge; let withN: Bool }

    /// 그리는 순서대로(뒤 → 앞) 배지 위치. 원본 배지 중심은 22pt 캔버스에서 (15, 9).
    private static func placements(_ badges: [NBadge], _ style: BadgeStyle) -> [Placement] {
        let front = badges[0], rest = Array(badges.dropFirst())
        switch style {
        case .dots:     // 말풍선 오른쪽 위에 지름 4pt 점
            return rest.enumerated().map { i, b in
                Placement(center: CGPoint(x: 21, y: 17 - CGFloat(i) * 5), radius: 2, badge: b, withN: false)
            } + [Placement(center: CGPoint(x: 15, y: 9), radius: badgeRadius, badge: front, withN: true)]
        case .peek:     // 같은 크기 배지를 위로 3pt 씩 밀어 뒤에 깔기 → 위쪽 테두리만 보임
            return rest.enumerated().reversed().map { i, b in
                Placement(center: CGPoint(x: 15, y: 9 + CGFloat(i + 1) * 3), radius: badgeRadius, badge: b, withN: false)
            } + [Placement(center: CGPoint(x: 15, y: 9), radius: badgeRadius, badge: front, withN: true)]
        case .triangle: // 지름 8pt: 아래 두 개(오른쪽 = 빨강) + 위 하나
            let spots = [CGPoint(x: 20, y: 5), CGPoint(x: 12, y: 5), CGPoint(x: 16, y: 12)]
            return badges.enumerated().reversed().map { i, b in
                Placement(center: spots[min(i, 2)], radius: 4, badge: b, withN: true)
            }
        default:
            return []
        }
    }

    private static func clusterImage(badges: [NBadge], style: BadgeStyle, ring: RingStyle, dimmed: Bool, bubble: Bool) -> NSImage {
        let h: CGFloat = 22
        let places = placements(badges, style)
        let arcsOuter: CGFloat = badgeRadius + gap + 2       // arcs: 바깥 링 반지름
        let right = style == .arcs ? 15 + arcsOuter + gap
                                   : (places.map { $0.center.x + $0.radius + gap }.max() ?? size)
        let img = NSImage(size: NSSize(width: ceil(max(size, right)), height: h), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let ringCol = ringColor(ring, dark: dark)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            let bubbleRect = NSRect(x: 0, y: 1, width: size, height: size)
            if bubble { drawBubble(in: bubbleRect, dark: dark, dimmed: dimmed) }
            if style == .arcs {
                // 바깥 링: 나머지 색을 12시부터 시계방향으로 등분
                let c = CGPoint(x: 15, y: 9)
                let outer = CGRect(x: c.x - arcsOuter - gap, y: c.y - arcsOuter - gap,
                                   width: (arcsOuter + gap) * 2, height: (arcsOuter + gap) * 2)
                ctx.setBlendMode(.clear); ctx.fillEllipse(in: outer); ctx.setBlendMode(.normal)
                if let ringCol { ctx.setFillColor(ringCol.cgColor); ctx.fillEllipse(in: outer) }
                let rest = Array(badges.dropFirst())
                let step = 2 * CGFloat.pi / CGFloat(rest.count)
                for (k, b) in rest.enumerated() {
                    let start = CGFloat.pi / 2 - CGFloat(k) * step
                    ctx.move(to: c)
                    ctx.addArc(center: c, radius: arcsOuter, startAngle: start, endAngle: start - step, clockwise: true)
                    ctx.closePath()
                    ctx.setFillColor(b.fill(dark: dark).cgColor); ctx.fillPath()
                }
                drawBadge(ctx, center: c, radius: badgeRadius, colors: [badges[0].fill(dark: dark)], letter: badges[0].letter,
                          withN: true, dark: dark, ring: nil)
            } else {
                for p in places {
                    drawBadge(ctx, center: p.center, radius: p.radius, colors: [p.badge.fill(dark: dark)], letter: p.badge.letter,
                              withN: p.withN, dark: dark, ring: ringCol)
                }
            }
            ctx.endTransparencyLayer()
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = "카카오톡"
        return img
    }

    // column: 메뉴바 두께(22pt) 안에 지름 8pt 배지를 7pt 간격으로 세로로 쌓는다(최대 3개 = 22pt).
    static let columnHeight: CGFloat = 22
    static let columnRadius: CGFloat = 4
    static let columnSpacing: CGFloat = 7
    static let columnX: CGFloat = 20        // 배지 열 중심 x (말풍선 오른쪽 끝에 살짝 걸침)

    /// 말풍선은 가리지 않고, 오른쪽에 배지 열. 맨 아래 = 첫 배지(빨강), 위로 파랑·노랑.
    private static func columnImage(badges: [NBadge], ring: RingStyle, dimmed: Bool, bubble: Bool) -> NSImage {
        let n = badges.count
        let total = columnRadius * 2 + CGFloat(n - 1) * columnSpacing
        let startY = ((columnHeight - total) / 2 + columnRadius).rounded()
        let width = columnX + columnRadius + gap
        let img = NSImage(size: NSSize(width: ceil(width), height: columnHeight), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            let bubbleRect = NSRect(x: 0, y: (columnHeight - size) / 2, width: size, height: size)
            if bubble { drawBubble(in: bubbleRect, dark: dark, dimmed: dimmed) }
            // 위(뒤)부터 그려서 아래(앞) 배지가 위로 오게
            for (i, b) in badges.enumerated().reversed() {
                let c = CGPoint(x: columnX, y: startY + CGFloat(i) * columnSpacing)
                drawBadge(ctx, center: c, radius: columnRadius, colors: [b.fill(dark: dark)], letter: b.letter,
                          withN: true, dark: dark, ring: ringColor(ring, dark: dark))
            }
            ctx.endTransparencyLayer()
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = "카카오톡"
        return img
    }

    /// 설정 미리보기용: 지정한 메뉴바 모양(밝음/어두움)으로 미리 그린 비트맵
    static func snapshot(badges: [NBadge], style: BadgeStyle, ring: RingStyle, showBubble: Bool,
                         dark: Bool, scale: CGFloat = 2) -> NSImage {
        let icon = image(badges: badges, style: style, ring: ring, showBubble: showBubble)
        let size = icon.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return icon }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            icon.draw(in: NSRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }

    /// 디버그: 스타일별 비교 시트. 실제 메뉴바처럼 1x 로 그린 뒤 픽셀 그대로 확대(scale).
    static func renderComparison(to path: String, scale: Int = 8, res: Int = 1) {
        let variants: [(BadgeStyle, RingStyle, Bool)] = [(.triangle, .shade, true), (.triangle, .shade, false),
                                                         (.row, .shade, true), (.row, .shade, false)]
        let combos: [[NBadge]] = [[.red], [.red, .blue], [.red, .blue, .yellow]]
        let backgrounds: [(NSAppearance.Name, NSColor)] = [
            (.darkAqua, NSColor(srgbRed: 0.24, green: 0.50, blue: 0.72, alpha: 1)),   // 파란 배경화면
            (.darkAqua, NSColor(white: 0.12, alpha: 1)),
            (.aqua, NSColor(white: 0.93, alpha: 1)),
            (.aqua, NSColor(srgbRed: 0.55, green: 0.84, blue: 0.99, alpha: 1)),        // 밝은 하늘색 배경화면
        ]
        let cellW = 40, cellH = 26
        let cols = combos.count * backgrounds.count, rows = variants.count
        let W = cellW * cols, H = cellH * rows
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W * res, pixelsHigh: H * res, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = NSSize(width: W, height: H)   // res 배율로 렌더
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (r, v) in variants.enumerated() {
            for (bi, bg) in backgrounds.enumerated() {
                for (ci, combo) in combos.enumerated() {
                    let x = CGFloat((bi * combos.count + ci) * cellW), y = CGFloat((rows - 1 - r) * cellH)
                    bg.1.setFill(); NSRect(x: x, y: y, width: CGFloat(cellW), height: CGFloat(cellH)).fill()
                    NSAppearance(named: bg.0)!.performAsCurrentDrawingAppearance {
                        let im = image(badges: combo, style: v.0, ring: v.1, showBubble: v.2)
                        im.draw(in: NSRect(x: x + ((CGFloat(cellW) - im.size.width) / 2).rounded(),
                                           y: y + ((CGFloat(cellH) - im.size.height) / 2).rounded(),
                                           width: im.size.width, height: im.size.height))
                    }
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        // 픽셀 그대로 확대
        guard let cg = rep.cgImage,
              let big = CGContext(data: nil, width: W * scale, height: H * scale, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        big.interpolationQuality = .none
        big.draw(cg, in: CGRect(x: 0, y: 0, width: W * scale, height: H * scale))
        guard let out = big.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
