import SwiftUI

// Machi AI 自有品牌标志 —— 与 web 端 components/brand/MachiAIMark.tsx 像素级一致。
// 复用 Machi 的「M」字标,在 M 的怀抱里嵌一颗四角星「灵光」(不是通用 sparkles)。
//   MachiAIMark   渐变 squircle 徽标 —— 聊天头像 / 入口卡
//   MachiAIGlyph  单色线形字符 —— 底部 Tab / 行内,继承 .foregroundStyle 着色
//
// 几何沿用 web:徽标在 100 网格里 M 顶点 (30,72)(30,40)(50,58)(70,40)(70,72),
// 灵光为谷底上方的四角星;线形在 24 网格里 M 顶点 (5,18)(5,8)(12,14)(19,8)(19,18)。

private let mPoints100: [CGPoint] = [
    CGPoint(x: 30, y: 72), CGPoint(x: 30, y: 40), CGPoint(x: 50, y: 58),
    CGPoint(x: 70, y: 40), CGPoint(x: 70, y: 72),
]
private let sparkPoints100: [CGPoint] = [
    CGPoint(x: 50, y: 39.5), CGPoint(x: 52.8, y: 44.2), CGPoint(x: 57.5, y: 47),
    CGPoint(x: 52.8, y: 49.8), CGPoint(x: 50, y: 54.5), CGPoint(x: 47.2, y: 49.8),
    CGPoint(x: 42.5, y: 47), CGPoint(x: 47.2, y: 44.2),
]
private let mPoints24: [CGPoint] = [
    CGPoint(x: 5, y: 18), CGPoint(x: 5, y: 8), CGPoint(x: 12, y: 14),
    CGPoint(x: 19, y: 8), CGPoint(x: 19, y: 18),
]
private let sparkPoints24: [CGPoint] = [
    CGPoint(x: 12, y: 8), CGPoint(x: 12.9, y: 9.7), CGPoint(x: 14.2, y: 10.6),
    CGPoint(x: 12.9, y: 11.5), CGPoint(x: 12, y: 13.2), CGPoint(x: 11.1, y: 11.5),
    CGPoint(x: 9.8, y: 10.6), CGPoint(x: 11.1, y: 9.7),
]

private func scaledPath(_ pts: [CGPoint], box: CGFloat, in rect: CGRect, closed: Bool) -> Path {
    let s = min(rect.width, rect.height) / box
    let ox = rect.minX + (rect.width - box * s) / 2
    let oy = rect.minY + (rect.height - box * s) / 2
    var path = Path()
    for (i, pt) in pts.enumerated() {
        let p = CGPoint(x: ox + pt.x * s, y: oy + pt.y * s)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    if closed { path.closeSubpath() }
    return path
}

private struct MachiMShape: Shape {
    let box: CGFloat
    let pts: [CGPoint]
    func path(in rect: CGRect) -> Path { scaledPath(pts, box: box, in: rect, closed: false) }
}

private struct MachiSparkShape: Shape {
    let box: CGFloat
    let pts: [CGPoint]
    func path(in rect: CGRect) -> Path { scaledPath(pts, box: box, in: rect, closed: true) }
}

/// 渐变徽标:teal squircle + 白色 M + 白色灵光。
struct MachiAIMark: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.137, green: 0.675, blue: 0.573), // #23AC92
                            Color(red: 0.047, green: 0.322, blue: 0.278), // #0C5247
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            MachiMShape(box: 100, pts: mPoints100)
                .stroke(style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.white)
            MachiSparkShape(box: 100, pts: sparkPoints100)
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 单色线形:M + 灵光,继承环境 .foregroundStyle(用于底部 Tab 等)。
struct MachiAIGlyph: View {
    var lineWidth: CGFloat = 2.2

    var body: some View {
        ZStack {
            MachiMShape(box: 24, pts: mPoints24)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            MachiSparkShape(box: 24, pts: sparkPoints24)
        }
        .accessibilityHidden(true)
    }
}
