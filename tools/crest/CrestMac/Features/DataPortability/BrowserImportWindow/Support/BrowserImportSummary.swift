import Foundation
import SwiftUI

enum BrowserImportPreviewControls {
    static let sourceFooterLeadingSymbol: String? = nil
    static let usesAnchoredImportFooter = true
}

enum BrowserImportSummary {
    static func tabCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(max(count, 0)) tabs", comment: "Tab count shown while reviewing a browser import.")
    }

    /// How many of a Space's pinned tabs move to a saved folder.
    static func overflowCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "\(max(count, 0)) pinned tabs move to a saved folder",
            comment: "Shown under the tab count while reviewing a browser import.")
    }

    static func extensionCount(included: Int, total: Int) -> LocalizedStringResource {
        let total = max(total, 0)
        let included = min(max(included, 0), total)
        return LocalizedStringResource(
            "\(included) of \(total) extensions",
            comment: "Extension count shown while reviewing a browser import. The first count is how many are on."
        )
    }

    static func leftOutCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "\(max(count, 0)) left out",
            comment: "How many of a browser's profiles or Spaces an import cannot bring, shown in the import review."
        )
    }

    /// What setup did, as the core summed it up.
    static func completed(_ summary: ImportSummary) -> LocalizedStringResource {
        completedImport(
            tabCount: summary.tabCount, spaceCount: summary.spaceCount)
    }

    private static func completedImport(
        tabCount: Int,
        spaceCount: Int
    ) -> LocalizedStringResource {
        let tabs = max(tabCount, 0)
        let spaces = max(spaceCount, 0)
        return LocalizedStringResource(
            "Imported \(tabs) reviewed tabs across \(spaces) Spaces.",
            comment:
                "Browser-import completion summary. The first count is imported tabs; the second is destination Spaces."
        )
    }
}
