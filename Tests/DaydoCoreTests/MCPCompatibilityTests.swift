import XCTest
@testable import DaydoCore

final class MCPCompatibilityTests: XCTestCase {
    func testCodexExperimentalObjectDoesNotBlockInitialization() throws {
        let input = Data(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"experimental":{"codex/auth-change":{}},"elicitation":{"form":{},"url":{}}},"clientInfo":{"name":"codex-mcp-client","version":"0.154.0"}}}"#.utf8)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: MCPCompatibility.normalizeInitialization(input)) as? [String: Any])
        let params = try XCTUnwrap(result["params"] as? [String: Any])
        let capabilities = try XCTUnwrap(params["capabilities"] as? [String: Any])
        XCTAssertNil(capabilities["experimental"])
        XCTAssertNotNil(capabilities["elicitation"])
        XCTAssertEqual(params["protocolVersion"] as? String, "2025-06-18")
    }

    func testToolArgumentsAndMalformedMessagesAreNeverRewritten() {
        for raw in [#"{"method":"tools/call","params":{"capabilities":{"experimental":{"note":"keep"}}}}"#, "not JSON"] {
            let input = Data(raw.utf8)
            XCTAssertEqual(MCPCompatibility.normalizeInitialization(input), input)
        }
    }
}
