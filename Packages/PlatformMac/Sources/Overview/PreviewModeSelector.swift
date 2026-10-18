import Foundation
import Config

/// Concrete capture strategy for overview tiles (never writes frames to disk).
public enum OverviewCaptureMode: String, Sendable, Equatable {
    /// Live `SCStream` per visible window.
    case live
    /// Periodic `SCScreenshotManager` snapshots (~1–2 s).
    case snapshots
    /// App-colour + icon tiles (no Screen Recording).
    case icons
}

/// Resolves `overview-previews` + power class + Screen Recording into a capture mode.
public enum PreviewModeSelector {
    public static func select(
        config: OverviewPreviewsMode,
        machine: MachinePowerClass,
        screenRecordingGranted: Bool
    ) -> OverviewCaptureMode {
        if config == .off || !screenRecordingGranted {
            return .icons
        }
        switch config {
        case .off:
            return .icons
        case .live:
            return .live
        case .snapshots:
            return .snapshots
        case .auto:
            switch machine {
            case .desktop:
                return .live
            case .laptop:
                // Laptop on mains still uses snapshots (PLAN §6 / §9).
                return .snapshots
            }
        }
    }
}
