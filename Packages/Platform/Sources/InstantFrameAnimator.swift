import Foundation

/// Immediate frame application for tests and hosts without a display link.
public final class InstantFrameAnimator: FrameAnimating, @unchecked Sendable {
    public typealias FrameApplier = @Sendable (WindowFrameTarget) async throws -> Void

    /// Shared mutable applier so hosts can wire `self` after construction.
    public final class ApplierBox: @unchecked Sendable {
        public var apply: FrameApplier?
        public init(_ apply: FrameApplier? = nil) {
            self.apply = apply
        }
    }

    private let box: ApplierBox
    private let queue = DispatchQueue(label: "com.designbyadrian.lattice.instant-frame-animator")
    private var _animating = false

    public init(box: ApplierBox = ApplierBox()) {
        self.box = box
    }

    public convenience init(apply: @escaping FrameApplier) {
        self.init(box: ApplierBox(apply))
    }

    public var isAnimating: Bool {
        queue.sync { _animating }
    }

    public func cancelAnimation() {
        queue.sync { _animating = false }
    }

    public func animateFrames(
        to targets: [WindowFrameTarget],
        durationSeconds: Double,
        reduceMotion: Bool
    ) async {
        _ = durationSeconds
        _ = reduceMotion
        queue.sync { _animating = true }
        let apply = box.apply
        for t in targets {
            try? await apply?(t)
        }
        queue.sync { _animating = false }
    }
}
