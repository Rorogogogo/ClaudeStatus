import AppKit
import Combine
import SwiftUI

// MARK: - Model

@MainActor
final class AgentStatusModel: ObservableObject {
    @Published var status: String = "idle"
    @Published var project: String = ""
    @Published var lastEventTs: Int = 0

    private var fileSource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var lastMtime: Date?
    private let statePath: String

    init(path: String) {
        statePath = path
        ensureFileExists()
        reload()
        watchFile()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pollIfChanged()
        }
        // Periodic re-publish so age-based UI checks (waiting → idle) update without new events
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    private func pollIfChanged() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: statePath),
              let mtime = attrs[.modificationDate] as? Date else { return }
        if lastMtime != mtime {
            lastMtime = mtime
            reload()
        }
    }

    private func ensureFileExists() {
        let dir = (statePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: statePath) {
            FileManager.default.createFile(atPath: statePath, contents: Data("idle\t0\t\n".utf8))
        }
    }

    func reload() {
        guard let raw = try? String(contentsOfFile: statePath, encoding: .utf8) else { return }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.indices.contains(0) { status = parts[0] }
        if parts.indices.contains(1) { lastEventTs = Int(parts[1]) ?? 0 }
        if parts.indices.contains(2) { project = parts[2] }
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(statePath, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            self.reload()
            // If the file was unlinked or replaced, re-establish the watch on the new inode.
            if flags.contains(.delete) || flags.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.ensureFileExists()
                    self.watchFile()
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
    }
}

// MARK: - Usage model (5h block + weekly token quota, written by usage-tick.sh)

@MainActor
final class AgentUsageModel: ObservableObject {
    @Published var blockPct: Double = 0
    @Published var weeklyPct: Double = 0
    @Published var blockResetUnix: Int = 0
    @Published var weeklyResetUnix: Int = 0

    private var fileSource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var lastMtime: Date?
    private let path: String

    init(path: String, createIfMissing: Bool = true) {
        self.path = path
        if createIfMissing { ensureFileExists() }
        reload()
        watchFile()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollIfChanged()
        }
    }

    private func ensureFileExists() {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: Data("0\t0\t0\t0\t0\t0\n".utf8))
        }
    }

    private func pollIfChanged() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else { return }
        if lastMtime != mtime {
            lastMtime = mtime
            reload()
        }
    }

    func reload() {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.indices.contains(0) { blockPct        = Double(parts[0]) ?? 0 }
        if parts.indices.contains(1) { blockResetUnix  = Int(parts[1]) ?? 0 }
        if parts.indices.contains(2) { weeklyPct       = Double(parts[2]) ?? 0 }
        if parts.indices.contains(3) { weeklyResetUnix = Int(parts[3]) ?? 0 }
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            self.reload()
            if flags.contains(.delete) || flags.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.ensureFileExists()
                    self.watchFile()
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
    }
}

enum AgentKind {
    case claude
    case codex
}

struct AgentSnapshot {
    let kind: AgentKind
    let name: String
    let status: String
    let project: String
    let lastEventTs: Int
    let usage: AgentUsageModel?
}

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

// MARK: - NSScreen notch detection (from Vibe Notch's Ext+NSScreen.swift)

extension NSScreen {
    var resolvedNotchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 224, height: 38)
        }
        let notchHeight = safeAreaInsets.top
        let fullWidth = frame.width
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        guard leftPadding > 0, rightPadding > 0 else {
            return CGSize(width: 180, height: notchHeight)
        }
        let notchWidth = fullWidth - leftPadding - rightPadding + 4
        return CGSize(width: notchWidth, height: notchHeight)
    }

    var hasNotch: Bool { safeAreaInsets.top > 0 }
}

// MARK: - Notch shape (curves inward at top, outward at bottom — Dynamic Island style)

struct NotchShape: Shape {
    var topCornerRadius: CGFloat = 6
    var bottomCornerRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

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

struct CodexMark: View {
    var body: some View {
        Text("C")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .frame(width: 14, height: 14)
            .background(Circle().fill(Color.white.opacity(0.9)))
    }
}

// MARK: - Notch view (collapsed state, matching Vibe Notch's pre-expansion look)

// Hover state driven externally (by a global mouse-location poll in
// AppDelegate) so the panel can be fully click-through while still expanding
// on hover.
@MainActor
final class PillHoverState: ObservableObject {
    @Published var hovering: Bool = false
}

struct NotchContentView: View {
    @ObservedObject var claudeStatus: AgentStatusModel
    @ObservedObject var claudeUsage: AgentUsageModel
    @ObservedObject var codexStatus: AgentStatusModel
    @ObservedObject var codexUsage: AgentUsageModel
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
                .allowsHitTesting(false)
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
            .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 18, y: 6)

            VStack(spacing: 0) {
                // Top row: collapsed uses tight 14pt margins to hug the pill;
                // expanded uses 22pt to line up with the detail rows below.
                HStack(spacing: 0) {
                    Spacer().frame(width: hovering ? 22 : 14)
                    if activeSnapshot.kind == .claude {
                        ClaudeCrabIcon(size: 14)
                    } else {
                        CodexMark()
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
                        .padding(.top, 6)
                        .padding(.bottom, 14)
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
            agentRow(codexSnapshot, showUsage: false)
            HStack {
                Spacer()
                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Quit")
            }
            .padding(.top, 2)
        }
    }

    private func agentRow(_ snapshot: AgentSnapshot, showUsage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if snapshot.kind == .claude {
                    ClaudeCrabIcon(size: 12)
                } else {
                    CodexMark()
                        .scaleEffect(0.86)
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

// MARK: - Notch panel

final class NotchPanel: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        // Fully click-through; hover is detected via a global mouse-location
        // poll in AppDelegate, not via panel-local mouse events.
        ignoresMouseEvents = true
        level = .init(Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NotchPanel?
    let claudeStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.claude/state/status")
    let claudeUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.claude/state/usage")
    let codexStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.codex/notchy/status")
    let codexUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.codex/notchy/usage")
    private var screenObserver: NSObjectProtocol?
    private var visibilityTimer: Timer?
    private var visibilityCancellables = Set<AnyCancellable>()

    // Hover detection (panel is click-through, so we poll the global cursor).
    private var hoverState = PillHoverState()
    private var hoverTimer: Timer?
    private var collapsedScreenRect: CGRect = .zero
    private var expandedScreenRect: CGRect = .zero

    private let idleHideAfterSeconds: TimeInterval = 10 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuild()
        applyVisibility()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuild()
                self?.applyVisibility()
            }
        }

        // React the instant either status file changes.
        claudeStatus.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyVisibility() }
        }
        .store(in: &visibilityCancellables)

        codexStatus.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyVisibility() }
        }
        .store(in: &visibilityCancellables)

        // Periodic check to hide after the idle window elapses with no new events
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.applyVisibility() }
        }

        // Poll the global cursor location to drive hover expansion. Use a
        // non-scheduled Timer added to .common run-loop mode so it fires
        // even while AppKit is in event-tracking modes.
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    private func updateHover() {
        guard let panel, panel.isVisible else {
            if hoverState.hovering { hoverState.hovering = false }
            return
        }
        let p = NSEvent.mouseLocation  // screen coords, bottom-left origin
        if hoverState.hovering {
            // Stay expanded as long as cursor is inside the expanded rect.
            if !expandedScreenRect.contains(p) { hoverState.hovering = false }
        } else {
            // Trigger expansion only when cursor enters the small collapsed pill.
            if collapsedScreenRect.contains(p) { hoverState.hovering = true }
        }
    }

    func applyVisibility() {
        guard let panel else { return }
        let now = Int(Date().timeIntervalSince1970)
        let newestEventTs = max(claudeStatus.lastEventTs, codexStatus.lastEventTs)
        let age = now - newestEventTs
        let shouldShow = newestEventTs > 0 && TimeInterval(age) < idleHideAfterSeconds
        if shouldShow {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            if panel.isVisible { panel.orderOut(nil) }
        }
    }

    func rebuild() {
        panel?.orderOut(nil)
        panel = nil
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let physical = screen.resolvedNotchSize

        // Collapsed pill is just crab + dot, so a small extension is enough
        // to keep the bottom curves visible past the camera housing.
        let widthExtension: CGFloat = 60
        let collapsedSize = CGSize(
            width: physical.width + widthExtension,
            height: physical.height
        )
        // Expanded pill: wider for the weekly bar + labels, taller for the detail block.
        let expandedSize = CGSize(
            width:  max(360, collapsedSize.width + 60),
            height: collapsedSize.height + 180
        )

        let frame = NSRect(
            x: screenFrame.midX - expandedSize.width / 2,
            y: screenFrame.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )

        let p = NotchPanel(contentRect: frame, styleMask: [], backing: .buffered, defer: false)
        hoverState.hovering = false
        let host = NSHostingView(rootView: NotchContentView(
            claudeStatus: claudeStatus,
            claudeUsage: claudeUsage,
            codexStatus: codexStatus,
            codexUsage: codexUsage,
            collapsedSize: collapsedSize,
            expandedSize: expandedSize,
            hoverState: hoverState
        ))
        host.frame = NSRect(origin: .zero, size: expandedSize)
        p.contentView = host
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        panel = p

        // Pill rects in screen coords (bottom-left origin) for hover hit-testing.
        collapsedScreenRect = CGRect(
            x: screenFrame.midX - collapsedSize.width / 2,
            y: screenFrame.maxY - collapsedSize.height,
            width: collapsedSize.width,
            height: collapsedSize.height
        )
        expandedScreenRect = CGRect(
            x: screenFrame.midX - expandedSize.width / 2,
            y: screenFrame.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }
}

@MainActor
func bootstrap() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    objc_setAssociatedObject(app, "delegate-retain", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.accessory)
    app.run()
}

DispatchQueue.main.async { bootstrap() }
dispatchMain()
