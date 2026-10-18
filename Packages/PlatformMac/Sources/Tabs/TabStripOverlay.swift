import AppKit
import AppCore
import LayoutModel

/// Native material tab strip over a tab group (PLAN P8).
@MainActor
public final class TabStripOverlay: NSObject {
    private var panels: [String: NSPanel] = [:]
    private var groupByKey: [String: TabGroupSnapshot] = [:]
    public var onSelect: ((TabGroupSnapshot, Int) -> Void)?

    public override init() {
        super.init()
    }

    public func update(groups: [TabGroupSnapshot]) {
        var keep = Set<String>()
        for group in groups where group.titles.count >= 2 {
            let key = "\(group.displayUUID)-\(group.path.map(String.init).joined(separator: "."))"
            keep.insert(key)
            groupByKey[key] = group
            let panel = panels[key] ?? makePanel()
            panels[key] = panel
            guard let frame = group.frame else {
                panel.orderOut(nil)
                continue
            }
            let height: CGFloat = 28
            let strip = NSRect(
                x: frame.x,
                y: frame.y + frame.height - height,
                width: max(frame.width, 80),
                height: height
            )
            panel.setFrame(strip, display: true)

            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 4
            stack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
            for (i, title) in group.titles.enumerated() {
                let button = NSButton(
                    title: title.isEmpty ? "Tab \(i + 1)" : title,
                    target: self,
                    action: #selector(tabClicked(_:))
                )
                button.bezelStyle = .flexiblePush
                button.isBordered = false
                button.tag = i
                button.identifier = NSUserInterfaceItemIdentifier(key)
                if i == group.selectedIndex {
                    button.contentTintColor = .controlAccentColor
                }
                stack.addArrangedSubview(button)
            }
            panel.contentView = stack
            panel.orderFrontRegardless()
        }
        for key in panels.keys where !keep.contains(key) {
            panels[key]?.orderOut(nil)
            panels[key] = nil
            groupByKey[key] = nil
        }
        panels = panels.filter { keep.contains($0.key) }
        groupByKey = groupByKey.filter { keep.contains($0.key) }
    }

    public func hideAll() {
        for p in panels.values { p.orderOut(nil) }
        panels.removeAll()
        groupByKey.removeAll()
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue,
              let snapshot = groupByKey[key] else { return }
        onSelect?(snapshot, sender.tag)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        return panel
    }
}
