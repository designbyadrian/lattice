import Testing
import LayoutModel

@Test func freshWorkspaceIsDesktop() {
    let ws = Workspace.empty
    #expect(ws.root == .desktop)
    #expect(LayoutInvariants.holds(ws))
}
