import AppKit
import Config
import Foundation
import LayoutEngine
import LayoutModel
import Platform

/// Bridges `OverviewPresenting` to the non-activating `OverviewPanelController`.
public final class MacOverviewPresenter: OverviewPresenting, @unchecked Sendable {
    public var configMode: OverviewPreviewsMode = .auto
    public var screenRecordingGranted: () -> Bool = { false }

    private let lock = NSLock()
    private var _visible = false
    /// Created on the main actor when first needed.
    private var panel: OverviewPanelController?
    private var previews: OverviewPreviewController?

    public init() {}

    public var isOverviewVisible: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _visible
    }

    public func presentOverview(
        displayFrame: CGRectCodable,
        tiles: [OverviewTileDescriptor],
        onActivatePath: @escaping @Sendable ([Int]) -> Void
    ) {
        let models = tiles.map { Self.model(from: $0) }
        let frame = CGRect(
            x: displayFrame.x,
            y: displayFrame.y,
            width: displayFrame.width,
            height: displayFrame.height
        )
        let windowIDs = tiles.compactMap(\.windowID)
        let mode = configMode
        let granted = screenRecordingGranted()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let panel = self.panel ?? OverviewPanelController()
            self.panel = panel
            let previews = self.previews ?? OverviewPreviewController()
            self.previews = previews

            panel.onActivateTile = { path in
                onActivatePath(path)
            }
            panel.show(displayFrame: frame, tiles: models)
            previews.start(
                config: mode,
                screenRecordingGranted: granted,
                windowIDs: windowIDs,
                onFrame: { _, _ in }
            )
            self.lock.lock()
            self._visible = true
            self.lock.unlock()
        }
    }

    public func updateOverviewTiles(_ tiles: [OverviewTileDescriptor]) {
        let models = tiles.map { Self.model(from: $0) }
        DispatchQueue.main.async { [weak self] in
            self?.panel?.updateTiles(models)
        }
    }

    public func dismissOverview() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.previews?.stop()
            self.panel?.hide()
            self.lock.lock()
            self._visible = false
            self.lock.unlock()
        }
    }

    private static func model(from d: OverviewTileDescriptor) -> OverviewTileModel {
        let presentation: CollapsePresentation
        switch d.presentation {
        case "windowTile": presentation = .windowTile
        case "groupTile": presentation = .groupTile
        default: presentation = .expanded
        }
        return OverviewTileModel(
            path: d.path,
            frame: CGRect(x: d.frame.x, y: d.frame.y, width: d.frame.width, height: d.frame.height),
            presentation: presentation,
            bundleID: d.bundleID,
            title: d.title,
            windowID: d.windowID
        )
    }
}
