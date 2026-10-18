import AppKit
import Config

/// Settings: config viewer, Open config, Append rule for frontmost app.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let configURL: URL
    private var textView: NSTextView!
    private var appendHandler: (() -> Void)?
    private var reloadHandler: (() -> Void)?

    convenience init(
        configURL: URL,
        onAppendRule: @escaping () -> Void,
        onReload: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lattice Settings"
        window.center()
        self.init(window: window)
        self.configURL = configURL
        self.appendHandler = onAppendRule
        self.reloadHandler = onReload
        buildUI()
        reloadText()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let tv = NSTextView(frame: .zero)
        tv.isEditable = false
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        textView = tv

        let openButton = NSButton(title: "Open config", target: self, action: #selector(openConfig))
        let appendButton = NSButton(
            title: "Append rule for frontmost app",
            target: self,
            action: #selector(appendRule)
        )
        let reloadButton = NSButton(title: "Reload", target: self, action: #selector(reloadText))

        let buttons = NSStackView(views: [openButton, appendButton, reloadButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let note = NSTextField(wrappingLabelWithString:
            "Lattice extension: [experimental] ax-window-id and multitouch are off by default; unavailable private APIs auto-disable."
        )
        note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scroll)
        content.addSubview(buttons)
        content.addSubview(note)

        NSLayoutConstraint.activate([
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            buttons.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),

            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: note.topAnchor, constant: -8),

            note.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            note.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            note.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    @objc func reloadText() {
        if let text = try? String(contentsOf: configURL, encoding: .utf8) {
            textView.string = text
        } else {
            textView.string = "(config not found at \(configURL.path))"
        }
        reloadHandler?()
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(configURL)
    }

    @objc private func appendRule() {
        appendHandler?()
        // Brief delay so file write lands, then refresh viewer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.reloadText()
        }
    }
}
