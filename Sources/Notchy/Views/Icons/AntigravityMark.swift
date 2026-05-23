import SwiftUI

struct AntigravityMark: View {
    var size: CGFloat = 16

    var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2
            let cy = h / 2
            
            var path = Path()
            path.move(to: CGPoint(x: cx, y: 0))
            path.addQuadCurve(to: CGPoint(x: w, y: cy), control: CGPoint(x: cx + w * 0.16, y: cy - h * 0.16))
            path.addQuadCurve(to: CGPoint(x: cx, y: h), control: CGPoint(x: cx + w * 0.16, y: cy + h * 0.16))
            path.addQuadCurve(to: CGPoint(x: 0, y: cy), control: CGPoint(x: cx - w * 0.16, y: cy + h * 0.16))
            path.addQuadCurve(to: CGPoint(x: cx, y: 0), control: CGPoint(x: cx - w * 0.16, y: cy - h * 0.16))
            
            let gradient = Gradient(colors: [
                Color(red: 0.35, green: 0.65, blue: 1.0),
                Color(red: 0.60, green: 0.40, blue: 1.0)
            ])
            ctx.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w, y: h)))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Antigravity")
    }
}
