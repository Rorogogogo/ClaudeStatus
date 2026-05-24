import AppKit

@MainActor
func bootstrap() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    objc_setAssociatedObject(app, "delegate-retain", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.setActivationPolicy(.accessory)
    app.run()
}

// Run bootstrap() directly on the main thread. NSApplication.run() then drives
// the main run loop, which services the main dispatch queue — so
// DispatchQueue.main.async blocks and main-queue DispatchSources fire normally.
//
// (The previous `DispatchQueue.main.async { bootstrap() } + dispatchMain()` wedged
// the main queue: dispatchMain drained the bootstrap block, app.run() never
// returned, and no further main-queue work — file-watch reloads, visibility
// updates — could ever run, freezing every status dot at its launch value.)
MainActor.assumeIsolated { bootstrap() }
