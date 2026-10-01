import AppKit
import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    constructionRings
                    appIcon
                }
                .frame(width: 380, height: 380)

                Spacer().frame(height: 32)

                Text("PROSETTA")
                    .font(.custom("Georgia-Italic", size: 13))
                    .tracking(9)
                    .foregroundStyle(Color(white: 0.1).opacity(0.75))

                Spacer().frame(height: 14)

                Text("Gregory Wang")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Color(white: 0, opacity: 0.35))

                Spacer().frame(height: 8)

                Text("v0.1.0  ·  2026")
                    .font(.system(size: 11, weight: .light))
                    .kerning(1.5)
                    .foregroundStyle(Color(white: 0, opacity: 0.2))

                Spacer()
            }
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    private var constructionRings: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2

            for (i, r) in [175.0, 138.0, 100.0, 58.0].enumerated() {
                var path = Path()
                path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                let dashed = !i.isMultiple(of: 2)
                ctx.stroke(
                    path,
                    with: .color(Color(white: 0, opacity: dashed ? 0.07 : 0.12)),
                    style: StrokeStyle(lineWidth: 0.6, dash: dashed ? [4, 4] : [])
                )
            }

            let lines: [(CGPoint, CGPoint)] = [
                (CGPoint(x: cx, y: 0),          CGPoint(x: cx, y: size.height)),
                (CGPoint(x: 0, y: cy),           CGPoint(x: size.width, y: cy)),
                (CGPoint(x: 0, y: 0),            CGPoint(x: size.width, y: size.height)),
                (CGPoint(x: size.width, y: 0),   CGPoint(x: 0, y: size.height)),
            ]
            for (a, b) in lines {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(Color(white: 0, opacity: 0.06)), lineWidth: 0.5)
            }

            let ticks: [(CGPoint, CGPoint)] = [
                (CGPoint(x: cx - 5, y: cy - 175), CGPoint(x: cx + 5, y: cy - 175)),
                (CGPoint(x: cx - 5, y: cy + 175), CGPoint(x: cx + 5, y: cy + 175)),
                (CGPoint(x: cx - 175, y: cy - 5), CGPoint(x: cx - 175, y: cy + 5)),
                (CGPoint(x: cx + 175, y: cy - 5), CGPoint(x: cx + 175, y: cy + 5)),
            ]
            for (a, b) in ticks {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(Color(white: 0, opacity: 0.25)), lineWidth: 0.9)
            }
        }
    }

    private var appIcon: some View {
        Group {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 220, height: 220)
            }
        }
    }
}
