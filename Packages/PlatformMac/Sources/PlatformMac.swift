import Foundation
import Platform

/// AppKit / AX / CG implementations of Platform protocols.
public enum PlatformMacModule {
    public static let name = "PlatformMac"

    /// Input Monitoring spike matrix lives at `docs/input-matrix.md` (P5a).
    public static let inputMatrixDoc = "docs/input-matrix.md"

    /// Native Spaces spike matrix lives at `docs/spaces-matrix.md` (P6a).
    public static let spacesMatrixDoc = "docs/spaces-matrix.md"
}
