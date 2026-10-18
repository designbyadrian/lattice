import Foundation
import Config
import LayoutEngine
import LayoutModel
import Platform

/// Identifier for a menu / status-bar action (ADDENDUM A2 + B13).
public enum MenuAction: Sendable, Equatable, Hashable {
    case historyBack
    case historyForward
    case zoomDesktop
    case zoomEverything
    case recallView(Int)
    case storeView(Int)
    case desktopAreaToggle
    case dockAll
    case unmanageAll
    case leaveAppAlone
    case workspace(Int)
    case spacesDetails
    case toggleInputFeatures
    case openSettings
    case quit
}

/// One status-bar control button (separate from the Lattice icon).
public struct MenuBarControlItem: Sendable, Equatable {
    public var control: MenuBarControl
    /// Occupied view slot when `control == .views`.
    public var viewIndex: Int?
    public var enabled: Bool
    /// Native "on" / filled state for the current camera / view.
    public var isOn: Bool
    public var action: MenuAction
    public var accessibilityLabel: String

    public init(
        control: MenuBarControl,
        viewIndex: Int? = nil,
        enabled: Bool = true,
        isOn: Bool = false,
        action: MenuAction,
        accessibilityLabel: String
    ) {
        self.control = control
        self.viewIndex = viewIndex
        self.enabled = enabled
        self.isOn = isOn
        self.action = action
        self.accessibilityLabel = accessibilityLabel
    }
}

/// One row in the Lattice status-item menu.
public struct MenuModelItem: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case action
        case submenu([MenuModelItem])
        case separator
        case notice
    }

    public var title: String
    public var kind: Kind
    public var action: MenuAction?
    public var enabled: Bool
    public var checked: Bool
    /// Binding chord description when expressible (`ctrl-alt-1`), else nil.
    public var keyEquivalentHint: String?

    public init(
        title: String,
        kind: Kind = .action,
        action: MenuAction? = nil,
        enabled: Bool = true,
        checked: Bool = false,
        keyEquivalentHint: String? = nil
    ) {
        self.title = title
        self.kind = kind
        self.action = action
        self.enabled = enabled
        self.checked = checked
        self.keyEquivalentHint = keyEquivalentHint
    }
}

/// Active workspace on one display (for menu checkmarks / multi-display labels).
public struct MenuDisplayWorkspace: Sendable, Equatable {
    public var displayName: String
    public var workspace: Int

    public init(displayName: String, workspace: Int) {
        self.displayName = displayName
        self.workspace = workspace
    }
}

/// Pure snapshot of AppCore / platform state for menu construction.
public struct MenuModelState: Sendable, Equatable {
    public var canGoBack: Bool
    public var canGoForward: Bool
    /// Occupied saved-view slots (1…9).
    public var occupiedViewSlots: Set<Int>
    /// Slot whose saved camera equals the current camera (filled control).
    public var currentViewSlot: Int?
    public var isFramingDesktop: Bool
    public var isFramingEverything: Bool
    /// "Desktop in this workspace" checkmark (`desktopMemory == nil`).
    public var desktopAreaVisible: Bool
    public var workspaceCount: Int
    public var activeWorkspaceByDisplay: [MenuDisplayWorkspace]
    public var displayCount: Int
    public var spacesBackend: SpacesBackend
    public var spacesNotice: String?
    public var inputFeaturesDisabled: Bool
    public var inputSafetyNetActive: Bool
    public var inputSafetyNetNotice: String?
    public var frontmostAppName: String?
    public var menuBarControls: [MenuBarControl]
    /// Chord descriptions keyed by primary command for key equivalents.
    public var bindingHints: [MenuAction: String]

    public init(
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        occupiedViewSlots: Set<Int> = [],
        currentViewSlot: Int? = nil,
        isFramingDesktop: Bool = false,
        isFramingEverything: Bool = true,
        desktopAreaVisible: Bool = true,
        workspaceCount: Int = 1,
        activeWorkspaceByDisplay: [MenuDisplayWorkspace] = [MenuDisplayWorkspace(displayName: "Main", workspace: 1)],
        displayCount: Int = 1,
        spacesBackend: SpacesBackend = .native,
        spacesNotice: String? = nil,
        inputFeaturesDisabled: Bool = false,
        inputSafetyNetActive: Bool = false,
        inputSafetyNetNotice: String? = nil,
        frontmostAppName: String? = nil,
        menuBarControls: [MenuBarControl] = MenuBarControl.allCases,
        bindingHints: [MenuAction: String] = [:]
    ) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.occupiedViewSlots = occupiedViewSlots
        self.currentViewSlot = currentViewSlot
        self.isFramingDesktop = isFramingDesktop
        self.isFramingEverything = isFramingEverything
        self.desktopAreaVisible = desktopAreaVisible
        self.workspaceCount = workspaceCount
        self.activeWorkspaceByDisplay = activeWorkspaceByDisplay
        self.displayCount = displayCount
        self.spacesBackend = spacesBackend
        self.spacesNotice = spacesNotice
        self.inputFeaturesDisabled = inputFeaturesDisabled
        self.inputSafetyNetActive = inputSafetyNetActive
        self.inputSafetyNetNotice = inputSafetyNetNotice
        self.frontmostAppName = frontmostAppName
        self.menuBarControls = menuBarControls
        self.bindingHints = bindingHints
    }
}

/// Built menu-bar controls + Lattice menu (no AppKit).
public struct MenuModel: Sendable, Equatable {
    public var controls: [MenuBarControlItem]
    public var items: [MenuModelItem]

    public init(controls: [MenuBarControlItem], items: [MenuModelItem]) {
        self.controls = controls
        self.items = items
    }

    /// Build from pure state (ADDENDUM A2 tests + B13 menu layout).
    public static func build(from state: MenuModelState) -> MenuModel {
        MenuModel(
            controls: buildControls(from: state),
            items: buildItems(from: state)
        )
    }

    // MARK: - Controls

    private static func buildControls(from state: MenuModelState) -> [MenuBarControlItem] {
        var result: [MenuBarControlItem] = []
        for control in state.menuBarControls {
            switch control {
            case .back:
                result.append(MenuBarControlItem(
                    control: .back,
                    enabled: state.canGoBack,
                    isOn: false,
                    action: .historyBack,
                    accessibilityLabel: "Back"
                ))
            case .forward:
                result.append(MenuBarControlItem(
                    control: .forward,
                    enabled: state.canGoForward,
                    isOn: false,
                    action: .historyForward,
                    accessibilityLabel: "Forward"
                ))
            case .views:
                for index in (1...9) where state.occupiedViewSlots.contains(index) {
                    result.append(MenuBarControlItem(
                        control: .views,
                        viewIndex: index,
                        enabled: true,
                        isOn: state.currentViewSlot == index,
                        action: .recallView(index),
                        accessibilityLabel: "View \(index)"
                    ))
                }
            case .desktop:
                result.append(MenuBarControlItem(
                    control: .desktop,
                    enabled: true,
                    isOn: state.isFramingDesktop,
                    action: .zoomDesktop,
                    accessibilityLabel: "Desktop"
                ))
            case .everything:
                result.append(MenuBarControlItem(
                    control: .everything,
                    enabled: true,
                    isOn: state.isFramingEverything && !state.isFramingDesktop,
                    action: .zoomEverything,
                    accessibilityLabel: "Everything"
                ))
            }
        }
        return result
    }

    // MARK: - Menu items (B13; no Overview)

    private static func buildItems(from state: MenuModelState) -> [MenuModelItem] {
        var items: [MenuModelItem] = []

        items.append(savedViewsSubmenu(from: state))
        items.append(MenuModelItem(
            title: "Desktop in this workspace",
            action: .desktopAreaToggle,
            checked: state.desktopAreaVisible,
            keyEquivalentHint: state.bindingHints[.desktopAreaToggle]
        ))
        items.append(MenuModelItem(title: "Dock all windows", action: .dockAll))
        items.append(MenuModelItem(title: "Float every window", action: .unmanageAll))

        let appName = state.frontmostAppName ?? "frontmost app"
        items.append(MenuModelItem(
            title: "Leave \(appName) alone",
            action: .leaveAppAlone,
            enabled: state.frontmostAppName != nil
        ))

        items.append(MenuModelItem(title: "", kind: .separator))

        if state.spacesBackend == .currentSpaceOnly {
            let notice = state.spacesNotice ?? SpacesSafetyNetCopy.menuNotice
            items.append(MenuModelItem(title: notice, kind: .notice, enabled: false))
            items.append(MenuModelItem(
                title: SpacesSafetyNetCopy.menuDetailsStub,
                action: .spacesDetails,
                enabled: true
            ))
        } else {
            items.append(contentsOf: workspaceItems(from: state))
        }

        items.append(MenuModelItem(title: "", kind: .separator))

        if state.inputSafetyNetActive, let notice = state.inputSafetyNetNotice {
            items.append(MenuModelItem(title: notice, kind: .notice, enabled: false))
        }

        let inputTitle = state.inputFeaturesDisabled
            ? "Enable input features"
            : "Disable input features"
        items.append(MenuModelItem(
            title: inputTitle,
            action: .toggleInputFeatures,
            checked: state.inputFeaturesDisabled
        ))

        items.append(MenuModelItem(title: "", kind: .separator))
        items.append(MenuModelItem(title: "Settings…", action: .openSettings))
        items.append(MenuModelItem(title: "Quit Lattice", action: .quit))

        return items
    }

    private static func savedViewsSubmenu(from state: MenuModelState) -> MenuModelItem {
        var go: [MenuModelItem] = []
        var store: [MenuModelItem] = []
        for index in 1...9 {
            let occupied = state.occupiedViewSlots.contains(index)
            go.append(MenuModelItem(
                title: "Go to View \(index)",
                action: .recallView(index),
                enabled: occupied,
                checked: state.currentViewSlot == index,
                keyEquivalentHint: state.bindingHints[.recallView(index)]
            ))
            store.append(MenuModelItem(
                title: "\(index)",
                action: .storeView(index),
                checked: occupied,
                keyEquivalentHint: state.bindingHints[.storeView(index)]
            ))
        }
        let children: [MenuModelItem] = [
            MenuModelItem(title: "Go to View", kind: .submenu(go)),
            MenuModelItem(title: "Save Current View as", kind: .submenu(store)),
        ]
        return MenuModelItem(title: "Saved views", kind: .submenu(children))
    }

    private static func workspaceItems(from state: MenuModelState) -> [MenuModelItem] {
        var items: [MenuModelItem] = []
        let multiDisplay = state.displayCount > 1
        for number in 1...max(state.workspaceCount, 1) {
            var title = "Workspace \(number)"
            if multiDisplay {
                let names = state.activeWorkspaceByDisplay
                    .filter { $0.workspace == number }
                    .map(\.displayName)
                if !names.isEmpty {
                    title += " (\(names.joined(separator: ", ")))"
                }
            }
            let checked = state.activeWorkspaceByDisplay.contains { $0.workspace == number }
            items.append(MenuModelItem(
                title: title,
                action: .workspace(number),
                checked: checked,
                keyEquivalentHint: state.bindingHints[.workspace(number)]
            ))
        }
        return items
    }
}

// MARK: - Binding hints helper

public enum MenuBindingHints {
    /// Map `[mode.main]` bindings onto menu actions (first matching command wins).
    public static func from(mode: ModeConfig?) -> [MenuAction: String] {
        guard let mode else { return [:] }
        var hints: [MenuAction: String] = [:]
        for binding in mode.bindings {
            guard let command = binding.commands.first else { continue }
            let action: MenuAction?
            switch command {
            case .history(.back): action = .historyBack
            case .history(.forward): action = .historyForward
            case .zoom(.desktop, _): action = .zoomDesktop
            case .zoom(.all, _): action = .zoomEverything
            case .recallView(let n): action = .recallView(n)
            case .storeView(let n): action = .storeView(n)
            case .desktopArea: action = .desktopAreaToggle
            case .dockAll: action = .dockAll
            case .unmanageAll: action = .unmanageAll
            case .workspace(.number(let n)): action = .workspace(n)
            default: action = nil
            }
            if let action, hints[action] == nil {
                hints[action] = binding.chord.description
            }
        }
        return hints
    }
}
