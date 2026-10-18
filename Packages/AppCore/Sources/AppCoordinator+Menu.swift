import Foundation
import Config
import LayoutEngine
import LayoutModel
import Platform

extension AppCoordinator {
    /// Pure menu snapshot for the focused (or primary) display's active workspace.
    public func menuModelState(
        frontmostAppName: String? = nil,
        inputFeaturesDisabled: Bool = false,
        inputSafetyNetActive: Bool = false,
        inputSafetyNetNotice: String? = nil,
        displayNames: [String: String] = [:]
    ) -> MenuModelState {
        queue.sync {
            let displays = Array(displayLayouts.keys).sorted()
            let focusUUID = displays.first
            let uuid = focusUUID ?? ""
            let wsNum = activeWorkspaceNumber[uuid] ?? 1
            let layout = displayLayouts[uuid] ?? DisplayLayout(displayUUID: uuid)
            let workspace = layout.workspaces[wsNum] ?? .empty
            let key = "\(uuid)#\(wsNum)"
            let history = navigationHistories[key] ?? NavigationHistory(current: workspace.camera)

            var isDesktop = false
            var isEverything = workspace.camera == .home || workspace.camera == .showAll
            // Prefer solve-based framing when we have a display rect from last frames / default.
            if let rect = lastDisplayRect(for: uuid) {
                let engine = CameraEngine(
                    workspace: workspace,
                    displayRect: rect,
                    gaps: gaps
                )
                isDesktop = engine.framedNodeID() == "desktop"
                isEverything = (engine.camera == .home || engine.framedNodeID() == workspace.root.id)
                    && !isDesktop
            }

            var currentView: Int?
            for (index, cam) in layout.savedViews {
                if cam == workspace.camera {
                    currentView = index
                    break
                }
            }

            var activeByDisplay: [MenuDisplayWorkspace] = []
            for dUUID in displays {
                let name = displayNames[dUUID] ?? dUUID
                let n = activeWorkspaceNumber[dUUID] ?? 1
                activeByDisplay.append(MenuDisplayWorkspace(displayName: name, workspace: n))
            }
            if activeByDisplay.isEmpty {
                activeByDisplay = [MenuDisplayWorkspace(displayName: "Main", workspace: 1)]
            }

            return MenuModelState(
                canGoBack: history.canGoBack,
                canGoForward: history.canGoForward,
                occupiedViewSlots: Set(layout.savedViews.keys),
                currentViewSlot: currentView,
                isFramingDesktop: isDesktop,
                isFramingEverything: isEverything && !isDesktop,
                desktopAreaVisible: !workspace.desktopHidden,
                workspaceCount: config.workspaces,
                activeWorkspaceByDisplay: activeByDisplay,
                displayCount: max(displays.count, 1),
                spacesBackend: platform.spacesController.spacesBackend,
                spacesNotice: platform.spacesController.spacesMenuNotice,
                inputFeaturesDisabled: inputFeaturesDisabled,
                inputSafetyNetActive: inputSafetyNetActive,
                inputSafetyNetNotice: inputSafetyNetNotice,
                frontmostAppName: frontmostAppName,
                menuBarControls: config.menuBarControls,
                bindingHints: MenuBindingHints.from(mode: config.mode())
            )
        }
    }

    public func buildMenuModel(
        frontmostAppName: String? = nil,
        inputFeaturesDisabled: Bool = false,
        inputSafetyNetActive: Bool = false,
        inputSafetyNetNotice: String? = nil,
        displayNames: [String: String] = [:]
    ) -> MenuModel {
        MenuModel.build(from: menuModelState(
            frontmostAppName: frontmostAppName,
            inputFeaturesDisabled: inputFeaturesDisabled,
            inputSafetyNetActive: inputSafetyNetActive,
            inputSafetyNetNotice: inputSafetyNetNotice,
            displayNames: displayNames
        ))
    }

    private func lastDisplayRect(for uuid: String) -> Rect? {
        // Fallback unit screen when no display geometry is cached.
        _ = uuid
        return Rect(x: 0, y: 0, width: 1440, height: 900)
    }
}
