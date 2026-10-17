import AppKit
import Foundation
import PokemonAccessCore

/// Upstream's text and list dialogs (renaming an object or a map, hack ROM
/// setup) as standard alerts VoiceOver reads. The Lua side keeps the game
/// running while it waits for the REPLY.
@MainActor
final class PromptPresenter {
    nonisolated(unsafe) private let log: FileLog
    private var listSources: [ChoiceListSource] = []

    nonisolated init(log: FileLog) {
        self.log = log
    }

    func text(id: Int, title: String, caption: String, defaultValue: String, reply: @escaping (HelperMessage) -> Void) {
        let alert = makeAlert(title: title, caption: caption)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultValue
        field.setAccessibilityLabel("Name")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let ok = present(alert)
        reply(.reply(id: id, ok: ok, values: ok ? [field.stringValue] : []))
        log.info("text prompt \(id) \(ok ? "answered" : "cancelled")")
    }

    func choice(id: Int, title: String, caption: String, multi: Bool, defaults: [Int], items: [String],
                reply: @escaping (HelperMessage) -> Void) {
        let alert = makeAlert(title: title, caption: caption)
        let source = ChoiceListSource(items: items)
        listSources.append(source)
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.width = 300
        table.addTableColumn(column)
        table.headerView = nil
        table.allowsMultipleSelection = multi
        table.allowsEmptySelection = false
        table.dataSource = source
        table.delegate = source
        table.setAccessibilityLabel("Choices")
        table.reloadData()
        let rows = IndexSet(defaults.map { $0 - 1 }.filter { (0..<items.count).contains($0) })
        table.selectRowIndexes(rows.isEmpty && !items.isEmpty ? IndexSet(integer: 0) : rows, byExtendingSelection: false)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = table
        let ok = present(alert)
        let values = ok ? table.selectedRowIndexes.map { String($0 + 1) } : []
        reply(.reply(id: id, ok: ok, values: values))
        log.info("choice prompt \(id) \(ok ? "answered \(values)" : "cancelled")")
        listSources.removeAll { $0 === source }
    }

    private func makeAlert(title: String, caption: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = caption
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    /// Runs the alert and hands focus back to mGBA afterwards.
    private func present(_ alert: NSAlert) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let ok = alert.runModal() == .alertFirstButtonReturn
        NSRunningApplication.runningApplications(withBundleIdentifier: MgbaInstallation.bundleIdentifier).first?.activate()
        return ok
    }
}

final class ChoiceListSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let items: [String]

    init(items: [String]) {
        self.items = items
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        items[row]
    }
}
