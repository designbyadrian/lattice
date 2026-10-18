import Testing
import LayoutModel

@Test func removeAbsorbsSiblingSpace() {
    var ws = Workspace.empty
    let a = WindowID.stub(1)
    let b = WindowID.stub(2)
    let c = WindowID.stub(3)
    (ws, _) = ws.inserting(a, at: .screenEdge(.left))
    (ws, _) = ws.inserting(b, at: .screenEdge(.right))
    (ws, _) = ws.inserting(c, at: .screenEdge(.top))

    guard case .split(let before) = ws.root else {
        Issue.record("expected split root")
        return
    }
    let ratioSumBefore = before.ratios.reduce(0, +)
    #expect(abs(ratioSumBefore - 1) < 1e-6)

    (ws, _) = ws.removing(b)
    #expect(!ws.contains(b))
    #expect(ws.contains(a))
    #expect(ws.contains(c))
    #expect(ws.root.desktopCount == 1)
    #expect(LayoutInvariants.holds(ws))

    // Ratios still valid after absorb.
    if case .split(let after) = ws.root {
        #expect(after.hasValidRatios)
    }
}

@Test func seamResizeTouchesOnlyNeighbours() {
    let a = WindowID.stub(1)
    let b = WindowID.stub(2)
    let c = WindowID.stub(3)
    let split = SplitNode(
        axis: .horizontal,
        children: [
            .panel(PanelNode(window: a)),
            .panel(PanelNode(window: b)),
            .panel(PanelNode(window: c)),
        ],
        ratios: [0.2, 0.3, 0.5]
    )
    var ws = Workspace(root: .split(split))
    let before = split.ratios
    (ws, _) = ws.resizing(path: [], dividerIndex: 0, delta: 0.1)

    guard case .split(let after) = ws.root else {
        Issue.record("expected split")
        return
    }
    #expect(abs(after.ratios[2] - before[2]) < 1e-9, "third child ratio must be untouched")
    #expect(abs((after.ratios[0] + after.ratios[1]) - (before[0] + before[1])) < 1e-9)
    #expect(after.ratios[0] > before[0])
    #expect(LayoutInvariants.holds(ws))
}

@Test func resizeClampingHonoursMinRatio() {
    let a = WindowID.stub(1)
    let b = WindowID.stub(2)
    let split = SplitNode(
        axis: .horizontal,
        children: [
            .panel(PanelNode(window: a)),
            .panel(PanelNode(window: b)),
        ],
        ratios: [0.5, 0.5]
    )
    var ws = Workspace(root: .split(split))
    (ws, _) = ws.resizing(path: [], dividerIndex: 0, delta: -10)
    guard case .split(let after) = ws.root else {
        Issue.record("expected split")
        return
    }
    #expect(after.ratios[0] >= SplitNode.minRatio - 1e-9)
    #expect(after.ratios[1] >= SplitNode.minRatio - 1e-9)
    #expect(abs(after.ratios.reduce(0, +) - 1) < 1e-6)
}
