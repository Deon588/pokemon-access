import AppKit

enum MainMenu {
    @MainActor
    static func build() -> NSMenu {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        menu.addItem(applicationItem)
        let applicationMenu = NSMenu(title: "Pokemon Access")
        applicationMenu.addItem(withTitle: "Quit Pokemon Access", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        return menu
    }
}
