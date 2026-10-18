import AppKit
import AppCore
import Config

/// Manages separate status items for menu-bar controls + the Lattice icon (B13).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var latticeItem: NSStatusItem?
    private var controlItems: [NSStatusItem] = []
    private var model = MenuModel(controls: [], items: [])
    private var actionHandler: ((MenuAction) -> Void)?

    func install(onAction: @escaping (MenuAction) -> Void) {
        actionHandler = onAction
        if latticeItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = NSImage(
                    systemSymbolName: "rectangle.split.3x1",
                    accessibilityDescription: "Lattice"
                )
                button.image?.isTemplate = true
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.target = self
                button.action = #selector(latticeClicked(_:))
            }
            latticeItem = item
        }
    }

    func update(model: MenuModel) {
        self.model = model
        rebuildControls()
        latticeItem?.menu = buildNSMenu(from: model.items)
    }

    func latticeButtonFrame() -> NSRect? {
        latticeItem?.button?.window?.frame
    }

    // MARK: - Controls

    private func rebuildControls() {
        for item in controlItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        controlItems.removeAll()

        // Status items appear right-to-left; create in reverse so final left→right matches config.
        for control in model.controls.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            configure(button: item.button, control: control)
            controlItems.append(item)
        }
        controlItems.reverse()
    }

    private func configure(button: NSStatusBarButton?, control: MenuBarControlItem) {
        guard let button else { return }
        button.target = self
        button.action = #selector(controlClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.identifier = NSUserInterfaceItemIdentifier(controlID(control))
        button.isEnabled = control.enabled
        button.toolTip = control.accessibilityLabel
        button.setAccessibilityLabel(control.accessibilityLabel)

        switch control.control {
        case .back:
            button.image = symbol(control.isOn ? "chevron.backward.circle.fill" : "chevron.backward.circle")
            button.title = ""
        case .forward:
            button.image = symbol(control.isOn ? "chevron.forward.circle.fill" : "chevron.forward.circle")
            button.title = ""
        case .views:
            button.image = nil
            button.title = "\(control.viewIndex ?? 0)"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: control.isOn ? .bold : .regular)
            button.appearsDisabled = false
            if control.isOn {
                button.contentTintColor = NSColor.controlAccentColor
            } else {
                button.contentTintColor = nil
            }
        case .desktop:
            button.image = symbol(control.isOn ? "menubar.dock.rectangle" : "menubar.rectangle")
            button.title = ""
        case .everything:
            button.image = symbol(control.isOn ? "rectangle.3.group.fill" : "rectangle.3.group")
            button.title = ""
        }
        button.image?.isTemplate = true
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func controlID(_ control: MenuBarControlItem) -> String {
        if let index = control.viewIndex {
            return "views.\(index)"
        }
        return control.control.rawValue
    }

    @objc private func controlClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showLatticeMenu(relativeTo: sender)
            return
        }
        guard let id = sender.identifier?.rawValue else { return }
        if let match = model.controls.first(where: { controlID($0) == id }) {
            actionHandler?(match.action)
        }
    }

    @objc private func latticeClicked(_ sender: NSStatusBarButton) {
        showLatticeMenu(relativeTo: sender)
    }

    private func showLatticeMenu(relativeTo button: NSStatusBarButton) {
        let menu = buildNSMenu(from: model.items)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    // MARK: - NSMenu

    private func buildNSMenu(from items: [MenuModelItem]) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        for item in items {
            menu.addItem(nsItem(from: item))
        }
        return menu
    }

    private func nsItem(from item: MenuModelItem) -> NSMenuItem {
        switch item.kind {
        case .separator:
            return .separator()
        case .notice:
            let ni = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            ni.isEnabled = false
            return ni
        case .submenu(let children):
            let ni = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: item.title)
            for child in children {
                sub.addItem(nsItem(from: child))
            }
            ni.submenu = sub
            return ni
        case .action:
            let key = keyEquivalent(from: item.keyEquivalentHint)
            let ni = NSMenuItem(title: item.title, action: #selector(menuAction(_:)), keyEquivalent: key.char)
            ni.keyEquivalentModifierMask = key.mask
            ni.target = self
            ni.isEnabled = item.enabled
            ni.state = item.checked ? .on : .off
            if let action = item.action {
                ni.representedObject = MenuActionBox(action)
            }
            return ni
        }
    }

    private func keyEquivalent(from hint: String?) -> (char: String, mask: NSEvent.ModifierFlags) {
        guard let hint, let chord = try? KeyChord.parse(hint) else {
            return ("", [])
        }
        var mask: NSEvent.ModifierFlags = []
        if chord.modifiers.control { mask.insert(.control) }
        if chord.modifiers.option { mask.insert(.option) }
        if chord.modifiers.shift { mask.insert(.shift) }
        if chord.modifiers.command { mask.insert(.command) }
        let char: String
        switch chord.key {
        case "left-bracket": char = "["
        case "right-bracket": char = "]"
        case "enter", "return": char = "\r"
        case "space": char = " "
        case "escape", "esc": char = "\u{1b}"
        default:
            char = chord.key.count == 1 ? chord.key : ""
        }
        return (char, mask)
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? MenuActionBox else { return }
        actionHandler?(box.action)
    }
}

private final class MenuActionBox: NSObject {
    let action: MenuAction
    init(_ action: MenuAction) { self.action = action }
}
