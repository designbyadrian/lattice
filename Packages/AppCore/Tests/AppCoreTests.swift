import Testing
import AppCore
import Platform

private final class FakePlatform: WindowServerProtocol, @unchecked Sendable {
    func listWindows() async -> [WindowRef] { [] }
    func listDisplays() async -> [DisplayRef] { [] }
}

@Test func coordinatorHoldsConfig() {
    let c = AppCoordinator(platform: FakePlatform())
    #expect(c.config.workspaces == 1)
}
