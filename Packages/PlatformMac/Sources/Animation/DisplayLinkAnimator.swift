import AppKit
import CoreVideo
import Foundation
import LayoutEngine
import LayoutModel
import Platform
import QuartzCore

/// Drives `LayoutEngine.FrameAnimator` on the display refresh; applies frames via AX.
/// Interruptible: a new `animateFrames` retargets mid-flight. Reduce Motion → jump to end.
public final class DisplayLinkAnimator: FrameAnimating, @unchecked Sendable {
    public typealias FrameApplier = @Sendable (WindowFrameTarget) async throws -> Void

    private let apply: FrameApplier
    private let stateQueue = DispatchQueue(label: "com.designbyadrian.lattice.display-link-animator")

    private var displayLink: CADisplayLink?
    private var cvDisplayLink: CVDisplayLink?
    private var animator: FrameAnimator?
    private var metaByKey: [String: WindowFrameTarget] = [:]
    private var lastApplied: [String: Rect] = [:]
    private var lastTick: CFTimeInterval = 0
    private var completion: CheckedContinuation<Void, Never>?
    private var generation: UInt64 = 0
    private var _animating = false

    public init(apply: @escaping FrameApplier) {
        self.apply = apply
    }

    public var isAnimating: Bool {
        stateQueue.sync { _animating }
    }

    public func cancelAnimation() {
        stateQueue.sync {
            finishLocked(applyFinal: false)
        }
    }

    public func animateFrames(
        to targets: [WindowFrameTarget],
        durationSeconds: Double,
        reduceMotion: Bool
    ) async {
        if reduceMotion || durationSeconds <= 0 {
            for t in targets {
                try? await apply(t)
            }
            stateQueue.sync {
                for t in targets {
                    let key = Self.key(t)
                    lastApplied[key] = Rect(
                        x: t.frame.x, y: t.frame.y, width: t.frame.width, height: t.frame.height
                    )
                    metaByKey[key] = t
                }
                finishLocked(applyFinal: false)
            }
            return
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            stateQueue.async {
                self.retargetLocked(to: targets, durationSeconds: durationSeconds, continuation: cont)
            }
        }
    }

    // MARK: - Internals

    private static func key(_ t: WindowFrameTarget) -> String {
        "\(t.windowID)|\(t.pid)"
    }

    private static func windowID(for key: String, meta: WindowFrameTarget) -> WindowID {
        WindowID(
            cgWindowID: meta.windowID,
            processID: meta.pid,
            bundleID: nil,
            titleFingerprint: key
        )
    }

    private func retargetLocked(
        to targets: [WindowFrameTarget],
        durationSeconds: Double,
        continuation: CheckedContinuation<Void, Never>
    ) {
        if let previous = completion {
            completion = nil
            previous.resume()
        }
        completion = continuation
        generation &+= 1

        var toMap: [WindowID: Rect] = [:]
        var fromMap: [WindowID: Rect] = [:]
        var meta: [String: WindowFrameTarget] = [:]

        for t in targets {
            let k = Self.key(t)
            meta[k] = t
            let wid = Self.windowID(for: k, meta: t)
            let dest = Rect(x: t.frame.x, y: t.frame.y, width: t.frame.width, height: t.frame.height)
            toMap[wid] = dest
            if let existing = lastApplied[k] {
                fromMap[wid] = existing
            } else if let flying = animator?.frames(at: animator?.elapsedSeconds ?? 0) {
                // Try match by cg id during flight.
                if let match = flying.first(where: { $0.key.cgWindowID == t.windowID })?.value {
                    fromMap[wid] = match
                } else {
                    fromMap[wid] = dest
                }
            } else {
                fromMap[wid] = dest
            }
        }

        if var existing = animator, !existing.isFinished {
            // Retarget from current eased position.
            existing.retarget(to: toMap)
            existing.durationSeconds = durationSeconds
            animator = existing
        } else {
            animator = FrameAnimator(from: fromMap, to: toMap, durationSeconds: durationSeconds)
        }
        metaByKey = meta
        _animating = true
        lastTick = CACurrentMediaTime()
        startDisplayLinkLocked()
    }

    private func tickLocked() {
        guard var anim = animator, _animating else { return }
        let now = CACurrentMediaTime()
        let dt = max(0, now - lastTick)
        lastTick = now
        // Advance the curve for timing only. ADDENDUM-2 B12 / ADDENDUM-3 §5.1:
        // still proxies draw motion; AX is written once at settle (not every frame).
        _ = anim.advance(by: dt)
        animator = anim

        let gen = generation
        stateQueue.async {
            guard self.generation == gen else { return }
            if self.animator?.isFinished == true {
                self.finishLocked(applyFinal: true)
            }
        }
    }

    private func finishLocked(applyFinal: Bool) {
        stopDisplayLinkLocked()
        if applyFinal, let anim = animator {
            let frames = anim.frames(at: anim.durationSeconds)
            var finals: [WindowFrameTarget] = []
            for (wid, rect) in frames {
                let k = wid.titleFingerprint
                guard let m = metaByKey[k] else { continue }
                lastApplied[k] = rect
                finals.append(WindowFrameTarget(
                    windowID: m.windowID,
                    pid: m.pid,
                    frame: CGRectCodable(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
                ))
            }
            let apply = self.apply
            Task {
                for t in finals {
                    try? await apply(t)
                }
            }
        }
        animator = nil
        _animating = false
        if let cont = completion {
            completion = nil
            cont.resume()
        }
    }

    private func startDisplayLinkLocked() {
        if displayLink != nil || cvDisplayLink != nil { return }

        if let screen = NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            return
        }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        let unmanaged = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, context -> CVReturn in
            guard let context else { return kCVReturnSuccess }
            let animator = Unmanaged<DisplayLinkAnimator>.fromOpaque(context).takeUnretainedValue()
            animator.stateQueue.async {
                animator.tickLocked()
            }
            return kCVReturnSuccess
        }, unmanaged)
        CVDisplayLinkStart(link)
        cvDisplayLink = link
    }

    private func stopDisplayLinkLocked() {
        if let link = displayLink {
            link.invalidate()
            displayLink = nil
        }
        if let link = cvDisplayLink {
            CVDisplayLinkStop(link)
            cvDisplayLink = nil
        }
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        _ = link
        stateQueue.async { [weak self] in
            self?.tickLocked()
        }
    }

    deinit {
        stateQueue.sync {
            stopDisplayLinkLocked()
            if let cont = completion {
                completion = nil
                cont.resume()
            }
        }
    }
}

/// Accessibility preference for Reduce Motion (AppKit).
public enum ReduceMotion {
    public static var isEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
