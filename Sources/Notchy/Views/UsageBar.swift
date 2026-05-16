import SwiftUI

// MARK: - Usage bar (5 segments + percent text)

struct UsageBar: View {
    var pct: Double  // 0-100
    var segmentCount: Int = 5
    var showPercent: Bool = true

    private var filledSegments: Int {
        let frac = max(0, min(100, pct)) / 100.0
        return Int((frac * Double(segmentCount)).rounded(.up))
    }

    private var color: Color {
        switch pct {
        case ..<70:  return Color(red: 0.30, green: 0.85, blue: 0.45)
        case ..<90:  return Color(red: 0.98, green: 0.78, blue: 0.20)
        default:     return Color(red: 0.95, green: 0.35, blue: 0.30)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<segmentCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < filledSegments ? color : Color.white.opacity(0.18))
                        .frame(width: 6, height: 8)
                }
            }
            if showPercent {
                Text("\(Int(pct.rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .monospacedDigit()
            }
        }
    }
}
