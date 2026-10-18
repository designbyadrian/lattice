import AppKit
import LayoutEngine
import LayoutModel

/// Non-activating overview UI with system materials (PLAN §6 / §7).
@MainActor
public final class OverviewPanelController {
    public private(set) var panel: NSPanel?
    public private(set) var isVisible: Bool = false

    public var onActivateTile: ((NodePath) -> Void)?
    public var onDismiss: (() -> Void)?

    private var contentView: OverviewContentView?

    public init() {}

    public func show(
        displayFrame: CGRect,
        tiles: [OverviewTileModel],
        material: NSVisualEffectView.Material = .hudWindow
    ) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(displayFrame, display: true)

        let content = contentView ?? OverviewContentView(frame: displayFrame)
        contentView = content
        content.tiles = tiles
        content.onActivate = { [weak self] path in
            self?.onActivateTile?(path)
        }
        content.applyMaterial(
            material,
            reduceTransparency: VisualAccessibility.reduceTransparency
        )
        panel.contentView = content
        panel.orderFrontRegardless()
        isVisible = true
    }

    public func updateTiles(_ tiles: [OverviewTileModel]) {
        contentView?.tiles = tiles
        contentView?.needsLayout = true
        contentView?.layoutSubtreeIfNeeded()
    }

    public func hide() {
        panel?.orderOut(nil)
        isVisible = false
        onDismiss?()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }
}

/// Model for one overview tile (collapsed or expanded preview host).
public struct OverviewTileModel: Sendable, Equatable {
    public var path: NodePath
    public var frame: CGRect
    public var presentation: CollapsePresentation
    public var bundleID: String?
    public var title: String
    public var windowID: UInt32?

    public init(
        path: NodePath,
        frame: CGRect,
        presentation: CollapsePresentation,
        bundleID: String? = nil,
        title: String = "",
        windowID: UInt32? = nil
    ) {
        self.path = path
        self.frame = frame
        self.presentation = presentation
        self.bundleID = bundleID
        self.title = title
        self.windowID = windowID
    }
}

@MainActor
final class OverviewContentView: NSView {
    var tiles: [OverviewTileModel] = [] {
        didSet { rebuild() }
    }

    var onActivate: ((NodePath) -> Void)?

    private let effectView = NSVisualEffectView()
    private var tileViews: [OverviewTileView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.material = .hudWindow
        addSubview(effectView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func applyMaterial(_ material: NSVisualEffectView.Material, reduceTransparency: Bool) {
        VisualAccessibility.applyMaterial(
            material,
            to: effectView,
            fallbackLayer: layer
        )
        if reduceTransparency {
            effectView.isHidden = true
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        if VisualAccessibility.increaseContrast {
            wantsLayer = true
            layer?.borderWidth = VisualAccessibility.outlineWidth(base: 1)
            layer?.borderColor = NSColor.labelColor.cgColor
        }
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        for (view, model) in zip(tileViews, tiles) {
            view.frame = model.frame
        }
    }

    private func rebuild() {
        tileViews.forEach { $0.removeFromSuperview() }
        tileViews = tiles.map { model in
            let view = OverviewTileView(frame: model.frame)
            view.presentation = model.presentation
            view.showsSplitLines = model.presentation == .groupTile
            view.appColor = color(for: model.bundleID)
            view.icon = icon(for: model.bundleID)
            let click = NSClickGestureRecognizer(target: self, action: #selector(tileClicked(_:)))
            view.addGestureRecognizer(click)
            view.toolTip = model.title
            addSubview(view)
            return view
        }
        needsLayout = true
    }

    @objc private func tileClicked(_ recognizer: NSClickGestureRecognizer) {
        guard let view = recognizer.view as? OverviewTileView,
              let idx = tileViews.firstIndex(of: view),
              tiles.indices.contains(idx) else { return }
        onActivate?(tiles[idx].path)
    }

    private func color(for bundleID: String?) -> NSColor {
        guard let bundleID, !bundleID.isEmpty else {
            return NSColor.controlAccentColor
        }
        var hash: UInt64 = 5381
        for byte in bundleID.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hue = CGFloat(hash % 360) / 360
        return NSColor(calibratedHue: hue, saturation: 0.45, brightness: 0.55, alpha: 1)
    }

    private func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
