import XCTest
import SwiftUI
import AppKit
@testable import KnowYou

@MainActor
final class OnboardingViewLayoutTests: XCTestCase {
    func testPermissionsStepRendersInsideAScrollView() {
        let appState = AppState(bootstrapServices: false)
        let view = OnboardingView(onComplete: {}, initialStep: .permissions)
            .environment(appState)
        let hostingView = NSHostingView(rootView: view)

        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNotNil(findScrollView(in: hostingView), "Permissions onboarding should stay scrollable inside the fixed window height.")
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }
}
