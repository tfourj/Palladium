import Darwin
import XCTest
@testable import Palladium

final class QuickJSBridgeTests: XCTestCase {
    private func invoke(_ request: [String: Any]) throws -> [String: Any] {
        typealias Run = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
        typealias Free = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
        let handle = try XCTUnwrap(dlopen(nil, RTLD_NOW))
        defer { dlclose(handle) }
        let runSymbol = try XCTUnwrap(dlsym(handle, "palladium_quickjs_bridge_run"))
        let freeSymbol = try XCTUnwrap(dlsym(handle, "palladium_quickjs_bridge_free"))
        let run = unsafeBitCast(runSymbol, to: Run.self)
        let free = unsafeBitCast(freeSymbol, to: Free.self)
        let data = try JSONSerialization.data(withJSONObject: request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let pointer = try XCTUnwrap(json.withCString { run($0) })
        defer { free(pointer) }
        let response = Data(bytes: pointer, count: strlen(pointer))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
    }

    @MainActor
    func testPythonPackageStagesQuickJSAdapter() throws {
        let scriptRoot = PythonScripts.ytDlpScriptURL.deletingLastPathComponent()
        let adapter = scriptRoot.appendingPathComponent("palladium_ytdlp/quickjs_bridge.py")
        let bundledAdapter = try XCTUnwrap(Bundle.main.url(forResource: "quickjs_bridge", withExtension: "py"))
        XCTAssertEqual(try Data(contentsOf: adapter), try Data(contentsOf: bundledAdapter))
    }

    func testAppExportsEmbeddedEngine() throws {
        let response = try invoke(["operation": "info"])
        XCTAssertEqual(response["name"] as? String, "quickjs-ng")
        XCTAssertEqual(response["ok"] as? Bool, true)
    }

    func testAppBridgeEvaluatesUnicodeAndPendingJobs() throws {
        let response = try invoke([
            "operation": "evaluate",
            "source": "Promise.resolve().then(() => console.log('živjo 🌍'))"
        ])
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["output"] as? String, "živjo 🌍\n")
    }
}
