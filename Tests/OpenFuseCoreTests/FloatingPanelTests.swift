import XCTest
@testable import OpenFuseCore

final class FloatingPanelTests: XCTestCase {
    func testPanelWidthStartsAtFiveHundredSixtyAndShrinksWithTheWindow() {
        XCTAssertEqual(FloatingPanelMath.panelWidth(containerWidth: 1180), 560)
        XCTAssertEqual(FloatingPanelMath.panelWidth(containerWidth: 900), 560)
        XCTAssertEqual(FloatingPanelMath.panelWidth(containerWidth: 600), 560)
        XCTAssertEqual(FloatingPanelMath.panelWidth(containerWidth: 500), 476)
        XCTAssertEqual(FloatingPanelMath.panelWidth(containerWidth: 320), 304)
        XCTAssertEqual(FloatingPanelMath.panelWidth(containerWidth: 0), 0)
    }

    func testDefaultOriginIsTopCentre() {
        let origin = FloatingPanelMath.baseOrigin(
            containerSize: CGSize(width: 1180, height: 760),
            panelSize: CGSize(width: 560, height: 96)
        )
        XCTAssertEqual(origin.x, 310, accuracy: 0.01)
        XCTAssertEqual(origin.y, 64, accuracy: 0.01)
        XCTAssertTrue(FloatingPanelMath.previewOpensDownward(panelOriginY: origin.y))
    }

    func testDraggedPanelCannotLeaveTheWindow() {
        let container = CGSize(width: 800, height: 600)
        let panel = CGSize(width: 520, height: 100)

        let farRightDown = FloatingPanelMath.clampedOffset(
            offset: CGSize(width: 5_000, height: 5_000),
            panelSize: panel,
            containerSize: container
        )
        let base = FloatingPanelMath.baseOrigin(containerSize: container, panelSize: panel)
        XCTAssertEqual(base.x + farRightDown.width, 800 - 520 - 8, accuracy: 0.01)
        XCTAssertEqual(base.y + farRightDown.height, 600 - 100 - 8, accuracy: 0.01)

        let farLeftUp = FloatingPanelMath.clampedOffset(
            offset: CGSize(width: -5_000, height: -5_000),
            panelSize: panel,
            containerSize: container
        )
        XCTAssertEqual(base.x + farLeftUp.width, 8, accuracy: 0.01)
        XCTAssertEqual(base.y + farLeftUp.height, 8, accuracy: 0.01)
    }

    func testResizeKeepsThePanelVisible() {
        let panel = CGSize(width: 304, height: 84)
        // A position that was valid in a 1180×760 window.
        let offset = FloatingPanelMath.clampedOffset(
            offset: CGSize(width: 280, height: 300),
            panelSize: panel,
            containerSize: CGSize(width: 1180, height: 760)
        )
        // Shrink to a 320×180 player (the documented minimum).
        let resized = FloatingPanelMath.clampedOffset(
            offset: offset,
            panelSize: panel,
            containerSize: CGSize(width: 320, height: 180)
        )
        let base = FloatingPanelMath.baseOrigin(
            containerSize: CGSize(width: 320, height: 180),
            panelSize: panel
        )
        XCTAssertGreaterThanOrEqual(base.x + resized.width, 8)
        XCTAssertLessThanOrEqual(base.x + resized.width + panel.width, 320 - 8 + 0.01)
        XCTAssertGreaterThanOrEqual(base.y + resized.height, 8)
        XCTAssertLessThanOrEqual(base.y + resized.height + panel.height, 180 - 8 + 0.01)
    }

    func testPreviewDirectionFollowsThePanelPosition() {
        XCTAssertTrue(FloatingPanelMath.previewOpensDownward(panelOriginY: 64))
        XCTAssertTrue(FloatingPanelMath.previewOpensDownward(panelOriginY: 189))
        XCTAssertFalse(FloatingPanelMath.previewOpensDownward(panelOriginY: 190))
        XCTAssertFalse(FloatingPanelMath.previewOpensDownward(panelOriginY: 420))
    }
}

final class PlayerHeadingTests: XCTestCase {
    func testSeriesHeadingUsesShowNameAndEpisode() {
        let heading = PlayerHeadingFormatter.heading(
            seriesTitle: "Fargo (2014)",
            episodeLabel: "S01E01",
            itemTitle: "S01E01 — Pilot"
        )
        XCTAssertEqual(heading.title, "Fargo (2014)")
        XCTAssertEqual(heading.detail, "S01E01 · Pilot")
    }

    func testHeadingDoesNotRepeatTheEpisodeLabel() {
        let heading = PlayerHeadingFormatter.heading(
            seriesTitle: "Fargo (2014)",
            episodeLabel: "S01E01",
            itemTitle: "S01E01"
        )
        XCTAssertEqual(heading.title, "Fargo (2014)")
        XCTAssertEqual(heading.detail, "S01E01")
    }

    func testMovieHeadingKeepsItsTitle() {
        let heading = PlayerHeadingFormatter.heading(
            seriesTitle: nil,
            episodeLabel: nil,
            itemTitle: "Big Buck Bunny"
        )
        XCTAssertEqual(heading.title, "Big Buck Bunny")
        XCTAssertNil(heading.detail)
    }

    func testEpisodeNameFromJellyfinStyleTitle() {
        let heading = PlayerHeadingFormatter.heading(
            seriesTitle: "Fargo",
            episodeLabel: "S01E01",
            itemTitle: "Pilot"
        )
        XCTAssertEqual(heading.title, "Fargo")
        XCTAssertEqual(heading.detail, "S01E01 · Pilot")
    }

    func testLocalFileNameHeadingDropsTheShowAndEpisodePrefix() {
        let heading = PlayerHeadingFormatter.heading(
            seriesTitle: "Fargo (2014)",
            episodeLabel: "S01E01",
            itemTitle: "Fargo (2014) - S01E01 - Pilot"
        )
        XCTAssertEqual(heading.title, "Fargo (2014)")
        XCTAssertEqual(heading.detail, "S01E01 · Pilot")

        let dotted = PlayerHeadingFormatter.heading(
            seriesTitle: "Fargo (2014)",
            episodeLabel: "S01E01",
            itemTitle: "Fargo (2014).S01E01.Pilot.1080p"
        )
        XCTAssertEqual(dotted.title, "Fargo (2014)")
        XCTAssertEqual(dotted.detail, "S01E01 · Pilot 1080p")
    }

    func testWhitespaceAndFullPathTitlesAreTrimmed() {
        let heading = PlayerHeadingFormatter.heading(
            seriesTitle: "  Fargo (2014)  ",
            episodeLabel: "  S01E01 ",
            itemTitle: "  S01E01 — Pilot  "
        )
        XCTAssertEqual(heading.title, "Fargo (2014)")
        XCTAssertEqual(heading.detail, "S01E01 · Pilot")
    }
}
