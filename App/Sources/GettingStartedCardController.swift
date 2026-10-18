import AppKit
import AppCore

/// Floating card under the menu-bar icon (ADDENDUM-2 B18).
@MainActor
final class GettingStartedCardController: NSWindowController {
    private var model: GettingStartedModel
    private var titleLabel: NSTextField!
    private var bodyLabel: NSTextField!
    private var onSkip: (() -> Void)?
    private var onChanged: ((GettingStartedModel) -> Void)?

    init(
        model: GettingStartedModel = GettingStartedDefaults.load(),
        onSkip: (() -> Void)? = nil,
        onChanged: ((GettingStartedModel) -> Void)? = nil
    ) {
        self.model = model
        self.onSkip = onSkip
        self.onChanged = onChanged
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.title = "Getting started"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var currentModel: GettingStartedModel { model }

    func showAnchored(under frame: NSRect?) {
        guard model.isVisible else {
            window?.orderOut(nil)
            return
        }
        if let frame {
            let x = frame.midX - 160
            let y = frame.minY - 150
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window?.center()
        }
        showWindow(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    @discardableResult
    func handle(_ event: GettingStartedEvent) -> Bool {
        let advanced = model.handle(event)
        if advanced {
            GettingStartedDefaults.save(model)
            onChanged?(model)
            render()
            if !model.isVisible { hide() }
        }
        return advanced
    }

    func skip() {
        model.skip()
        GettingStartedDefaults.save(model)
        onChanged?(model)
        hide()
        onSkip?()
    }

    func restart() {
        model.restart()
        GettingStartedDefaults.save(model)
        onChanged?(model)
        render()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel = NSTextField(wrappingLabelWithString: "")
        bodyLabel.font = NSFont.systemFont(ofSize: 12)
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        let skip = NSButton(title: "Skip", target: self, action: #selector(skipTapped))
        skip.bezelStyle = .recessed
        skip.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(titleLabel)
        content.addSubview(bodyLabel)
        content.addSubview(skip)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            skip.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            skip.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
    }

    private func render() {
        guard let step = model.current, model.isVisible else {
            hide()
            return
        }
        titleLabel.stringValue = step.title
        bodyLabel.stringValue = step.body
    }

    @objc private func skipTapped() { skip() }
}
