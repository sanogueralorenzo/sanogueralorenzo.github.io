import Foundation
import SwiftUI

/// The groups of the emoji catalog, as the category bar offers them.
///
/// `name` is the category the generated catalog files each emoji under.
struct BrowserEmojiCategory: Decodable, Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let people = BrowserEmojiCategory(name: "people", title: "Smileys & People", symbol: "face.smiling")
    static let nature = BrowserEmojiCategory(name: "nature", title: "Animals & Nature", symbol: "pawprint")
    static let food = BrowserEmojiCategory(name: "food", title: "Food & Drink", symbol: "cup.and.saucer")
    static let activity = BrowserEmojiCategory(name: "activity", title: "Activity", symbol: "medal")
    static let travel = BrowserEmojiCategory(name: "travel", title: "Travel & Places", symbol: "bus")
    static let objects = BrowserEmojiCategory(name: "objects", title: "Objects", symbol: "gift")
    static let symbols = BrowserEmojiCategory(name: "symbols", title: "Symbols", symbol: "heart")
    static let flags = BrowserEmojiCategory(name: "flags", title: "Flags", symbol: "flag")

    /// Every category, in the category bar's order.
    static let all: [BrowserEmojiCategory] = [people, nature, food, activity, travel, objects, symbols, flags]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let symbol: String

    var id: String { name }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, symbol: String) {
        self.name = name
        self.title = title
        self.symbol = symbol
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let category = Self.all.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown emoji category \(name)")
        }
        self = category
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserEmojiCategory, rhs: BrowserEmojiCategory) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

struct BrowserTabEmojiVariant: Identifiable, Sendable {
    let emoji: String
    let name: String

    var id: String { emoji }
}

struct BrowserTabEmojiChoice: Identifiable, Sendable {
    let emoji: String
    let name: String
    let category: BrowserEmojiCategory
    var keywords = ""
    var variants: [BrowserTabEmojiVariant] = []

    var id: String { emoji }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return name.localizedStandardContains(trimmed)
            || keywords.localizedStandardContains(trimmed)
            || emoji.contains(trimmed)
    }
}

struct BrowserEmojiCatalogMetadata: Decodable, Equatable, Sendable {
    let unicodeVersion: String
    let sourceURL: String
    let sourceSHA256: String
    let fullyQualifiedCount: Int
}

enum BrowserEmojiPlatformSupport {
    /// Apple added the Emoji 17 keyboard set in the 26.4 platform updates.
    /// Crest's minimum deployment target is 26.1, whose keyboard set ends at
    /// Emoji 16. Keeping this mapping explicit avoids showing a newer sequence
    /// as disconnected fallback glyphs on an older platform.
    static func maximumVersion(
        for operatingSystemVersion: OperatingSystemVersion,
        catalogVersion: Double = 17
    ) -> Double {
        let platformVersion: Double
        if operatingSystemVersion.majorVersion > 26
            || (operatingSystemVersion.majorVersion == 26
                && operatingSystemVersion.minorVersion >= 4)
        {
            platformVersion = 17
        } else {
            platformVersion = 16
        }
        return min(platformVersion, catalogVersion)
    }
}

enum BrowserTabEmojiChoices {
    /// Every fully-qualified sequence supported by the running platform.
    /// Browsing groups tone variations in the Apple keyboard style, while
    /// search returns these exact choices so no composed sequence is hidden.
    static let all = flatChoices(maximumVersion: currentMaximumVersion)

    static func choices(
        in category: BrowserEmojiCategory,
        matching query: String = ""
    ) -> [BrowserTabEmojiChoice] {
        currentGroupedSections[category, default: []]
            .filter { $0.matches(query) }
    }

    static func choices(
        in category: BrowserEmojiCategory,
        matching query: String = "",
        maximumVersion: Double
    ) -> [BrowserTabEmojiChoice] {
        groupedChoices(in: category, maximumVersion: maximumVersion)
            .filter { $0.matches(query) }
    }

    static func matching(_ query: String) -> [BrowserTabEmojiChoice] {
        all.filter { $0.matches(query) }
    }

    static func matching(
        _ query: String,
        maximumVersion: Double
    ) -> [BrowserTabEmojiChoice] {
        flatChoices(maximumVersion: maximumVersion)
            .filter { $0.matches(query) }
    }

    private static let catalog: BrowserEmojiCatalogDocument = {
        guard let data = generatedCatalogJSONString.data(using: .utf8) else {
            assertionFailure("The generated emoji catalog is not UTF-8.")
            return .empty
        }
        do {
            return try JSONDecoder().decode(
                BrowserEmojiCatalogDocument.self,
                from: data
            )
        } catch {
            assertionFailure("Cannot decode the generated emoji catalog: \(error)")
            return .empty
        }
    }()

    private static let currentMaximumVersion =
        BrowserEmojiPlatformSupport.maximumVersion(
            for: ProcessInfo.processInfo.operatingSystemVersion,
            catalogVersion: Double(catalog.metadata.unicodeVersion) ?? 17
        )

    private static let currentGroupedSections = Dictionary(
        uniqueKeysWithValues: BrowserEmojiCategory.all.map { category in
            (
                category,
                groupedChoices(
                    in: category,
                    maximumVersion: currentMaximumVersion
                )
            )
        }
    )

    private static func flatChoices(
        maximumVersion: Double
    ) -> [BrowserTabEmojiChoice] {
        catalog.entries.compactMap { entry in
            guard entry.version <= maximumVersion else { return nil }
            return BrowserTabEmojiChoice(
                emoji: entry.emoji,
                name: entry.name,
                category: entry.category,
                keywords: entry.subgroup.replacingOccurrences(of: "-", with: " ")
            )
        }
    }

    private static func groupedChoices(
        in category: BrowserEmojiCategory,
        maximumVersion: Double
    ) -> [BrowserTabEmojiChoice] {
        var entryGroups: [[BrowserEmojiCatalogEntry]] = []
        var groupIndices: [String: Int] = [:]

        for entry in catalog.entries
        where entry.category == category && entry.version <= maximumVersion {
            let key = variationGroupKey(for: entry)
            if let index = groupIndices[key] {
                entryGroups[index].append(entry)
            } else {
                groupIndices[key] = entryGroups.count
                entryGroups.append([entry])
            }
        }

        return entryGroups.compactMap { entries in
            guard let first = entries.first else { return nil }
            let baseName = nameWithoutSkinTones(first.name)
            let representative =
                entries.first { $0.name == baseName }
                ?? entries.first { !containsSkinTone($0.emoji) }
                ?? first
            let variants =
                entries.count > 1
                ? entries.map {
                    BrowserTabEmojiVariant(emoji: $0.emoji, name: $0.name)
                }
                : []
            let searchTerms = ([representative.subgroup] + entries.map(\.name))
                .joined(separator: " ")
                .replacingOccurrences(of: "-", with: " ")

            return BrowserTabEmojiChoice(
                emoji: representative.emoji,
                name: representative.name,
                category: representative.category,
                keywords: searchTerms,
                variants: variants
            )
        }
    }

    private static func variationGroupKey(
        for entry: BrowserEmojiCatalogEntry
    ) -> String {
        entry.category.name + "|" + nameWithoutSkinTones(entry.name)
    }

    private static func nameWithoutSkinTones(_ name: String) -> String {
        let components = name.split(separator: ":", maxSplits: 1)
        guard components.count == 2 else { return name }
        let remainingDetails = components[1]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasSuffix("skin tone") }
        guard !remainingDetails.isEmpty else { return String(components[0]) }
        return String(components[0]) + ": " + remainingDetails.joined(separator: ", ")
    }

    private static func containsSkinTone(_ emoji: String) -> Bool {
        emoji.unicodeScalars.contains { scalar in
            (0x1F3FB...0x1F3FF).contains(scalar.value)
        }
    }
}

private struct BrowserEmojiCatalogDocument: Decodable {
    let metadata: BrowserEmojiCatalogMetadata
    let entries: [BrowserEmojiCatalogEntry]

    static let empty = Self(
        metadata: BrowserEmojiCatalogMetadata(
            unicodeVersion: "0",
            sourceURL: "",
            sourceSHA256: "",
            fullyQualifiedCount: 0
        ),
        entries: []
    )
}

private struct BrowserEmojiCatalogEntry: Decodable {
    let emoji: String
    let name: String
    let category: BrowserEmojiCategory
    let subgroup: String
    let version: Double
}
