import AppKit
import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit
import Config

/// Owns overview preview capture. Frames stay in memory — never written to disk.
/// Call on the main thread.
public final class OverviewPreviewController: @unchecked Sendable {
    public private(set) var mode: OverviewCaptureMode = .icons
    public private(set) var isActive = false

    private var streams: [UInt32: SCStream] = [:]
    private var snapshotTimer: Timer?
    private var latestImages: [UInt32: NSImage] = [:]
    private var onFrame: ((UInt32, NSImage) -> Void)?

    public init() {}

    /// Resolve and start capture for the given config / permissions.
    public func start(
        config: OverviewPreviewsMode,
        screenRecordingGranted: Bool,
        windowIDs: [UInt32],
        onFrame: @escaping (UInt32, NSImage) -> Void
    ) {
        stop()
        self.onFrame = onFrame
        let machine = PowerSourceClassifier.classifySystem()
        mode = PreviewModeSelector.select(
            config: config,
            machine: machine,
            screenRecordingGranted: screenRecordingGranted
        )
        isActive = true

        switch mode {
        case .icons:
            break
        case .live:
            Task { await startLiveStreams(windowIDs: windowIDs) }
        case .snapshots:
            Task { [weak self] in
                guard let self else { return }
                await self.captureSnapshots(windowIDs: windowIDs)
                await MainActor.run {
                    self.snapshotTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                        Task {
                            await self?.captureSnapshots(windowIDs: windowIDs)
                        }
                    }
                }
            }
        }
    }

    public func stop() {
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        for (_, stream) in streams {
            stream.stopCapture()
        }
        streams.removeAll()
        latestImages.removeAll()
        onFrame = nil
        isActive = false
    }

    public func image(for windowID: UInt32) -> NSImage? {
        latestImages[windowID]
    }

    // MARK: - Live

    private func startLiveStreams(windowIDs: [UInt32]) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            for windowID in windowIDs {
                guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                config.width = max(2, Int(scWindow.frame.width))
                config.height = max(2, Int(scWindow.frame.height))
                config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
                config.queueDepth = 2
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                let output = PreviewStreamOutput { [weak self] image in
                    DispatchQueue.main.async {
                        self?.latestImages[windowID] = image
                        self?.onFrame?(windowID, image)
                    }
                }
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .main)
                try await stream.startCapture()
                streams[windowID] = stream
            }
        } catch {
            // Fall back silently; overview still shows icon tiles.
            mode = .icons
        }
    }

    // MARK: - Snapshots

    private func captureSnapshots(windowIDs: [UInt32]) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            for windowID in windowIDs {
                guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                config.width = max(2, Int(scWindow.frame.width))
                config.height = max(2, Int(scWindow.frame.height))
                if let cgImage = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                ) {
                    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    latestImages[windowID] = image
                    onFrame?(windowID, image)
                }
            }
        } catch {
            mode = .icons
        }
    }
}

/// In-memory SCStream output — never writes to disk.
private final class PreviewStreamOutput: NSObject, SCStreamOutput {
    let handler: (NSImage) -> Void

    init(handler: @escaping (NSImage) -> Void) {
        self.handler = handler
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let rep = NSCIImageRep(ciImage: ciImage)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        handler(image)
    }
}
