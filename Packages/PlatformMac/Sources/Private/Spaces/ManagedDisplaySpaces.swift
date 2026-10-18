import CoreFoundation
import Foundation
import LayoutModel

#if canImport(ObjectiveC)
import ObjectiveC
#endif

/// Function pointer shapes for SkyLight queries (resolved via dlsym; never linked).
private typealias SLSMainConnectionIDProc = @convention(c) () -> Int32
private typealias SLSCopyManagedDisplaySpacesProc = @convention(c) (Int32) -> Unmanaged<CFArray>?

/// Parses `SLSCopyManagedDisplaySpaces` dictionaries into `DisplaySnapshot`s.
public enum ManagedDisplaySpaces {
    /// Space type values observed in managed-display-spaces dictionaries (public RE notes).
    /// User desktop ≈ 0; full-screen app Space ≈ 4. Only non-fullscreen are bindable.
    public static let fullscreenSpaceType = 4

    public static func connectionID(
        symbols: any SpacesSymbolLooking = SkyLightSymbolTable.shared
    ) -> Int32? {
        guard let ptr = symbols.address(for: .mainConnectionID) else { return nil }
        let fn = unsafeBitCast(ptr, to: SLSMainConnectionIDProc.self)
        return fn()
    }

    public static func copyRawManagedDisplaySpaces(
        symbols: any SpacesSymbolLooking = SkyLightSymbolTable.shared
    ) -> [[String: Any]]? {
        guard let cid = connectionID(symbols: symbols),
              let ptr = symbols.address(for: .copyManagedDisplaySpaces)
        else { return nil }
        let fn = unsafeBitCast(ptr, to: SLSCopyManagedDisplaySpacesProc.self)
        guard let unmanaged = fn(cid) else { return nil }
        let cfArray = unmanaged.takeRetainedValue()
        let array = cfArray as NSArray as? [Any] ?? []
        return array.compactMap { $0 as? [String: Any] }
    }

    public static func snapshots(
        symbols: any SpacesSymbolLooking = SkyLightSymbolTable.shared,
        displayNamesByUUID: [String: String] = [:]
    ) -> [DisplaySnapshot]? {
        guard let raw = copyRawManagedDisplaySpaces(symbols: symbols) else { return nil }
        return raw.compactMap { entry in
            parseDisplayEntry(entry, displayNamesByUUID: displayNamesByUUID)
        }
    }

    public static func parseDisplayEntry(
        _ entry: [String: Any],
        displayNamesByUUID: [String: String]
    ) -> DisplaySnapshot? {
        let uuid = displayUUID(from: entry) ?? ""
        guard !uuid.isEmpty else { return nil }

        let spacesRaw = (entry["Spaces"] as? [Any]) ?? []
        let spaces: [SpaceSnapshot] = spacesRaw.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            return parseSpace(dict)
        }
        guard !spaces.isEmpty else { return nil }

        let current: SpaceID
        if let currentDict = entry["Current Space"] as? [String: Any],
           let parsed = parseSpace(currentDict) {
            current = parsed.id
        } else {
            current = spaces[0].id
        }

        let name = displayNamesByUUID[uuid] ?? uuid
        return DisplaySnapshot(
            uuid: uuid,
            nameForPatterns: name,
            spaces: spaces,
            current: current
        )
    }

    public static func parseSpace(_ dict: [String: Any]) -> SpaceSnapshot? {
        let idValue: UInt64?
        if let n = dict["id64"] as? UInt64 {
            idValue = n
        } else if let n = dict["id64"] as? Int {
            idValue = UInt64(n)
        } else if let n = dict["ManagedSpaceID"] as? UInt64 {
            idValue = n
        } else if let n = dict["ManagedSpaceID"] as? Int {
            idValue = UInt64(n)
        } else {
            idValue = nil
        }
        guard let idValue else { return nil }

        let typeValue: Int
        if let t = dict["type"] as? Int {
            typeValue = t
        } else if let t = dict["type"] as? UInt64 {
            typeValue = Int(t)
        } else {
            typeValue = 0
        }
        let isFullscreen = typeValue == fullscreenSpaceType
        return SpaceSnapshot(id: SpaceID(rawValue: idValue), isFullscreen: isFullscreen)
    }

    private static func displayUUID(from entry: [String: Any]) -> String? {
        if let s = entry["Display Identifier"] as? String { return s }
        if let s = entry["DisplayID"] as? String { return s }
        return nil
    }
}
