import AppKit
import SwiftUI

// MARK: - Notch view (collapsed state, matching Vibe Notch's pre-expansion look)

// Hover state is driven externally by a global mouse-location poll. The
// collapsed notch remains click-through; the expanded panel becomes solid so
// its controls can receive clicks.
@MainActor
final class PillHoverState: ObservableObject {
    @Published var hovering: Bool = false
}

struct NotchContentView: View {
    @ObservedObject var claudeStatus: AgentStatusModel
    @ObservedObject var claudeUsage: AgentUsageModel
    @ObservedObject var codexStatus: AgentStatusModel
    @ObservedObject var codexUsage: AgentUsageModel
    @StateObject private var repoStats = GitHubRepoStatsModel()
    let collapsedSize: CGSize
    let expandedSize: CGSize
    @ObservedObject var hoverState: PillHoverState

    private var hovering: Bool { hoverState.hovering }

    private var claudeSnapshot: AgentSnapshot {
        AgentSnapshot(
            kind: .claude,
            name: "Claude",
            status: effectiveStatus(for: claudeStatus),
            project: claudeStatus.project,
            lastEventTs: claudeStatus.lastEventTs,
            usage: claudeUsage
        )
    }

    private var codexSnapshot: AgentSnapshot {
        AgentSnapshot(
            kind: .codex,
            name: "Codex",
            status: effectiveStatus(for: codexStatus),
            project: codexStatus.project,
            lastEventTs: codexStatus.lastEventTs,
            usage: codexUsage
        )
    }

    private var activeSnapshot: AgentSnapshot {
        codexSnapshot.lastEventTs > claudeSnapshot.lastEventTs ? codexSnapshot : claudeSnapshot
    }

    private func effectiveStatus(for model: AgentStatusModel) -> String {
        if model.status == "waiting" {
            let age = Int(Date().timeIntervalSince1970) - model.lastEventTs
            if age > 3 { return "idle" }
        }
        return model.status
    }

    var dotColor: Color {
        switch activeSnapshot.status {
        case "working": return Color(red: 0.30, green: 0.85, blue: 0.45)
        case "waiting": return Color(red: 0.98, green: 0.78, blue: 0.20)
        case "error":   return Color(red: 0.95, green: 0.35, blue: 0.30)
        default:        return Color(white: 0.45)
        }
    }

    private var currentSize: CGSize {
        hovering ? expandedSize : collapsedSize
    }

    private func resetLabel(_ unix: Int) -> String {
        guard unix > 0 else { return "—" }
        let remaining = max(0, unix - Int(Date().timeIntervalSince1970))
        let hours = remaining / 3600
        let mins  = (remaining % 3600) / 60
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        if hours > 0   { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    var body: some View {
        // Outer container is sized to the expanded bounding box but is
        // entirely transparent. The pill itself sits centered at the top —
        // hover detection lives on the pill view only, so the empty area
        // around it does NOT trigger expansion or block clicks below.
        ZStack(alignment: .top) {
            Color.clear
                .frame(width: expandedSize.width, height: expandedSize.height)
                .allowsHitTesting(false)

            pillView
                .frame(width: currentSize.width, height: currentSize.height)
                .allowsHitTesting(hovering)
                .modifier(AntigravityModifier(enabled: !hovering))
        }
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: hovering)
    }

    private var pillView: some View {
        ZStack(alignment: .top) {
            NotchShape(
                topCornerRadius: 6,
                bottomCornerRadius: hovering ? 22 : 14
            )
            .fill(Color.black)

            VStack(spacing: 0) {
                // Top row: collapsed uses tight 14pt margins to hug the pill;
                // expanded uses 22pt to line up with the detail rows below.
                HStack(spacing: 0) {
                    Spacer().frame(width: hovering ? 22 : 14)
                    if activeSnapshot.kind == .claude {
                        ClaudeCrabIcon(size: 14)
                    } else {
                        CodexMark(size: 15)
                    }
                    Spacer(minLength: 0)
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: dotColor.opacity(0.7), radius: 2)
                    Spacer().frame(width: hovering ? 22 : 14)
                }
                .frame(width: currentSize.width, height: collapsedSize.height)

                if hovering {
                    expandedDetail
                        .padding(.horizontal, 22)
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                        .frame(width: currentSize.width)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            agentRow(claudeSnapshot, showUsage: true)
            Divider().background(Color.white.opacity(0.12))
            agentRow(codexSnapshot, showUsage: true)
            Divider().background(Color.white.opacity(0.12))
            systemRow
            footerControls
                .padding(.top, 4)
        }
    }

    private var systemRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 12, height: 12)
                Text("System")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.82))
                Spacer()
                Text(uptimeText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }

    private var uptimeText: String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let hours   = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 { return "up \(hours / 24)d \(hours % 24)h" }
        if hours > 0   { return "up \(hours)h \(minutes)m" }
        return "up \(minutes)m"
    }

    private var footerControls: some View {
        HStack(spacing: 8) {
            repoButton {
                openGitHub()
            }
            Spacer(minLength: 8)
            footerButton(title: "Quit", systemImage: "xmark") {
                NSApp.terminate(nil)
            }
        }
    }

    private static let githubMarkImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "github", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()

    private func repoButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Group {
                        if let mark = Self.githubMarkImage {
                            Image(nsImage: mark)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                    }
                    .frame(width: 11, height: 11)
                    Text(repoStats.repoName)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.24).opacity(0.9))
                    Text(repoStats.starsText)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .foregroundColor(.white.opacity(0.68))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Open GitHub")
    }

    private func footerButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.66))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func openGitHub() {
        guard let url = URL(string: repoStats.repoURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func agentRow(_ snapshot: AgentSnapshot, showUsage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if snapshot.kind == .claude {
                    ClaudeCrabIcon(size: 12)
                } else {
                    CodexMark(size: 13)
                }
                Text(snapshot.name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.82))
                if !snapshot.project.isEmpty {
                    Text(snapshot.project)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                Text(snapshot.status)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }

            if showUsage, let usage = snapshot.usage {
                usageRow(label: "5h block", pct: usage.blockPct, reset: usage.blockResetUnix)
                usageRow(label: "This week", pct: usage.weeklyPct, reset: usage.weeklyResetUnix)
            }
        }
    }

    private func usageRow(label: String, pct: Double, reset: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            HStack {
                UsageBar(pct: pct, segmentCount: 16, showPercent: false)
                Spacer()
                Text("\(Int(pct.rounded()))% · resets in \(resetLabel(reset))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Antigravity floating modifier
//
// Uses SwiftUI's withAnimation(.repeatForever) which is backed by Core Animation
// and runs entirely on the render thread — no timer callbacks, no body re-evals
// per frame. A naive Timer-based implementation would fire at 60 fps and force
// SwiftUI to re-diff the entire pill hierarchy on every frame, causing visible jank.
//
// When hovering starts the float is cancelled with a matching spring so the
// transition into the expanded state feels seamless.
private struct AntigravityModifier: ViewModifier {
    var enabled: Bool
    @State private var floatOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(y: floatOffset)
            .onChange(of: enabled, initial: true) { _, isEnabled in
                if isEnabled {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        floatOffset = 3
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        floatOffset = 0
                    }
                }
            }
    }
}
