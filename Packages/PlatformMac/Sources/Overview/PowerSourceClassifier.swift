import Foundation

#if canImport(IOKit.ps)
import IOKit.ps
#endif

/// Machine class inferred from IOPS power-source dictionaries (PLAN §6).
public enum MachinePowerClass: String, Sendable, Equatable {
    /// No internal battery → desktop (Mac mini / Studio / iMac).
    case desktop
    /// Has an internal battery → laptop (including when on AC mains).
    case laptop
}

/// Keys mirrored from IOKit power-source dictionaries so tests can use fixtures
/// without calling `IOPSCopyPowerSourcesInfo`.
public enum PowerSourceKeys {
    /// `kIOPSTypeKey`
    public static let type = "Type"
    /// `kIOPSInternalBatteryType`
    public static let internalBattery = "InternalBattery"
    /// `kIOPSUPSType`
    public static let ups = "UPS"
    /// `kIOPSPowerSourceStateKey`
    public static let state = "Power Source State"
    /// `kIOPSACPowerValue`
    public static let acPower = "AC Power"
    /// `kIOPSBatteryPowerValue`
    public static let batteryPower = "Battery Power"
}

/// Pure classification over IOPS-style dictionaries.
public enum PowerSourceClassifier {
    /// Returns `.laptop` iff any source has `Type == InternalBattery`.
    /// A UPS attached to a desktop does **not** count as an internal battery.
    public static func classify(sources: [[String: Any]]) -> MachinePowerClass {
        for source in sources {
            let type = source[PowerSourceKeys.type] as? String
            if type == PowerSourceKeys.internalBattery {
                return .laptop
            }
        }
        return .desktop
    }

    /// Live system probe via `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList`.
    public static func classifySystem() -> MachinePowerClass {
        #if canImport(IOKit.ps)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .desktop
        }
        guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .desktop
        }
        var sources: [[String: Any]] = []
        for item in list {
            if let desc = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any] {
                sources.append(desc)
            }
        }
        return classify(sources: sources)
        #else
        return .desktop
        #endif
    }
}
