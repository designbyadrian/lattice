import Foundation
import Platform

/// OS majors that failed the P6a spike matrix (`docs/spaces-matrix.md`).
/// Empty while every matrix cell is `PENDING_VM`. After Adrian marks a row `FAIL`,
/// add that major here so the probe routes it to `.currentSpaceOnly`.
public enum SpacesMatrixFailures: Sendable {
    public static let failedMajors: Set<Int> = []

    public static func isFailed(osMajor: Int) -> Bool {
        failedMajors.contains(osMajor)
    }
}

public struct SpacesProbeResult: Sendable, Equatable {
    public var backend: SpacesBackend
    public var osMajor: Int
    public var osBuild: String
    public var missingSymbols: [String]
    public var matrixFailed: Bool
    public var notice: String?

    public init(
        backend: SpacesBackend,
        osMajor: Int,
        osBuild: String,
        missingSymbols: [String] = [],
        matrixFailed: Bool = false,
        notice: String? = nil
    ) {
        self.backend = backend
        self.osMajor = osMajor
        self.osBuild = osBuild
        self.missingSymbols = missingSymbols
        self.matrixFailed = matrixFailed
        self.notice = notice
    }
}

/// Launch / post-update probe: native vs currentSpaceOnly safety net.
public enum SpacesCapabilityProbe {
    public static func probe(
        symbols: any SpacesSymbolLooking = SkyLightSymbolTable.shared,
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        osBuild: String = Self.currentOSBuild(),
        matrixFailedMajors: Set<Int> = SpacesMatrixFailures.failedMajors
    ) -> SpacesProbeResult {
        let major = osVersion.majorVersion
        var missing: [String] = []

        for name in SpacesSymbolName.requiredQuery + SpacesSymbolName.requiredOperations {
            if symbols.address(for: name) == nil {
                missing.append(name.rawValue)
            }
        }
        // At least one bridged dispatcher must exist.
        let hasSync = symbols.address(for: .bridgedPerformSync) != nil
        let hasAsync = symbols.address(for: .bridgedPerformAsync) != nil
        if !hasSync && !hasAsync {
            missing.append(SpacesSymbolName.bridgedPerformSync.rawValue)
        }

        let matrixFailed = matrixFailedMajors.contains(major)
        if !missing.isEmpty || matrixFailed {
            let reason: String
            if matrixFailed {
                reason = "P6a matrix FAIL for macOS \(major) (build \(osBuild))"
            } else {
                reason = "Missing SkyLight symbols on macOS \(major) (build \(osBuild)): \(missing.joined(separator: ", "))"
            }
            return SpacesProbeResult(
                backend: .currentSpaceOnly,
                osMajor: major,
                osBuild: osBuild,
                missingSymbols: missing,
                matrixFailed: matrixFailed,
                notice: reason
            )
        }

        return SpacesProbeResult(
            backend: .native,
            osMajor: major,
            osBuild: osBuild,
            missingSymbols: [],
            matrixFailed: false,
            notice: nil
        )
    }

    public static func currentOSBuild() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        return version
    }
}
