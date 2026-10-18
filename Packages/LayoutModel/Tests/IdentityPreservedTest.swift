import Testing
import LayoutModel

@Test func windowLeafIdentitySurvivesInsert() {
    let id = WindowID(cgWindowID: 11, processID: 100, bundleID: "app.one", titleFingerprint: "One")
    let leaf = WindowLeaf(identity: id)
    let root = TreeOps.insertAtScreenEdge(
        .desktop(DesktopArea()),
        edge: .right,
        new: .window(leaf),
        cfg: .default
    )
    #expect(root.tiledWindowIDs.first?.cgWindowID == 11)
}

@Test func workspaceInsertingPreservesIdentity() {
    let id = WindowID(cgWindowID: 11, processID: 100, bundleID: "app.one", titleFingerprint: "One")
    let ws = Workspace.empty
    let (next, _) = ws.inserting(id, at: .screenEdge(.right))
    #expect(next.root.tiledWindowIDs.first?.cgWindowID == 11)
    #expect(next.allWindowIDs.first?.cgWindowID == 11)
}
