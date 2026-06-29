import SwiftUI

// Machi AI 自有品牌标志 —— 「灵光 Spark」。与 web 端 components/brand/MachiAIMark.tsx
// 像素级一致:Apple 风多彩渐变 squircle(粉→紫→蓝→青) + 一颗精致的四角星灵光 +
// 右上一颗微光点 + 玻璃高光。
//   MachiAIMark   渐变 squircle 徽标 —— 聊天头像 / 入口卡
//   MachiAIGlyph  单色线形灵光 —— 底部 Tab / 行内,继承 .foregroundStyle 着色
//
// 几何沿用 web(100 网格):主灵光以 (50,50) 为心、半径 34 的四角星,四边内凹;
// 微光点在右上 (74,28)。

/// 四角星「灵光」。`includeMicro` 时附带右上的微光点(徽标用);
/// 线形 Glyph 只取主星描边。
private struct MachiSparkShape: Shape {
    var includeMicro: Bool = true

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let ox = rect.minX + (rect.width - 100 * s) / 2
        let oy = rect.minY + (rect.height - 100 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var path = Path()
        // 主灵光(四角星,四边内凹细腰)
        path.move(to: p(50, 16))
        path.addCurve(to: p(84, 50), control1: p(51.5, 38), control2: p(62, 48.5))
        path.addCurve(to: p(50, 84), control1: p(62, 51.5), control2: p(51.5, 62))
        path.addCurve(to: p(16, 50), control1: p(48.5, 62), control2: p(38, 51.5))
        path.addCurve(to: p(50, 16), control1: p(38, 48.5), control2: p(48.5, 38))
        path.closeSubpath()

        if includeMicro {
            // 微光点(右上)
            path.move(to: p(74, 21))
            path.addCurve(to: p(81, 27.7), control1: p(74.6, 26), control2: p(75.7, 27.1))
            path.addCurve(to: p(74, 34.4), control1: p(75.7, 28.3), control2: p(74.6, 29.4))
            path.addCurve(to: p(67, 27.7), control1: p(73.4, 29.4), control2: p(72.3, 28.3))
            path.addCurve(to: p(74, 21), control1: p(72.3, 27.1), control2: p(73.4, 26))
            path.closeSubpath()
        }
        return path
    }
}

/// 渐变徽标:teal squircle + 玻璃高光 + 白色灵光。
struct MachiAIMark: View {
    var size: CGFloat = 48

    var body: some View {
        let corner = size * 0.28
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 1.000, green: 0.435, blue: 0.710), location: 0.0),  // #FF6FB5
                            .init(color: Color(red: 0.627, green: 0.420, blue: 0.941), location: 0.38), // #A06BF0
                            .init(color: Color(red: 0.357, green: 0.553, blue: 0.937), location: 0.72), // #5B8DEF
                            .init(color: Color(red: 0.212, green: 0.839, blue: 0.765), location: 1.0),  // #36D6C3
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // 玻璃高光,左上柔光带来体积感
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0)]),
                                center: UnitPoint(x: 0.32, y: 0.26),
                                startRadius: 0,
                                endRadius: size * 0.7
                            )
                        )
                )
            MachiSparkShape(includeMicro: true)
                .fill(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 单色线形:四角星灵光描边,继承环境 .foregroundStyle(用于底部 Tab 等)。
struct MachiAIGlyph: View {
    var lineWidth: CGFloat = 2.2

    var body: some View {
        // MachiSparkShape scales its 100-grid path to fill the view's frame, so
        // lineWidth is already in the rendered point space — no grid rescale.
        MachiSparkShape(includeMicro: false)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)
    }
}
