import AppKit
import ApplicationServices
import Foundation
import PokemonAccessCore

/// Loads the entry script into a running mGBA 0.10.5 through the Accessibility
/// API, the sequence verified in Phase 1: Tools > Scripting..., set the prompt
/// field's value to a dofile() line, press Run, close the Scripting window.
final class ScriptInjector {
    enum InjectionError: Error, CustomStringConvertible {
        case notTrusted
        case noWindow
        case noScriptingMenu
        case noScriptingWindow
        case noPromptOrRunButton
        case setValueFailed(AXError)

        var description: String {
            switch self {
            case .notTrusted: return "the Accessibility permission is missing"
            case .noWindow: return "mGBA showed no window"
            case .noScriptingMenu: return "the Tools > Scripting menu item was not found"
            case .noScriptingWindow: return "the Scripting window did not open"
            case .noPromptOrRunButton: return "the Scripting window's prompt or Run button was not found"
            case let .setValueFailed(error): return "setting the prompt text failed (AXError \(error.rawValue))"
            }
        }
    }

    private let pid: pid_t
    private let application: AXUIElement
    private let log: FileLog

    init(pid: pid_t, log: FileLog) {
        self.pid = pid
        self.log = log
        application = AXUIElementCreateApplication(pid)
    }

    func load(script: URL, timeout: TimeInterval) throws {
        guard AccessibilityPermission.isTrusted else { throw InjectionError.notTrusted }
        let deadline = Date().addingTimeInterval(timeout)

        try wait(until: deadline, orThrow: .noWindow) { !self.windows().isEmpty }
        log.info("mGBA window is up")

        if findWindow(titled: "Scripting") == nil {
            guard let menuItem = scriptingMenuItem() else { throw InjectionError.noScriptingMenu }
            AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
        }
        var scripting: AXUIElement?
        try wait(until: deadline, orThrow: .noScriptingWindow) {
            scripting = self.findWindow(titled: "Scripting")
            return scripting != nil
        }

        // Qt fills the window's accessibility tree a moment after it opens.
        var prompt: AXUIElement?
        var runButton: AXUIElement?
        try wait(until: deadline, orThrow: .noPromptOrRunButton) {
            (prompt, runButton) = self.promptAndRunButton(in: scripting!)
            return prompt != nil && runButton != nil
        }

        let snippet = InjectionSnippet.dofile(path: script.path)
        let result = AXUIElementSetAttributeValue(prompt!, kAXValueAttribute as CFString, snippet as CFTypeRef)
        guard result == .success else { throw InjectionError.setValueFailed(result) }
        Thread.sleep(forTimeInterval: 0.3)
        AXUIElementPerformAction(runButton!, kAXPressAction as CFString)
        log.info("script loaded through the Scripting window: \(snippet)")
        Thread.sleep(forTimeInterval: 0.5)

        if let closeButton = attribute(of: scripting!, kAXCloseButtonAttribute) as! AXUIElement? {
            AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        }
        if let main = windows().first(where: { title(of: $0) != "Scripting" }) {
            AXUIElementPerformAction(main, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    // MARK: Accessibility helpers

    private func wait(until deadline: Date, orThrow error: InjectionError, for condition: () -> Bool) throws {
        while !condition() {
            if Date() >= deadline { throw error }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private func attribute(of element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(of: element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func role(of element: AXUIElement) -> String? {
        attribute(of: element, kAXRoleAttribute) as? String
    }

    private func title(of element: AXUIElement) -> String? {
        attribute(of: element, kAXTitleAttribute) as? String
    }

    private func windows() -> [AXUIElement] {
        attribute(of: application, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    private func findWindow(titled wanted: String) -> AXUIElement? {
        windows().first { title(of: $0) == wanted }
    }

    private func scriptingMenuItem() -> AXUIElement? {
        guard let menuBar = attribute(of: application, kAXMenuBarAttribute) as! AXUIElement? else { return nil }
        guard let tools = children(of: menuBar).first(where: { title(of: $0) == "Tools" }) else { return nil }
        for menu in children(of: tools) {
            if let item = children(of: menu).first(where: { title(of: $0)?.hasPrefix("Scripting") == true }) {
                return item
            }
        }
        return nil
    }

    /// Depth-first search for the first text field and the button titled Run.
    private func promptAndRunButton(in window: AXUIElement) -> (AXUIElement?, AXUIElement?) {
        var prompt: AXUIElement?
        var runButton: AXUIElement?
        var stack = children(of: window)
        while let element = stack.popLast(), prompt == nil || runButton == nil {
            switch role(of: element) {
            case kAXTextFieldRole where prompt == nil:
                prompt = element
            case kAXButtonRole where runButton == nil && title(of: element) == "Run":
                runButton = element
            default:
                stack.append(contentsOf: children(of: element))
            }
        }
        return (prompt, runButton)
    }
}
