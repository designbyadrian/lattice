import Foundation
import LayoutEngine
import LayoutModel
import Platform
import Config

/// Coordinates engine ↔ platform. Depends on Platform protocols only (never PlatformMac).
public final class AppCoordinator: @unchecked Sendable {
    public private(set) var config: LatticeConfig
    public let platform: any WindowServerProtocol

    public init(platform: any WindowServerProtocol, config: LatticeConfig = .default) {
        self.platform = platform
        self.config = config
    }

    public func reloadConfig(_ config: LatticeConfig) {
        self.config = config
    }
}
