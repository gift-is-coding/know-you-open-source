import AppKit
import XCTest

final class AppIconAssetTests: XCTestCase {
    func testMacAppIconImagesKeepTransparentCanvas() throws {
        let iconDirectory = projectRootURL()
            .appendingPathComponent("KnowYou/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
        let iconURLs = try FileManager.default.contentsOfDirectory(
            at: iconDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(iconURLs.isEmpty, "Expected mac app icon PNGs in \(iconDirectory.path)")

        for url in iconURLs {
            let imageData = try Data(contentsOf: url)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: imageData), "Could not decode \(url.lastPathComponent)")

            XCTAssertTrue(
                bitmap.hasAlpha,
                "\(url.lastPathComponent) should include an alpha channel so the app icon can preserve transparency"
            )
            XCTAssertTrue(
                iconHasTransparentCorner(bitmap),
                "\(url.lastPathComponent) should keep transparent corners so Dock does not render a square background"
            )
        }
    }

    private func iconHasTransparentCorner(_ bitmap: NSBitmapImageRep) -> Bool {
        let samplePoints = [
            NSPoint(x: 0, y: 0),
            NSPoint(x: bitmap.pixelsWide - 1, y: 0),
            NSPoint(x: 0, y: bitmap.pixelsHigh - 1),
            NSPoint(x: bitmap.pixelsWide - 1, y: bitmap.pixelsHigh - 1)
        ]

        return samplePoints.allSatisfy { point in
            let color = bitmap.colorAt(x: Int(point.x), y: Int(point.y))
            return (color?.alphaComponent ?? 1) < 0.05
        }
    }

    private func projectRootURL(filePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
