import Testing
import LayoutModel

@Test func layoutModelModuleName() {
    #expect(LayoutModelModule.name == "LayoutModel")
}

@Test func normalizeFlattensSameAxis() {
    let tree = SplitBuilder.h(
        [WindowLeaf.win("A"), SplitBuilder.h([WindowLeaf.win("B"), WindowLeaf.win("C")], ratios: [0.25, 0.75])],
        ratios: [0.6, 0.4]
    )
    let n = tree.normalizedOrDesktop()
    guard case .split(let s) = n else {
        Issue.record("expected split")
        return
    }
    #expect(s.children.map(\.id) == ["A", "B", "C"])
    #expect(abs(s.ratios[0] - 0.6) < 1e-9)
    #expect(abs(s.ratios[1] - 0.1) < 1e-9)
    #expect(abs(s.ratios[2] - 0.3) < 1e-9)
}

@Test func insertTakesHalfOfTarget() {
    var root = SplitBuilder.H(WindowLeaf.win("A"), WindowLeaf.win("B"))
    root = TreeOps.insertAtEdge(root, targetID: "B", edge: .right, new: WindowLeaf.win("C"), cfg: .default)
    guard case .split(let s) = root else {
        Issue.record("expected split")
        return
    }
    #expect(s.children.map(\.id) == ["A", "B", "C"])
    #expect(abs(s.ratios[0] - 0.5) < 1e-9)
    #expect(abs(s.ratios[1] - 0.25) < 1e-9)
    #expect(abs(s.ratios[2] - 0.25) < 1e-9)
}

@Test func closeUndoesAddViaDonor() {
    var root = SplitBuilder.h([WindowLeaf.win("A"), WindowLeaf.win("B")], ratios: [0.7, 0.3])
    root = TreeOps.insertAtEdge(root, targetID: "A", edge: .right, new: WindowLeaf.win("C"), cfg: .default)
    root = TreeOps.remove(root, windowID: "C", cfg: .default) ?? root
    guard case .split(let s) = root else {
        Issue.record("expected split")
        return
    }
    #expect(s.children.map(\.id) == ["A", "B"])
    #expect(abs(s.ratios[0] - 0.7) < 1e-9)
    #expect(abs(s.ratios[1] - 0.3) < 1e-9)
}

@Test func firstDockOnFreshWorkspace() {
    let root = TreeOps.insertAtScreenEdge(
        .desktop(DesktopArea()),
        edge: .left,
        new: WindowLeaf.win("A"),
        cfg: .default
    )
    guard case .split(let s) = root else {
        Issue.record("expected split")
        return
    }
    #expect(s.children.count == 2)
    #expect(s.children[0].id == "A")
    #expect(s.children[1].id == "desktop")
    #expect(abs(s.ratios[0] - 0.5) < 1e-9)
}

@Test func desktopHideShowRestores() {
    var root = SplitBuilder.h(
        [WindowLeaf.win("A"), WindowLeaf.win("B"), .desktop(DesktopArea())],
        ratios: [0.4, 0.3, 0.3]
    )
    let (hidden, mem) = TreeOps.desktopAreaHide(root, cfg: .default)
    #expect(mem != nil)
    #expect(TreeOps.find(hidden, target: "desktop") == nil)
    root = TreeOps.desktopAreaShow(hidden, memory: mem, cfg: .default)
    guard case .split(let s) = root else {
        Issue.record("expected split")
        return
    }
    #expect(s.children.map(\.id) == ["A", "B", "desktop"])
    #expect(abs(s.ratios[0] - 0.4) < 1e-9)
    #expect(abs(s.ratios[1] - 0.3) < 1e-9)
    #expect(abs(s.ratios[2] - 0.3) < 1e-9)
}

@Test func cameraIsWorldRect() {
    let cam = Camera(x0: 0.3, y0: 0, x1: 0.8, y1: 1)
    #expect(cam.x0 == 0.3)
    #expect(cam.x1 == 0.8)
    #expect(Camera.home.x0 == 0)
    #expect(Camera.home.x1 == 1)
}

@Test func floatsLiveInDesktopArea() {
    let desk = DesktopArea(floats: [
        FloatWin(window: WindowLeaf(id: "F"), frac: (0.1, 0.1, 0.7, 0.6))
    ])
    #expect(desk.floats.count == 1)
    #expect(desk.floats[0].window.id == "F")
    let ws = Workspace(root: .desktop(desk))
    #expect(ws.root.floatingWindowIDs.map(\.nodeID) == ["F"])
}
