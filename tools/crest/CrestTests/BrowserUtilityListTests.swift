import Foundation
import XCTest

@testable import Crest

final class BrowserUtilityListTests: XCTestCase {
    func testDownloadReconciliationDropsRemovedAndForeignProfileRows() throws {
        let context = utilityDownloadContext()
        let prepared = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.2,
            phase: .downloading
        )
        let foreign = utilityDownload(
            id: context.itemID,
            profileID: identifier(0x66),
            progress: 0.9,
            phase: .finished
        )
        let exact = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.4,
            phase: .downloading
        )
        let preparedSections = [context.section(prepared)]

        for current in [[], [foreign]] {
            XCTAssertTrue(
                BrowserUtilityListReconciliation.sections(
                    preparedSections: preparedSections,
                    surface: .downloads,
                    assignment: context.assignment,
                    downloads: current,
                    searchText: "",
                    filter: .all
                ).isEmpty
            )
        }

        let reconciled = BrowserUtilityListReconciliation.sections(
            preparedSections: preparedSections,
            surface: .downloads,
            assignment: context.assignment,
            downloads: [foreign, exact, foreign],
            searchText: "",
            filter: .all
        )
        let item = try XCTUnwrap(reconciled.first?.items.first)
        guard case .download(let current) = item else {
            return XCTFail("Expected the exact-profile download")
        }
        XCTAssertEqual(current.profileID, context.assignment.profileID)
        XCTAssertEqual(current.progress, 0.4)
    }

    private func localized(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
            .replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
    }

    private func utilityDownloadContext() -> (
        assignment: BrowserSpaceRuntimeAssignment,
        itemID: UUID,
        section: (DownloadState) -> BrowserUtilityListSection
    ) {
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: identifier(0x61),
            profileID: identifier(0x62)
        )
        let now = Date(timeIntervalSinceReferenceDate: 807_969_600)
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = timeZone
        }
        let timeframe = BrowserUtilityTimeSection(
            date: now,
            now: now,
            calendar: calendar
        )
        return (
            assignment,
            identifier(0x63),
            { item in
                BrowserUtilityListSection(
                    timeframe: timeframe,
                    items: [.download(item)]
                )
            }
        )
    }

    private func utilityDownload(
        id: UUID,
        profileID: UUID,
        progress: Double,
        phase: DownloadPhase
    ) -> DownloadState {
        DownloadState.fixture(
            id: id,
            profileID: profileID,
            createdAt: Date(timeIntervalSinceReferenceDate: 807_969_600),
            filename: "Crest.dmg",
            destination: URL(filePath: "/crest-preview/Crest.dmg"),
            progress: progress,
            phase: phase
        )
    }

    private func identifier(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0x40, 0,
                0x80, 0, 0, 0, 0, 0, 0, finalByte
            )
        )
    }
}
