import Testing
import Foundation
import Config
import PlatformMac

// MARK: - Power-source classification (fixture IOPS dictionaries)

@Test func powerSourceDesktopNoSources() {
    #expect(PowerSourceClassifier.classify(sources: []) == .desktop)
}

@Test func powerSourceDesktopACOnly() {
    let sources: [[String: Any]] = [
        [
            PowerSourceKeys.type: "AC Power",
            PowerSourceKeys.state: PowerSourceKeys.acPower,
        ]
    ]
    #expect(PowerSourceClassifier.classify(sources: sources) == .desktop)
}

@Test func powerSourceDesktopWithUPS() {
    // UPS attached to a desktop counts as no internal battery (PLAN §9).
    let sources: [[String: Any]] = [
        [
            PowerSourceKeys.type: PowerSourceKeys.ups,
            PowerSourceKeys.state: PowerSourceKeys.acPower,
        ],
        [
            PowerSourceKeys.type: "AC Power",
            PowerSourceKeys.state: PowerSourceKeys.acPower,
        ],
    ]
    #expect(PowerSourceClassifier.classify(sources: sources) == .desktop)
}

@Test func powerSourceLaptopOnBattery() {
    let sources: [[String: Any]] = [
        [
            PowerSourceKeys.type: PowerSourceKeys.internalBattery,
            PowerSourceKeys.state: PowerSourceKeys.batteryPower,
            "Current Capacity": 72,
        ]
    ]
    #expect(PowerSourceClassifier.classify(sources: sources) == .laptop)
}

@Test func powerSourceLaptopOnMains() {
    // Laptop on AC still has an InternalBattery source → laptop (snapshots).
    let sources: [[String: Any]] = [
        [
            PowerSourceKeys.type: PowerSourceKeys.internalBattery,
            PowerSourceKeys.state: PowerSourceKeys.acPower,
            "Current Capacity": 100,
        ],
        [
            PowerSourceKeys.type: "AC Power",
            PowerSourceKeys.state: PowerSourceKeys.acPower,
        ],
    ]
    #expect(PowerSourceClassifier.classify(sources: sources) == .laptop)
}

// MARK: - Preview-mode selection matrix

@Test func previewModeMatrix() {
    let cases: [(OverviewPreviewsMode, MachinePowerClass, Bool, OverviewCaptureMode)] = [
        // off / denied → icons
        (.off, .desktop, true, .icons),
        (.off, .laptop, true, .icons),
        (.auto, .desktop, false, .icons),
        (.auto, .laptop, false, .icons),
        (.live, .desktop, false, .icons),
        (.snapshots, .laptop, false, .icons),

        // explicit live / snapshots when granted
        (.live, .desktop, true, .live),
        (.live, .laptop, true, .live),
        (.snapshots, .desktop, true, .snapshots),
        (.snapshots, .laptop, true, .snapshots),

        // auto: desktop → live, laptop → snapshots
        (.auto, .desktop, true, .live),
        (.auto, .laptop, true, .snapshots),
    ]

    for (config, machine, granted, expected) in cases {
        let got = PreviewModeSelector.select(
            config: config,
            machine: machine,
            screenRecordingGranted: granted
        )
        #expect(
            got == expected,
            "config=\(config) machine=\(machine) granted=\(granted) → \(got), expected \(expected)"
        )
    }
}

@Test func reduceMotionHelperExists() {
    // Smoke: API is reachable in test host.
    _ = ReduceMotion.isEnabled
}
