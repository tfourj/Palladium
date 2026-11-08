import XCTest
@testable import Palladium

final class SavedDownloadLocationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var rootURL: URL!
    private var appFolderURL: URL!

    override func setUpWithError() throws {
        suiteName = "SavedDownloadLocationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedDownloadLocationTests-\(UUID().uuidString)", isDirectory: true)
        appFolderURL = rootURL.appendingPathComponent("Documents/Saved", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testDefaultsToAppFolder() {
        let store = makeStore()

        XCTAssertEqual(store.state, .appFolder)
        XCTAssertEqual(store.directoryURL, appFolderURL)
        XCTAssertFalse(store.isCustom)
        XCTAssertEqual(store.displayPath, "Documents/Saved")
    }

    func testChosenFolderSavesIntoPalladiumSubfolder() throws {
        let pickedURL = try makePickedFolder(named: "iCloud Pick")
        let store = makeStore()

        try store.useFolder(pickedURL)

        XCTAssertEqual(store.state, .custom(folderName: "iCloud Pick"))
        XCTAssertEqual(store.directoryURL.standardizedFileURL.lastPathComponent, "Palladium")
        XCTAssertEqual(
            store.directoryURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath(),
            pickedURL.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directoryURL.path))
        XCTAssertEqual(store.displayPath, "iCloud Pick/Palladium")
    }

    func testChosenFolderPersistsAcrossLaunches() throws {
        let pickedURL = try makePickedFolder(named: "Shared")
        try makeStore().useFolder(pickedURL)

        let relaunched = makeStore()

        XCTAssertEqual(relaunched.state, .custom(folderName: "Shared"))
        XCTAssertNotEqual(relaunched.directoryURL, appFolderURL)
    }

    func testResetReturnsToAppFolder() throws {
        let store = makeStore()
        try store.useFolder(try makePickedFolder(named: "Shared"))

        store.resetToAppFolder()

        XCTAssertEqual(store.state, .appFolder)
        XCTAssertEqual(store.directoryURL, appFolderURL)
        XCTAssertNil(defaults.data(forKey: SavedDownloadLocationStore.bookmarkKey))
        XCTAssertEqual(makeStore().state, .appFolder)
    }

    func testUnresolvableBookmarkFallsBackToAppFolder() {
        defaults.set(Data("not a bookmark".utf8), forKey: SavedDownloadLocationStore.bookmarkKey)
        defaults.set("Gone", forKey: SavedDownloadLocationStore.folderNameKey)

        let store = makeStore()

        XCTAssertEqual(store.state, .unavailable(folderName: "Gone"))
        XCTAssertEqual(store.directoryURL, appFolderURL)
        XCTAssertTrue(store.isCustom)
        XCTAssertEqual(store.displayPath, "Documents/Saved")
    }

    func testUnavailableFolderRecoversOnReload() throws {
        let pickedURL = try makePickedFolder(named: "External")
        try makeStore().useFolder(pickedURL)
        let bookmark = try XCTUnwrap(defaults.data(forKey: SavedDownloadLocationStore.bookmarkKey))
        defaults.set(Data("broken".utf8), forKey: SavedDownloadLocationStore.bookmarkKey)
        let store = makeStore()
        XCTAssertEqual(store.state, .unavailable(folderName: "External"))

        defaults.set(bookmark, forKey: SavedDownloadLocationStore.bookmarkKey)
        store.reloadIfUnavailable()

        XCTAssertEqual(store.state, .custom(folderName: "External"))
    }

    private func makeStore() -> SavedDownloadLocationStore {
        SavedDownloadLocationStore(defaults: defaults, appFolderURL: appFolderURL)
    }

    private func makePickedFolder(named name: String) throws -> URL {
        let url = rootURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
