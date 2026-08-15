import CoreGraphics
import XCTest
@testable import Catway

final class ModelsTests: XCTestCase {
    func testCatalogShowsOnlyOccupiedWorkspacesAndSortsUniqueApps() {
        let spaces = [
            RawSpace(index: 1, label: "N1", windows: [11, 12], hasFocus: true),
            RawSpace(index: 2, label: "Z", windows: [], hasFocus: false),
            RawSpace(index: 3, label: "V", windows: [13], hasFocus: false),
        ]
        let windows = [
            RawWindow(app: "Zen", space: 1),
            RawWindow(app: "Code", space: 1),
            RawWindow(app: "Zen", space: 1),
            RawWindow(app: "Terminal", space: 3),
        ]

        let result = WorkspaceCatalog.make(spaces: spaces, windows: windows)

        XCTAssertEqual(result.map(\.index), [1, 3])
        XCTAssertEqual(result[0].displayLabel, "1")
        XCTAssertEqual(result[0].apps, ["Code", "Zen"])
        XCTAssertEqual(result[1].displayLabel, "V")
    }

    func testCatalogCanIncludeEmptyWorkspaces() {
        let spaces = [RawSpace(index: 7, label: "", windows: [], hasFocus: true)]
        let result = WorkspaceCatalog.make(spaces: spaces, windows: [], occupiedOnly: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].displayLabel, "7")
        XCTAssertFalse(result[0].isOccupied)
    }

    func testStayCenterAlwaysWinsEvenWhenGestureOriginIsNearScreenEdge() {
        let edgeOrigin = CGPoint(x: 4, y: 5)
        XCTAssertNil(RadialLayout.nearestIndex(
            pointer: edgeOrigin,
            gestureOrigin: edgeOrigin,
            visualCenter: edgeOrigin,
            count: 8
        ))
    }

    func testRadialSelectionUsesCursorCenteredDirections() {
        let center = CGPoint(x: 100, y: 100)
        let top = RadialLayout.nearestIndex(
            pointer: CGPoint(x: 100, y: 20),
            gestureOrigin: center,
            visualCenter: center,
            count: 4
        )
        let right = RadialLayout.nearestIndex(
            pointer: CGPoint(x: 180, y: 100),
            gestureOrigin: center,
            visualCenter: center,
            count: 4
        )
        XCTAssertEqual(top, 0)
        XCTAssertEqual(right, 1)
    }

    func testNodeSizeShrinksForManyActiveWorkspaces() {
        XCTAssertEqual(RadialLayout.nodeSize(for: 4), 112)
        XCTAssertEqual(RadialLayout.nodeSize(for: 10), 82)
        XCTAssertEqual(RadialLayout.nodeSize(for: 13), 72)
    }
}
