import Foundation
import XCTest
@testable import Catway

private struct FixtureRunner: ProcessRunning {
    let spaces: Data
    let windows: Data

    func run(executable: String, arguments: [String]) throws -> ProcessResult {
        if arguments == ["-m", "query", "--spaces"] {
            return ProcessResult(status: 0, stdout: spaces, stderr: Data())
        }
        if arguments == ["-m", "query", "--windows"] {
            return ProcessResult(status: 0, stdout: windows, stderr: Data())
        }
        return ProcessResult(status: 64, stdout: Data(), stderr: Data("unexpected command".utf8))
    }
}

final class YabaiClientTests: XCTestCase {
    func testClientDecodesCurrentYabaiSchema() throws {
        let spaces = Data("""
        [{"index":1,"label":"N1","windows":[42],"has-focus":true}]
        """.utf8)
        let windows = Data("""
        [{"app":"Code","space":1}]
        """.utf8)
        let client = try YabaiClient(
            executable: "/mock/yabai",
            runner: FixtureRunner(spaces: spaces, windows: windows)
        )

        let result = try client.loadWorkspaces()

        XCTAssertEqual(result, [
            WorkspaceModel(index: 1, label: "N1", isFocused: true, windowCount: 1, apps: ["Code"]),
        ])
    }

    func testClientSurfacesYabaiFailure() throws {
        struct FailureRunner: ProcessRunning {
            func run(executable: String, arguments: [String]) throws -> ProcessResult {
                ProcessResult(status: 1, stdout: Data(), stderr: Data("socket unavailable".utf8))
            }
        }
        let client = try YabaiClient(executable: "/mock/yabai", runner: FailureRunner())
        XCTAssertThrowsError(try client.loadWorkspaces()) { error in
            XCTAssertTrue(error.localizedDescription.contains("socket unavailable"))
        }
    }
}
