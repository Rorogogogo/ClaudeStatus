import SwiftUI

struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY
        
        path.move(to: CGPoint(x: cx, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: cy), control: CGPoint(x: cx + w * 0.16, y: cy - h * 0.16))
        path.addQuadCurve(to: CGPoint(x: cx, y: rect.maxY), control: CGPoint(x: cx + w * 0.16, y: cy + h * 0.16))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: cy), control: CGPoint(x: cx - w * 0.16, y: cy + h * 0.16))
        path.addQuadCurve(to: CGPoint(x: cx, y: rect.minY), control: CGPoint(x: cx - w * 0.16, y: cy - h * 0.16))
        
        return path
    }
}

struct AntigravityMark: View {
    var size: CGFloat = 16

    var body: some View {
        SparkleShape()
            .fill(LinearGradient(
                colors: [
                    Color(red: 0.35, green: 0.65, blue: 1.0),
                    Color(red: 0.60, green: 0.40, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            .accessibilityLabel("Antigravity")
    }
}
