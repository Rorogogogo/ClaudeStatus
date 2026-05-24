import SwiftUI

// Static four-point Gemini sparkle. A plain Shape rendered once and
// GPU-composited — never a Canvas, never animated, no timers. Mirrors the
// CodexMark/ClaudeCrabIcon API: a `size` knob and a fixed `.frame(size)`.
struct AntigravitySparkle: Shape {
    func path(in rect: CGRect) -> Path {
        // 4-point star: tips at N/E/S/W, waist pinched toward the center.
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let w = r * 0.32                       // waist half-width
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))            // top tip
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y),    // right tip
                       control: CGPoint(x: c.x + w, y: c.y - w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r),    // bottom tip
                       control: CGPoint(x: c.x + w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y),    // left tip
                       control: CGPoint(x: c.x - w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r),    // back to top
                       control: CGPoint(x: c.x - w, y: c.y - w))
        p.closeSubpath()
        return p
    }
}

struct AntigravityMark: View {
    var size: CGFloat = 14
    var body: some View {
        AntigravitySparkle()
            .fill(Color(red: 0.36, green: 0.56, blue: 0.96)) // Gemini blue
            .frame(width: size, height: size)
            .accessibilityLabel("Antigravity")
    }
}
