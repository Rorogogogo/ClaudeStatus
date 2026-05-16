import SwiftUI

// MARK: - Claude crab icon (pixel-art, ported from Vibe Notch's ClaudeCrabIcon)

struct ClaudeCrabIcon: View {
    var size: CGFloat = 14
    var color: Color = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        Canvas { ctx, canvasSize in
            let scale = size / 52.0           // viewBox is 66x52
            let xOffset = (canvasSize.width - 66 * scale) / 2

            func applyOffset(_ p: Path) -> Path {
                p.applying(CGAffineTransform(scaleX: scale, y: scale)
                            .translatedBy(x: xOffset / scale, y: 0))
            }

            // Antennae
            ctx.fill(applyOffset(Path(CGRect(x: 0,  y: 13, width: 6, height: 13))), with: .color(color))
            ctx.fill(applyOffset(Path(CGRect(x: 60, y: 13, width: 6, height: 13))), with: .color(color))

            // Legs (static, no walking animation)
            for x in [CGFloat(6), 18, 42, 54] {
                ctx.fill(applyOffset(Path(CGRect(x: x, y: 39, width: 6, height: 13))), with: .color(color))
            }

            // Body
            ctx.fill(applyOffset(Path(CGRect(x: 6, y: 0, width: 54, height: 39))), with: .color(color))

            // Eyes (black squares on body)
            ctx.fill(applyOffset(Path(CGRect(x: 12, y: 13, width: 6, height: 6.5))), with: .color(.black))
            ctx.fill(applyOffset(Path(CGRect(x: 48, y: 13, width: 6, height: 6.5))), with: .color(.black))
        }
        .frame(width: size, height: size)
    }
}
