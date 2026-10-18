import Testing
import AppCore
import Config
import Platform

@Test func menuModelEmptyHistoryDisablesBackForward() {
    let model = MenuModel.build(from: MenuModelState(
        canGoBack: false,
        canGoForward: false
    ))
    let back = model.controls.first { $0.control == .back }
    let forward = model.controls.first { $0.control == .forward }
    #expect(back?.enabled == false)
    #expect(forward?.enabled == false)
}

@Test func menuModelPartialHistory() {
    let model = MenuModel.build(from: MenuModelState(
        canGoBack: true,
        canGoForward: false
    ))
    #expect(model.controls.first { $0.control == .back }?.enabled == true)
    #expect(model.controls.first { $0.control == .forward }?.enabled == false)
}

@Test func menuModelEmptyViewSlotsOmitViewControls() {
    let model = MenuModel.build(from: MenuModelState(
        occupiedViewSlots: [],
        menuBarControls: [.views, .desktop]
    ))
    #expect(model.controls.filter { $0.control == .views }.isEmpty)
    #expect(model.controls.contains { $0.control == .desktop })
}

@Test func menuModelOccupiedViewSlotsAndCurrentFilled() {
    let model = MenuModel.build(from: MenuModelState(
        occupiedViewSlots: [1, 3, 9],
        currentViewSlot: 3,
        menuBarControls: [.views]
    ))
    let views = model.controls.filter { $0.control == .views }
    #expect(views.map(\.viewIndex) == [1, 3, 9])
    #expect(views.first { $0.viewIndex == 3 }?.isOn == true)
    #expect(views.first { $0.viewIndex == 1 }?.isOn == false)

    let go = flatten(model.items).first { $0.action == .recallView(3) }
    #expect(go?.enabled == true)
    #expect(go?.checked == true)
    let emptyGo = flatten(model.items).first { $0.action == .recallView(2) }
    #expect(emptyGo?.enabled == false)
    let storeOccupied = flatten(model.items).first { $0.action == .storeView(1) }
    #expect(storeOccupied?.checked == true)
}

@Test func menuModelOneWorkspaceOneDisplay() {
    let model = MenuModel.build(from: MenuModelState(
        workspaceCount: 1,
        activeWorkspaceByDisplay: [MenuDisplayWorkspace(displayName: "Built-in", workspace: 1)],
        displayCount: 1
    ))
    let workspaces = flatten(model.items).filter {
        if case .workspace = $0.action { return true }
        return false
    }
    #expect(workspaces.count == 1)
    #expect(workspaces[0].title == "Workspace 1")
    #expect(workspaces[0].checked == true)
}

@Test func menuModelThreeWorkspacesTwoDisplays() {
    let model = MenuModel.build(from: MenuModelState(
        workspaceCount: 3,
        activeWorkspaceByDisplay: [
            MenuDisplayWorkspace(displayName: "Built-in", workspace: 1),
            MenuDisplayWorkspace(displayName: "Dell", workspace: 2),
        ],
        displayCount: 2
    ))
    let workspaces = flatten(model.items).filter {
        if case .workspace = $0.action { return true }
        return false
    }
    #expect(workspaces.count == 3)
    #expect(workspaces[0].title.contains("Built-in"))
    #expect(workspaces[1].title.contains("Dell"))
    #expect(workspaces[0].checked == true)
    #expect(workspaces[1].checked == true)
    #expect(workspaces[2].checked == false)
}

@Test func menuModelCurrentSpaceOnlyShowsNotice() {
    let model = MenuModel.build(from: MenuModelState(
        workspaceCount: 3,
        spacesBackend: .currentSpaceOnly,
        spacesNotice: SpacesSafetyNetCopy.menuNotice
    ))
    let flat = flatten(model.items)
    #expect(flat.contains { $0.title == SpacesSafetyNetCopy.menuNotice })
    #expect(flat.contains { $0.action == .spacesDetails })
    #expect(!flat.contains {
        if case .workspace = $0.action { return true }
        return false
    })
}

@Test func menuModelInputSafetyNetNotice() {
    let model = MenuModel.build(from: MenuModelState(
        inputFeaturesDisabled: false,
        inputSafetyNetActive: true,
        inputSafetyNetNotice: "reduced input features active"
    ))
    let flat = flatten(model.items)
    #expect(flat.contains { $0.title == "reduced input features active" })
    #expect(flat.contains { $0.action == .toggleInputFeatures && $0.title.hasPrefix("Disable") })
}

@Test func menuModelNoOverviewItem() {
    let model = MenuModel.build(from: MenuModelState())
    let titles = flatten(model.items).map(\.title)
    #expect(!titles.contains(where: { $0.localizedCaseInsensitiveContains("overview") }))
    #expect(model.controls.contains { $0.control == .everything && $0.action == .zoomEverything })
}

@Test func menuModelDesktopEverythingFilledState() {
    let desktop = MenuModel.build(from: MenuModelState(
        isFramingDesktop: true,
        isFramingEverything: false,
        menuBarControls: [.desktop, .everything]
    ))
    #expect(desktop.controls.first { $0.control == .desktop }?.isOn == true)
    #expect(desktop.controls.first { $0.control == .everything }?.isOn == false)

    let all = MenuModel.build(from: MenuModelState(
        isFramingDesktop: false,
        isFramingEverything: true,
        menuBarControls: [.desktop, .everything]
    ))
    #expect(all.controls.first { $0.control == .everything }?.isOn == true)
}

@Test func menuModelControlsOrderFollowsConfig() {
    let model = MenuModel.build(from: MenuModelState(
        occupiedViewSlots: [2],
        menuBarControls: [.everything, .back, .views, .desktop]
    ))
    #expect(model.controls.map(\.control) == [.everything, .back, .views, .desktop])
}

@Test func menuModelDesktopAreaCheckmark() {
    let visible = MenuModel.build(from: MenuModelState(desktopAreaVisible: true))
    let hidden = MenuModel.build(from: MenuModelState(desktopAreaVisible: false))
    let v = flatten(visible.items).first { $0.action == .desktopAreaToggle }
    let h = flatten(hidden.items).first { $0.action == .desktopAreaToggle }
    #expect(v?.checked == true)
    #expect(h?.checked == false)
}

private func flatten(_ items: [MenuModelItem]) -> [MenuModelItem] {
    var result: [MenuModelItem] = []
    for item in items {
        result.append(item)
        if case .submenu(let kids) = item.kind {
            result.append(contentsOf: flatten(kids))
        }
    }
    return result
}
