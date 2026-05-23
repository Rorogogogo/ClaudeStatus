import AppKit
import Combine
import SwiftUI

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NotchPanel?
    let claudeStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.claude/state/status")
    let claudeUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.claude/state/usage")
    let codexStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.codex/notchy/status")
    let codexUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.codex/notchy/usage")
    let antigravityStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.gemini/notchy/status")
    let antigravityUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.gemini/notchy/usage")
    private var screenObserver: NSObjectProtocol?
    private var visibilityTimer: Timer?
    private var visibilityCancellables = Set<AnyCancellable>()

    // Hover detection is global so collapsed can stay click-through.
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

        antigravityStatus.objectWillChange.sink { [weak self] _ in
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
            if hoverState.hovering { setHovering(false) }
            return
        }
        let p = NSEvent.mouseLocation  // screen coords, bottom-left origin
        if hoverState.hovering {
            // Stay expanded as long as cursor is inside the expanded rect.
            if !expandedScreenRect.contains(p) { setHovering(false) }
        } else {
            // Trigger expansion only when cursor enters the small collapsed pill.
            if collapsedScreenRect.contains(p) { setHovering(true) }
        }
    }

    private func setHovering(_ hovering: Bool) {
        hoverState.hovering = hovering
        panel?.ignoresMouseEvents = !hovering
    }

    func applyVisibility() {
        guard let panel else { return }
        let now = Int(Date().timeIntervalSince1970)
        let newestEventTs = max(max(claudeStatus.lastEventTs, codexStatus.lastEventTs), antigravityStatus.lastEventTs)
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
            width:  max(390, collapsedSize.width + 90),
            height: collapsedSize.height + 252 + 52
        )

        let frame = NSRect(
            x: screenFrame.midX - expandedSize.width / 2,
            y: screenFrame.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )

        let p = NotchPanel(contentRect: frame, styleMask: [], backing: .buffered, defer: false)
        setHovering(false)
        let host = NSHostingView(rootView: NotchContentView(
            claudeStatus: claudeStatus,
            claudeUsage: claudeUsage,
            codexStatus: codexStatus,
            codexUsage: codexUsage,
            antigravityStatus: antigravityStatus,
            antigravityUsage: antigravityUsage,
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
