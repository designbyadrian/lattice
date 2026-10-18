import Testing
import Config

@Test func defaultConfig() {
    let c = LatticeConfig.default
    #expect(c.workspaces == 1)
    #expect(c.overviewPreviews == .auto)
}
