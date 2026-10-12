import AppKit

// Bus Stop uses a plain AppKit lifecycle: an NSStatusItem with an NSPopover
// and NSWindow-hosted SwiftUI views (see docs/SPEC.md §9, "MenuBarExtra or
// NSStatusItem?"). There is no SwiftUI `App` struct.

let application = NSApplication.shared
/// Held for the life of the process; `NSApplication.delegate` is weak.
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
