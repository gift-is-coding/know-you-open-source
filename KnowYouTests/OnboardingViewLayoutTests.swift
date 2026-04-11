import XCTest
import SwiftUI
import AppKit
@testable import KnowYou

private actor OnboardingProbeTracker {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func markStarted() {
        started = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

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

    func testOnboardingStartsBackgroundEngineProbeOnAppear() async {
        let tracker = OnboardingProbeTracker()
        let appState = AppState(
            bootstrapServices: false,
            probeEngine: { engine, _, _ in
                if engine == .claudeCLI {
                    await tracker.markStarted()
                }
                return EngineProbeResult(
                    engine: engine,
                    state: .yellow,
                    detail: "Probe finished.",
                    verifiedAt: nil
                )
            }
        )
        let view = OnboardingView(onComplete: {}, initialStep: .permissions)
            .environment(appState)
        let hostingView = NSHostingView(rootView: view)

        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        await tracker.waitUntilStarted()
        XCTAssertTrue(appState.isRetestingEngines)
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
