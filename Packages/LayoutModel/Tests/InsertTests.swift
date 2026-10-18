import Testing
import LayoutModel

@Test func insertScreenEdgeKeepsDesktop() {
    var ws = Workspace.empty
    let w1 = WindowID.stub(1)
    (ws, _) = ws.inserting(w1, at: .screenEdge(.left))
    #expect(ws.root.desktopCount == 1)
    #expect(ws.root.tiledWindowIDs == [w1])
    #expect(LayoutInvariants.holds(ws))

    let w2 = WindowID.stub(2)
    (ws, _) = ws.inserting(w2, at: .screenEdge(.right))
    #expect(ws.root.desktopCount == 1)
    #expect(Set(ws.root.tiledWindowIDs) == [w1, w2])
    #expect(LayoutInvariants.holds(ws))
}

@Test func insertEveryDropTarget() {
    let anchors = (1...3).map { WindowID.stub($0) }
    var base = Workspace.empty
    for (i, w) in anchors.enumerated() {
        let edge: Edge = [.left, .top, .right][i]
        (base, _) = base.inserting(w, at: .screenEdge(edge))
    }
    #expect(LayoutInvariants.holds(base))

    let paths = base.root.allPaths()
    var targets: [DropTarget] = Edge.allCases.map { .screenEdge($0) }
    for path in paths {
        targets.append(.center(nodePath: path))
        for edge in Edge.allCases {
            targets.append(.edge(nodePath: path, edge: edge))
        }
    }

    for (i, target) in targets.enumerated() {
        let newbie = WindowID.stub(100 + i)
        let (next, diff) = base.inserting(newbie, at: target)
        #expect(diff.inserted.contains(newbie), "target \(target)")
        #expect(next.contains(newbie), "target \(target)")
        #expect(LayoutInvariants.holds(next), "invariants failed for \(target): \(LayoutInvariants.check(next))")
        // Unique window occurrence.
        let ids = next.allWindowIDs
        #expect(ids.count == Set(ids).count)
    }
}

@Test func insertCenterMakesTabs() {
    var ws = Workspace.empty
    let a = WindowID.stub(1)
    let b = WindowID.stub(2)
    (ws, _) = ws.inserting(a, at: .screenEdge(.left))
    // Path to the panel (not desktop).
    guard let path = ws.root.path(to: a) else {
        Issue.record("missing path")
        return
    }
    (ws, _) = ws.inserting(b, at: .center(nodePath: path))
    guard let node = ws.root.node(at: path) else {
        Issue.record("missing node")
        return
    }
    guard case .tabs(let tabs) = node else {
        Issue.record("expected tabs, got \(node)")
        return
    }
    #expect(tabs.windows == [a, b])
    #expect(LayoutInvariants.holds(ws))
}
