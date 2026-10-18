import AppKit
import AppCore
import Config
import LayoutModel
import Platform
import PlatformMac

/// Native toolbar-style Settings (ADDENDUM-2 B19).
@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let editor: ConfigFileEditor
    private var onReload: (() -> Void)?
    private var onRestartGettingStarted: (() -> Void)?
    private var onRestorePrefs: (() -> Void)?
    private var onOverridePrefs: (() -> Void)?
    private var systemPrefs: SystemPrefsBackup?
    private var permissions: MacPermissions

    private var tabView: NSTabView!
    private var errorBanner: NSTextField!
    private var openConfigButton: NSButton!

    // Pane controls (rebound on reload)
    private var startAtLoginButton: NSButton!
    private var gapsInnerField: NSTextField!
    private var durationField: NSTextField!
    private var pinchPopup: NSPopUpButton!
    private var framePopup: NSPopUpButton!
    private var bordersEnabled: NSButton!
    private var menuBarChecks: [MenuBarControl: NSButton] = [:]
    private var menuBarOrderField: NSTextField!
    private var workspacesField: NSTextField!
    private var shortcutsStack: NSStackView!
    private var rulesStack: NSStackView!

    init(
        configURL: URL,
        systemPrefs: SystemPrefsBackup? = nil,
        permissions: MacPermissions = MacPermissions(),
        onReload: (() -> Void)? = nil,
        onRestartGettingStarted: (() -> Void)? = nil,
        onOverridePrefs: (() -> Void)? = nil,
        onRestorePrefs: (() -> Void)? = nil
    ) {
        self.editor = ConfigFileEditor(fileURL: configURL)
        self.systemPrefs = systemPrefs
        self.permissions = permissions
        self.onReload = onReload
        self.onRestartGettingStarted = onRestartGettingStarted
        self.onOverridePrefs = onOverridePrefs
        self.onRestorePrefs = onRestorePrefs

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lattice Settings"
        window.center()
        super.init(window: window)
        buildUI()
        installToolbar()
        refreshFromEditor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reloadFromDisk() {
        editor.reloadFromDisk()
        refreshFromEditor()
    }

    // MARK: - UI shell

    private func buildUI() {
        guard let content = window?.contentView else { return }

        errorBanner = NSTextField(wrappingLabelWithString: "")
        errorBanner.textColor = .systemRed
        errorBanner.isHidden = true
        errorBanner.translatesAutoresizingMaskIntoConstraints = false

        openConfigButton = NSButton(title: "Open config", target: self, action: #selector(openConfig))
        openConfigButton.translatesAutoresizingMaskIntoConstraints = false
        openConfigButton.isHidden = true

        tabView = NSTabView(frame: .zero)
        tabView.tabViewType = .noTabsNoBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false

        tabView.addTabViewItem(tab("General", view: makeGeneralPane()))
        tabView.addTabViewItem(tab("Layout", view: makeLayoutPane()))
        tabView.addTabViewItem(tab("Mouse & Trackpad", view: makeMousePane()))
        tabView.addTabViewItem(tab("Menu Bar", view: makeMenuBarPane()))
        tabView.addTabViewItem(tab("Apps & Rules", view: makeRulesPane()))
        tabView.addTabViewItem(tab("Shortcuts", view: makeShortcutsPane()))
        tabView.addTabViewItem(tab("Workspaces", view: makeWorkspacesPane()))

        content.addSubview(errorBanner)
        content.addSubview(openConfigButton)
        content.addSubview(tabView)

        NSLayoutConstraint.activate([
            errorBanner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            errorBanner.trailingAnchor.constraint(equalTo: openConfigButton.leadingAnchor, constant: -8),
            errorBanner.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            openConfigButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            openConfigButton.centerYAnchor.constraint(equalTo: errorBanner.centerYAnchor),
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabView.topAnchor.constraint(equalTo: errorBanner.bottomAnchor, constant: 8),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    private func tab(_ title: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
        item.view = scroll
        return item
    }

    private func installToolbar() {
        let toolbar = NSToolbar(identifier: "LatticeSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier("General")
        window?.toolbar = toolbar
        window?.toolbarStyle = .preference
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabView.tabViewItems.compactMap { item -> NSToolbarItem.Identifier? in
            guard let id = item.identifier as? String else { return nil }
            return NSToolbarItem.Identifier(id)
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = itemIdentifier.rawValue
        item.paletteLabel = itemIdentifier.rawValue
        item.target = self
        item.action = #selector(selectTab(_:))
        item.image = NSImage(systemSymbolName: symbol(for: itemIdentifier.rawValue), accessibilityDescription: nil)
        return item
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        let id = sender.itemIdentifier.rawValue
        if let index = tabView.tabViewItems.firstIndex(where: { ($0.identifier as? String) == id }) {
            tabView.selectTabViewItem(at: index)
            window?.toolbar?.selectedItemIdentifier = sender.itemIdentifier
        }
    }

    private func symbol(for title: String) -> String {
        switch title {
        case "General": return "gearshape"
        case "Layout": return "rectangle.split.3x1"
        case "Mouse & Trackpad": return "computermouse"
        case "Menu Bar": return "menubar.rectangle"
        case "Apps & Rules": return "app.badge"
        case "Shortcuts": return "keyboard"
        case "Workspaces": return "square.grid.3x3"
        default: return "gearshape"
        }
    }

    // MARK: - Panes

    private func makeGeneralPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let ax = NSTextField(labelWithString: permissionsLabel())
        ax.tag = 1001
        stack.addArrangedSubview(ax)

        startAtLoginButton = NSButton(
            checkboxWithTitle: "Start at login",
            target: self,
            action: #selector(toggleStartAtLogin)
        )
        stack.addArrangedSubview(startAtLoginButton)

        let conflict = NSButton(
            title: "Turn off conflicting macOS features",
            target: self,
            action: #selector(overridePrefs)
        )
        let restore = NSButton(
            title: "Turn back on",
            target: self,
            action: #selector(restorePrefs)
        )
        let row = NSStackView(views: [conflict, restore])
        row.spacing = 8
        stack.addArrangedSubview(row)

        let restart = NSButton(
            title: "Restart getting started",
            target: self,
            action: #selector(restartGettingStarted)
        )
        stack.addArrangedSubview(restart)
        return stack
    }

    private func makeLayoutPane() -> NSView {
        let stack = formStack()
        gapsInnerField = labeledField("Gaps inner", in: stack)
        gapsInnerField.target = self
        gapsInnerField.action = #selector(commitGaps)
        durationField = labeledField("Animation duration (ms)", in: stack)
        durationField.target = self
        durationField.action = #selector(commitDuration)
        let note = NSTextField(wrappingLabelWithString: "Reduce Motion in System Settings forces animations off.")
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        return stack
    }

    private func makeMousePane() -> NSView {
        let stack = formStack()
        pinchPopup = labeledPopup("Pinch modifier", items: ["alt", "ctrl", "ctrl-alt", "cmd"], in: stack)
        pinchPopup.target = self
        pinchPopup.action = #selector(commitPinch)
        framePopup = labeledPopup("Frame modifier", items: ["cmd-shift", "alt", "ctrl-alt"], in: stack)
        framePopup.target = self
        framePopup.action = #selector(commitFrame)
        let ffm = NSTextField(wrappingLabelWithString: "Focus-follows-mouse and double-click actions are edited in the config file for now when advanced.")
        ffm.textColor = .secondaryLabelColor
        stack.addArrangedSubview(ffm)
        return stack
    }

    private func makeMenuBarPane() -> NSView {
        let stack = formStack()
        menuBarChecks = [:]
        for control in MenuBarControl.allCases {
            let button = NSButton(
                checkboxWithTitle: control.rawValue,
                target: self,
                action: #selector(commitMenuBar)
            )
            menuBarChecks[control] = button
            stack.addArrangedSubview(button)
        }
        menuBarOrderField = labeledField("Order (comma-separated)", in: stack)
        menuBarOrderField.placeholderString = "back, forward, views, desktop, everything"
        menuBarOrderField.target = self
        menuBarOrderField.action = #selector(commitMenuBarOrder)
        bordersEnabled = NSButton(
            checkboxWithTitle: "Borders enabled",
            target: self,
            action: #selector(commitBorders)
        )
        stack.addArrangedSubview(bordersEnabled)
        return stack
    }

    private func makeRulesPane() -> NSView {
        let stack = formStack()
        rulesStack = NSStackView()
        rulesStack.orientation = .vertical
        rulesStack.alignment = .leading
        rulesStack.spacing = 4
        stack.addArrangedSubview(rulesStack)
        let leave = NSButton(
            title: "Leave frontmost app alone",
            target: self,
            action: #selector(leaveFrontmostAlone)
        )
        stack.addArrangedSubview(leave)
        return stack
    }

    private func makeShortcutsPane() -> NSView {
        let stack = formStack()
        shortcutsStack = NSStackView()
        shortcutsStack.orientation = .vertical
        shortcutsStack.alignment = .leading
        shortcutsStack.spacing = 8
        stack.addArrangedSubview(shortcutsStack)
        let restore = NSButton(
            title: "Restore default shortcuts",
            target: self,
            action: #selector(restoreDefaultShortcuts)
        )
        stack.addArrangedSubview(restore)
        return stack
    }

    private func makeWorkspacesPane() -> NSView {
        let stack = formStack()
        workspacesField = labeledField("Workspaces", in: stack)
        workspacesField.target = self
        workspacesField.action = #selector(commitWorkspaces)
        let note = NSTextField(wrappingLabelWithString: "[workspace-to-display] patterns: edit in config for multi-display routing.")
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        return stack
    }

    private func formStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        return stack
    }

    private func labeledField(_ title: String, in stack: NSStackView) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        let field = NSTextField(string: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let row = NSStackView(views: [label, field])
        row.spacing = 8
        stack.addArrangedSubview(row)
        return field
    }

    private func labeledPopup(_ title: String, items: [String], in stack: NSStackView) -> NSPopUpButton {
        let label = NSTextField(labelWithString: title)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: items)
        let row = NSStackView(views: [label, popup])
        row.spacing = 8
        stack.addArrangedSubview(row)
        return popup
    }

    // MARK: - Bind / save

    private func refreshFromEditor() {
        if let err = editor.loadError {
            errorBanner.stringValue = "Config invalid: \(err.description)"
            errorBanner.isHidden = false
            openConfigButton.isHidden = false
            setPanesEnabled(false)
        } else {
            errorBanner.isHidden = true
            openConfigButton.isHidden = true
            setPanesEnabled(true)
        }
        guard let config = editor.config ?? (try? ConfigParser.parse(text: editor.text)) else { return }
        startAtLoginButton?.state = config.startAtLogin ? .on : .off
        gapsInnerField?.stringValue = String(Int(config.gaps.inner.asUniform))
        durationField?.stringValue = String(config.animations.durationMs)
        workspacesField?.stringValue = String(config.workspaces)
        bordersEnabled?.state = config.borders.enabled ? .on : .off
        select(popup: pinchPopup, title: config.modifiers.pinchModifier.description)
        select(popup: framePopup, title: config.modifiers.frameModifier.description)
        let order = config.menuBarControls
        for (control, button) in menuBarChecks {
            button.state = order.contains(control) ? .on : .off
        }
        menuBarOrderField?.stringValue = order.map(\.rawValue).joined(separator: ", ")
        rebuildRules(config)
        rebuildShortcuts(config)
        if let ax = window?.contentView?.viewWithTag(1001) as? NSTextField {
            ax.stringValue = permissionsLabel()
        }
    }

    private func select(popup: NSPopUpButton?, title: String) {
        guard let popup else { return }
        if popup.itemTitles.contains(title) {
            popup.selectItem(withTitle: title)
        }
    }

    private func setPanesEnabled(_ enabled: Bool) {
        tabView?.isHidden = false
        for view in [startAtLoginButton, gapsInnerField, durationField, pinchPopup, framePopup,
                     bordersEnabled, menuBarOrderField, workspacesField] as [NSView?] {
            (view as? NSControl)?.isEnabled = enabled
        }
        for button in menuBarChecks.values { button.isEnabled = enabled }
    }

    private func rebuildRules(_ config: LatticeConfig) {
        rulesStack?.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, rule) in config.rules.enumerated() {
            let label = rule.appId ?? rule.appName ?? rule.title ?? "rule \(i)"
            let run = rule.run.joined(separator: ", ")
            rulesStack?.addArrangedSubview(NSTextField(labelWithString: "\(label) → \(run)"))
        }
        if config.rules.isEmpty {
            rulesStack?.addArrangedSubview(NSTextField(labelWithString: "(no rules)"))
        }
    }

    private func rebuildShortcuts(_ config: LatticeConfig) {
        shortcutsStack?.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let mode = config.mode() else { return }
        // Show a representative subset + recorder for one binding.
        for binding in mode.bindings.prefix(12) {
            let chordLabel = NSTextField(labelWithString: binding.chord.description)
            chordLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let cmd = binding.commands.map { String(describing: $0) }.joined(separator: "; ")
            let cmdLabel = NSTextField(labelWithString: cmd)
            cmdLabel.textColor = .secondaryLabelColor
            let row = NSStackView(views: [chordLabel, cmdLabel])
            row.spacing = 12
            shortcutsStack?.addArrangedSubview(row)
        }
        let recorder = ShortcutRecorderView(frame: .zero)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 280).isActive = true
        recorder.onChange = { [weak self] chord in
            guard let self, let chord else { return }
            let conflicts = ShortcutConflictDetector.conflicts(in: mode, candidate: chord)
            recorder.conflictText = conflicts.first?.reason
            guard conflicts.isEmpty else { return }
            // Write binding for zoom all as a demo path; full list editing uses Open config.
            try? self.editor.set(
                table: "mode.main",
                key: chord.description,
                value: .string("zoom all")
            )
            self.onReload?()
            self.reloadFromDisk()
        }
        shortcutsStack?.addArrangedSubview(NSTextField(labelWithString: "Record a chord (writes zoom all):"))
        shortcutsStack?.addArrangedSubview(recorder)
    }

    private func permissionsLabel() -> String {
        let ax = permissions.isAccessibilityTrusted ? "granted" : "needed"
        let scr = permissions.hasScreenRecordingAccess ? "granted" : "optional"
        return "Accessibility: \(ax) · Screen Recording: \(scr)"
    }

    private func apply(_ mutate: () throws -> Void) {
        do {
            try mutate()
            onReload?()
            refreshFromEditor()
        } catch {
            errorBanner.stringValue = "\(error)"
            errorBanner.isHidden = false
        }
    }

    // MARK: - Actions

    @objc private func openConfig() { NSWorkspace.shared.open(editor.fileURL) }

    @objc private func toggleStartAtLogin() {
        apply {
            try editor.set(
                table: nil,
                key: "start-at-login",
                value: .bool(startAtLoginButton.state == .on)
            )
        }
    }

    @objc private func commitGaps() {
        apply {
            let n = Int(gapsInnerField.stringValue) ?? 10
            try editor.set(table: "gaps", key: "inner", value: .int(n))
        }
    }

    @objc private func commitDuration() {
        apply {
            let n = Int(durationField.stringValue) ?? 450
            try editor.set(table: "animations", key: "duration-ms", value: .int(n))
        }
    }

    @objc private func commitPinch() {
        apply {
            let title = pinchPopup.titleOfSelectedItem ?? "alt"
            try editor.set(table: "modifiers", key: "pinch-modifier", value: .string(title))
        }
    }

    @objc private func commitFrame() {
        apply {
            let title = framePopup.titleOfSelectedItem ?? "cmd-shift"
            try editor.set(table: "modifiers", key: "frame-modifier", value: .string(title))
        }
    }

    @objc private func commitBorders() {
        apply {
            try editor.set(table: "borders", key: "enabled", value: .bool(bordersEnabled.state == .on))
        }
    }

    @objc private func commitMenuBar() {
        apply {
            var selected: [String] = []
            for control in MenuBarControl.allCases {
                if menuBarChecks[control]?.state == .on {
                    selected.append(control.rawValue)
                }
            }
            try editor.set(table: nil, key: "menu-bar-controls", value: .stringArray(selected))
        }
    }

    @objc private func commitMenuBarOrder() {
        apply {
            let parts = menuBarOrderField.stringValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            try editor.set(table: nil, key: "menu-bar-controls", value: .stringArray(parts))
        }
    }

    @objc private func commitWorkspaces() {
        apply {
            let n = Int(workspacesField.stringValue) ?? 1
            try editor.set(table: nil, key: "workspaces", value: .int(max(1, n)))
        }
    }

    @objc private func leaveFrontmostAlone() {
        apply {
            let app = NSWorkspace.shared.frontmostApplication
            try editor.appendIgnoreRule(
                appId: app?.bundleIdentifier,
                appName: app?.localizedName
            )
        }
    }

    @objc private func restoreDefaultShortcuts() {
        apply {
            // Rewrite each B11 binding key into [mode.main].
            let mode = DefaultBindings.mainMode()
            for binding in mode.bindings {
                let cmd: String
                if let first = binding.commands.first {
                    cmd = commandLiteral(first)
                } else {
                    continue
                }
                try editor.set(table: "mode.main", key: binding.chord.description, value: .string(cmd))
            }
        }
    }

    @objc private func restartGettingStarted() { onRestartGettingStarted?() }
    @objc private func overridePrefs() { onOverridePrefs?() }
    @objc private func restorePrefs() { onRestorePrefs?() }

    private func commandLiteral(_ command: Command) -> String {
        // Minimal reverse for defaults restore.
        switch command {
        case .zoom(.all, false): return "zoom all"
        case .zoom(.out, false): return "zoom out"
        case .zoom(.in, false): return "zoom in"
        case .zoom(.window, true): return "zoom window --toggle"
        case .zoom(.desktop, false): return "zoom desktop"
        case .pan(.left): return "pan left"
        case .pan(.right): return "pan right"
        case .pan(.up): return "pan up"
        case .pan(.down): return "pan down"
        case .history(.back): return "history back"
        case .history(.forward): return "history forward"
        case .desktopArea(.toggle): return "desktop-area toggle"
        case .splitNew(let id): return "split-new \(id)"
        case .storeView(let n): return "store-view \(n)"
        case .recallView(let n): return "recall-view \(n)"
        case .workspace(.number(let n)): return "workspace \(n)"
        case .moveWindowToWorkspace(.number(let n), _): return "move-window-to-workspace \(n)"
        default: return "zoom all"
        }
    }
}

private extension ModifierSet {
    var description: String {
        var parts: [String] = []
        if control { parts.append("ctrl") }
        if option { parts.append("alt") }
        if command { parts.append("cmd") }
        if shift { parts.append("shift") }
        return parts.joined(separator: "-")
    }
}
