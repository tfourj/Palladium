import XCTest
@testable import Palladium

final class PackageIndexMirrorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PackageIndexMirrorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToPipDefaultIndex() {
        XCTAssertEqual(PackageIndexMirror.selected(in: defaults), .pypi)
        XCTAssertNil(PackageIndexMirror.selectedIndexURL(in: defaults))
    }

    func testPresetMirrorsUseFixedURLs() {
        defaults.set(PackageIndexMirror.tsinghua.rawValue, forKey: PackageIndexMirror.defaultsKey)
        XCTAssertEqual(PackageIndexMirror.selectedIndexURL(in: defaults), "https://pypi.tuna.tsinghua.edu.cn/simple")

        defaults.set(PackageIndexMirror.aliyun.rawValue, forKey: PackageIndexMirror.defaultsKey)
        XCTAssertEqual(PackageIndexMirror.selectedIndexURL(in: defaults), "https://mirrors.aliyun.com/pypi/simple/")
    }

    func testCustomMirrorUsesTrimmedURL() {
        defaults.set(PackageIndexMirror.custom.rawValue, forKey: PackageIndexMirror.defaultsKey)
        defaults.set("  https://example.com/simple \n", forKey: PackageIndexMirror.customURLDefaultsKey)

        XCTAssertEqual(PackageIndexMirror.selectedIndexURL(in: defaults), "https://example.com/simple")
    }

    func testInvalidCustomURLFallsBackToPipDefault() {
        defaults.set(PackageIndexMirror.custom.rawValue, forKey: PackageIndexMirror.defaultsKey)

        for value in ["", "example.com/simple", "ftp://example.com/simple", "https://"] {
            defaults.set(value, forKey: PackageIndexMirror.customURLDefaultsKey)
            XCTAssertNil(PackageIndexMirror.selectedIndexURL(in: defaults), value)
        }
    }

    func testUnknownStoredValueFallsBackToDefault() {
        defaults.set("removed-mirror", forKey: PackageIndexMirror.defaultsKey)

        XCTAssertEqual(PackageIndexMirror.selected(in: defaults), .pypi)
    }
}
