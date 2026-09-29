#if DEBUG
import SwiftUI
import UIKit

extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        DeveloperDebugMenuPresenter.present(in: self)
    }
}

enum DeveloperDebugMenuPresenter {
    // Results survive closing the menu so a shake can reopen the last run.
    private static let store = DeveloperDiagnosticsStore()

    static func present(in window: UIWindow) {
        guard var topController = window.rootViewController else { return }
        while true {
            if topController is DeveloperDebugMenuHostingController { return }
            guard let presented = topController.presentedViewController else { break }
            topController = presented
        }

        let presenter = topController
        let menu = DeveloperDebugMenuView(store: store) {
            presenter.dismiss(animated: true)
        }
        presenter.present(DeveloperDebugMenuHostingController(rootView: menu), animated: true)
    }
}

private final class DeveloperDebugMenuHostingController: UIHostingController<DeveloperDebugMenuView> {}
#endif
