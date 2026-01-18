import Foundation
import AppKit
import VPACore

final class MenuBarController: NSObject, StateMachineObserver {
    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "VPA"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func stateDidChange(_ newState: AssistantState) {
        DispatchQueue.main.async {
            self.statusItem.button?.title = "VPA: \(self.label(for: newState))"
        }
    }

    private func label(for state: AssistantState) -> String {
        switch state {
        case .idle: return "Idle"
        case .listening: return "Listening"
        case .processing: return "Processing"
        case .speaking: return "Speaking"
        case .interrupted: return "Interrupted"
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
