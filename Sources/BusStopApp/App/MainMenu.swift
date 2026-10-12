import AppKit

/// The app's main menu.
///
/// Bus Stop is a menu bar accessory most of the time, so the menu bar itself
/// shows only while a window is open with a Dock icon. The menu still matters:
/// its key equivalents (⌘, ⌘R ⌘1 ⌘W, and the Edit commands that text fields
/// need) work in the popover and in every window.
enum MainMenu {
    static let projectURL = URL(string: "https://github.com/static74/BusStop")!

    /// Builds the menu. App-specific items target `delegate`.
    static func make(delegate: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu(title: "Main Menu")
        mainMenu.addItem(submenuItem(appMenu(delegate: delegate)))
        mainMenu.addItem(submenuItem(editMenu()))
        mainMenu.addItem(submenuItem(viewMenu(delegate: delegate)))

        let window = windowMenu()
        mainMenu.addItem(submenuItem(window))
        NSApp.windowsMenu = window

        let help = helpMenu(delegate: delegate)
        mainMenu.addItem(submenuItem(help))
        NSApp.helpMenu = help
        return mainMenu
    }

    private static func appMenu(delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Bus Stop")
        menu.addItem(item("About Bus Stop", #selector(AppDelegate.openAbout(_:)), target: delegate))
        menu.addItem(.separator())
        menu.addItem(item("Settings\u{2026}", #selector(AppDelegate.openSettings(_:)), key: ",", target: delegate))
        menu.addItem(.separator())
        menu.addItem(item("Hide Bus Stop", #selector(NSApplication.hide(_:)), key: "h"))
        let hideOthers = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Bus Stop", #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), key: "z"))
        let redo = item("Redo", Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private static func viewMenu(delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Refresh", #selector(AppDelegate.refreshPorts(_:)), key: "r", target: delegate))
        menu.addItem(item("Show Topology", #selector(AppDelegate.openTopology(_:)), key: "1", target: delegate))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), key: "w"))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func helpMenu(delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Bus Stop on GitHub", #selector(AppDelegate.openProjectPage(_:)), target: delegate))
        return menu
    }

    // MARK: Helpers

    private static func submenuItem(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// A menu item. Without a target it goes to the first responder.
    private static func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
