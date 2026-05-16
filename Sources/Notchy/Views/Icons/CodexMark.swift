import AppKit
import SwiftUI

struct CodexMark: View {
    var size: CGFloat = 16

    private var codexImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "codex", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        return image
    }

    var body: some View {
        Group {
            if let codexImage {
                Image(nsImage: codexImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Text("C")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.78))
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.92)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Codex")
    }
}
