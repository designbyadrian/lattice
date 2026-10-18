import Foundation
import LayoutModel
import Platform

extension WindowRef {
    public func asWindowFacts(
        resizable: Bool = true,
        fullscreenButtonEnabled: Bool = true,
        closeButtonEnabled: Bool = true
    ) -> WindowFacts {
        WindowFacts(
            bundleID: bundleID,
            appName: appName ?? "",
            title: title,
            kind: WindowKind.from(subrole: subrole),
            resizable: resizable,
            fullscreenButtonEnabled: fullscreenButtonEnabled,
            closeButtonEnabled: closeButtonEnabled
        )
    }
}
