import AppKit

// Swift 6: main.swift top-level code is not @MainActor-isolated.
// AppDelegate is @MainActor, so we bridge via MainActor.assumeIsolated.
// main.swift always executes on the main thread, so this is safe.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
    app.run()
}
