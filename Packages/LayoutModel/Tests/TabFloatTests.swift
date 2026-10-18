import Testing
import LayoutModel

@Test func tabAndUntab() {
    var ws = Workspace.empty
    let a = WindowID.stub(1)
    let b = WindowID.stub(2)
    (ws, _) = ws.inserting(a, at: .screenEdge(.left))
    (ws, _) = ws.inserting(b, at: .screenEdge(.right))
    (ws, _) = ws.tabbing(b, onto: a)

    guard let path = ws.root.path(to: a) else {
        Issue.record("missing path")
        return
    }
    guard case .tabs(let tabs) = ws.root.node(at: path) else {
        Issue.record("expected tabs after tabbing")
        return
    }
    #expect(Set(tabs.windows) == [a, b])
    #expect(LayoutInvariants.holds(ws))

    (ws, _) = ws.untabbing(b)
    #expect(ws.root.contains(a))
    #expect(ws.root.contains(b))
    // After untab, b should not share a tab group with a (unless re-normalized oddly).
    if let p = ws.root.path(to: a), case .tabs = ws.root.node(at: p) {
        Issue.record("still tabbed after untab")
    }
    #expect(LayoutInvariants.holds(ws))
}

@Test func floatAndDock() {
    var ws = Workspace.empty
    let a = WindowID.stub(1)
    (ws, _) = ws.inserting(a, at: .screenEdge(.left))
    let frame = Rect(x: 40, y: 40, width: 400, height: 300)
    (ws, _) = ws.floating(a, frame: frame)
    #expect(ws.isFloating(a))
    #expect(!ws.root.contains(a))
    #expect(ws.root.desktopCount >= 1)

    (ws, _) = ws.docking(a, at: .screenEdge(.left))
    #expect(!ws.isFloating(a))
    #expect(ws.root.contains(a))
    #expect(ws.root.desktopCount == 1)
    #expect(LayoutInvariants.holds(ws))
}

@Test func floatAllMovesEveryTiledWindow() {
    var ws = Workspace.empty
    for i in 1...5 {
        (ws, _) = ws.inserting(WindowID.stub(i), at: .screenEdge(.left))
    }
    (ws, _) = ws.floatingAll()
    #expect(ws.root.tiledWindowIDs.isEmpty)
    #expect(ws.floating.count == 5)
    #expect(LayoutInvariants.holds(ws))
    if case .desktop = ws.root {
        // ok
    } else {
        // normalize may leave desktop
        #expect(ws.root.tiledWindowIDs.isEmpty)
    }
}

@Test func swapWindows() {
    var ws = Workspace.empty
    let a = WindowID.stub(1)
    let b = WindowID.stub(2)
    (ws, _) = ws.inserting(a, at: .screenEdge(.left))
    (ws, _) = ws.inserting(b, at: .screenEdge(.right))
    let pathABefore = ws.root.path(to: a)
    let pathBBefore = ws.root.path(to: b)
    (ws, _) = ws.swapping(a, with: b)
    #expect(ws.root.path(to: a) == pathBBefore)
    #expect(ws.root.path(to: b) == pathABefore)
    #expect(LayoutInvariants.holds(ws))
}

@Test func moveBetweenTargets() {
    var ws = Workspace.empty
    let a = WindowID.stub(1)
    let b = WindowID.stub(2)
    (ws, _) = ws.inserting(a, at: .screenEdge(.left))
    (ws, _) = ws.inserting(b, at: .screenEdge(.right))
    (ws, _) = ws.moving(a, to: .screenEdge(.top))
    #expect(ws.root.contains(a))
    #expect(ws.root.contains(b))
    #expect(ws.allWindowIDs.count == Set(ws.allWindowIDs).count)
    #expect(LayoutInvariants.holds(ws))
}
