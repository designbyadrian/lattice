import Testing
import Platform
import PlatformMac

@Test func moduleName() {
    #expect(PlatformMacModule.name == "PlatformMac")
}

@Test func macPermissionsPreflightAPIsExist() {
    let perms = MacPermissions()
    // Just exercise getters; values depend on the host environment.
    _ = perms.isAccessibilityTrusted
    _ = perms.hasScreenRecordingAccess
}

@Test func displayUUIDHelperHandlesBogusID() {
    // Unknown display IDs should not crash; may return nil.
    let uuid = MacDisplays.uuidString(for: 0)
    _ = uuid
}

@Test func windowServerConforms() async {
    let server = MacWindowServer()
    #expect(server.experimentalFlags.axWindowID == false)
    let displays = await server.listDisplays()
    // CI / headless may still have at least the main display when a session exists.
    _ = displays
}
