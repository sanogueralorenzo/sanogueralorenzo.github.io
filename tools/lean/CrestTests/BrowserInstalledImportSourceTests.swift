import Foundation
import XCTest

@testable import Crest

final class BrowserInstalledImportSourceTests: XCTestCase {

    func testRememberedBrowserAccessIsStoredSeparatelyForEachBrowser() throws {
        let suite = "BrowserInstalledImportSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let arcBookmark = Data("arc-bookmark".utf8)
        let zenBookmark = Data("zen-bookmark".utf8)

        BrowserImportAccessStore.saveBookmarkData(
            arcBookmark,
            for: .arc,
            defaults: defaults
        )
        BrowserImportAccessStore.saveBookmarkData(
            zenBookmark,
            for: .zen,
            defaults: defaults
        )

        XCTAssertEqual(
            BrowserImportAccessStore.bookmarkData(for: .arc, defaults: defaults),
            arcBookmark
        )
        XCTAssertEqual(
            BrowserImportAccessStore.bookmarkData(for: .zen, defaults: defaults),
            zenBookmark
        )
        XCTAssertNil(
            BrowserImportAccessStore.bookmarkData(for: .chrome, defaults: defaults)
        )
    }

    func testClearingRememberedAccessOnlyClearsTheRequestedBrowser() throws {
        let suite = "BrowserInstalledImportSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let arcBookmark = Data("arc-bookmark".utf8)
        let zenBookmark = Data("zen-bookmark".utf8)
        BrowserImportAccessStore.saveBookmarkData(
            arcBookmark,
            for: .arc,
            defaults: defaults
        )
        BrowserImportAccessStore.saveBookmarkData(
            zenBookmark,
            for: .zen,
            defaults: defaults
        )

        BrowserImportAccessStore.clear(for: .arc, defaults: defaults)

        XCTAssertNil(
            BrowserImportAccessStore.bookmarkData(for: .arc, defaults: defaults)
        )
        XCTAssertEqual(
            BrowserImportAccessStore.bookmarkData(for: .zen, defaults: defaults),
            zenBookmark
        )
    }

    func testRememberedDataDirectoryResolvesForARepeatImport() throws {
        let suite = "BrowserInstalledImportSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: directory) }

        try BrowserImportAccessStore.remember(
            directory,
            for: .arc,
            defaults: defaults
        )
        let access = try XCTUnwrap(
            BrowserImportAccessStore.resolve(for: .arc, defaults: defaults)
        )
        defer { access.stopAccessing() }

        XCTAssertEqual(
            access.url.resolvingSymlinksInPath(),
            directory.resolvingSymlinksInPath()
        )
    }

    func testHostHomeResolutionPrefersTheAccountHomeOverASandboxContainer() {
        let containerHome = URL(fileURLWithPath: "/Users/test/Library/Containers/app/Data")
        let accountHome = URL(fileURLWithPath: "/Users/test")

        XCTAssertEqual(
            ImportSource.resolvedHomeDirectory(
                currentHome: containerHome,
                accountHome: accountHome
            ),
            accountHome
        )
        XCTAssertEqual(
            ImportSource.resolvedHomeDirectory(
                currentHome: containerHome,
                accountHome: nil
            ),
            containerHome
        )
    }

    private func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("crest-import-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

}
