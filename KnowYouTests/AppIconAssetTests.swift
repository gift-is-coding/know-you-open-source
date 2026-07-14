import CoreGraphics
import ImageIO
import XCTest

final class AppIconAssetTests: XCTestCase {
    func testMacAppIconImagesKeepTransparentCanvas() throws {
        let iconDirectory = try XCTUnwrap(
            Bundle(for: Self.self).resourceURL?
                .appendingPathComponent("AppIcon.appiconset", isDirectory: true),
            "Expected a test resource directory"
        )
        let iconURLs = try FileManager.default.contentsOfDirectory(
            at: iconDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(iconURLs.isEmpty, "Expected mac app icon PNGs in \(iconDirectory.path)")

        for url in iconURLs {
            let imageData = try Data(contentsOf: url)
            let source = try XCTUnwrap(
                CGImageSourceCreateWithData(imageData as CFData, nil),
                "Could not read \(url.lastPathComponent)"
            )
            let image = try XCTUnwrap(
                CGImageSourceCreateImageAtIndex(source, 0, nil),
                "Could not decode \(url.lastPathComponent)"
            )

            XCTAssertTrue(
                image.hasAlpha,
                "\(url.lastPathComponent) should include an alpha channel so the app icon can preserve transparency"
            )
            XCTAssertTrue(
                iconHasTransparentCorner(image),
                "\(url.lastPathComponent) should keep transparent corners so Dock does not render a square background"
            )
        }
    }

    private func iconHasTransparentCorner(_ image: CGImage) -> Bool {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let cornerAlphaOffsets = [
            3,
            (image.width - 1) * 4 + 3,
            (image.height - 1) * image.width * 4 + 3,
            (image.width * image.height - 1) * 4 + 3
        ]
        return cornerAlphaOffsets.allSatisfy { pixels[$0] < 13 }
    }

}

private extension CGImage {
    var hasAlpha: Bool {
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            true
        case .none, .noneSkipFirst, .noneSkipLast, .alphaOnly:
            false
        @unknown default:
            false
        }
    }
}
