import AppKit
import SwiftUI
import XCTest
@testable import ccMonitor

@MainActor
final class SnapshotViewTests: XCTestCase {
    func test_snapshotDarkModeRendersDarkCanvas() throws {
        let color = try renderCanvasPixel(appearanceMode: .dark, systemIsDark: false)

        XCTAssertLessThan(color.redComponent, 0.35)
        XCTAssertLessThan(color.greenComponent, 0.35)
        XCTAssertLessThan(color.blueComponent, 0.35)
    }

    func test_snapshotLightModeRendersLightCanvas() throws {
        let color = try renderCanvasPixel(appearanceMode: .light, systemIsDark: false)

        XCTAssertGreaterThan(color.redComponent, 0.8)
        XCTAssertGreaterThan(color.greenComponent, 0.8)
        XCTAssertGreaterThan(color.blueComponent, 0.8)
    }

    private func renderCanvasPixel(appearanceMode: AppAppearanceMode, systemIsDark: Bool) throws -> NSColor {
        let pricing = PricingStore()
        let balance = BalanceStore()
        let snapshot = SnapshotView(
            modelUsages: [],
            pricing: pricing,
            balance: balance,
            dbPath: SettingsStore.defaultDBPath,
            summary: SummaryStats(input: 0, output: 0, cacheRead: 0, cacheCreate: 0),
            selectedRange: .today,
            expandedModelIDs: [],
            tokenPlan: nil,
            trend: [],
            heatmap: [],
            heatmapFitMode: .fit,
            trendChartDisplayMode: .bar,
            appearanceMode: appearanceMode,
            systemAppearanceIsDark: systemIsDark,
            width: 180
        )

        let renderer = ImageRenderer(content: snapshot)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let color = try XCTUnwrap(bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
        return color
    }
}

@MainActor
final class ProgressBarTests: XCTestCase {
    func test_fillWidthPreservesSmallFraction() {
        XCTAssertEqual(
            ProgressBarGeometry.fillWidth(fraction: 0.01, totalWidth: 300),
            3,
            accuracy: 0.001
        )
    }

    func test_fillWidthClampsOutOfRangeFractions() {
        XCTAssertEqual(ProgressBarGeometry.fillWidth(fraction: -0.2, totalWidth: 300), 0)
        XCTAssertEqual(ProgressBarGeometry.fillWidth(fraction: 1.2, totalWidth: 300), 300)
    }

    func test_onePercentFillDoesNotRenderAsMinimumCapsuleWidth() throws {
        let bar = UsageProgressBar(fraction: 0.01, text: "", height: 18, tint: .red)
            .environment(\.appBackgroundStyle, .solid)
            .environment(\.colorScheme, .light)
            .frame(width: 300, height: 18)
        let renderer = ImageRenderer(content: bar)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let filledPixel = try XCTUnwrap(bitmap.colorAt(x: 1, y: 9))
        let trackPixel = try XCTUnwrap(bitmap.colorAt(x: 12, y: 9))

        XCTAssertGreaterThan(filledPixel.alphaComponent, 0.8)
        XCTAssertLessThan(trackPixel.alphaComponent, 0.5)
    }
}
