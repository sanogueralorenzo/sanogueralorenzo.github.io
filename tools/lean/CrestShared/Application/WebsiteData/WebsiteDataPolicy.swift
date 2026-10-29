import Foundation

enum BrowsingDataCategory: String, CaseIterable, Sendable {
    case history, siteData, cache
    static let all = allCases
    var name: String { rawValue }
    var clearsHistory: Bool { self == .history }
    var clearsBySite: Bool { self != .history }
    var title: LocalizedStringResource {
        switch self {
        case .history: "History"
        case .siteData: "Cookies and Site Data"
        case .cache: "Cached Images and Files"
        }
    }
    var detail: LocalizedStringResource? { self == .siteData ? "Signs you out of most sites." : nil }
    var clearSiteTitle: LocalizedStringResource? {
        switch self {
        case .history: nil
        case .siteData: "Clear Cookies"
        case .cache: "Clear Cache"
        }
    }
    var clearedTitle: LocalizedStringResource? {
        switch self {
        case .history: nil
        case .siteData: "Cookies Cleared"
        case .cache: "Cache Cleared"
        }
    }
    var failedTitle: LocalizedStringResource? {
        switch self {
        case .history: nil
        case .siteData: "Couldn’t Clear Cookies"
        case .cache: "Couldn’t Clear Cache"
        }
    }
    var symbol: String? {
        switch self {
        case .history: nil
        case .siteData: "person.crop.circle.badge.xmark"
        case .cache: "trash"
        }
    }
}
enum WebsiteDataKind: String, CaseIterable, Sendable {
    case cookies, storage, cache
    static let all = allCases
    var name: String { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .cookies: "Cookies"
        case .storage: "Storage"
        case .cache: "Cache"
        }
    }
}
enum WebsiteDataFailure: Error, Equatable { case invalidSiteHost, noCategory }

/// Requests keep only their native inputs; WebKit implements the operation
/// directly. No command identity or result callback is sent through the core.
protocol DataDeletionRequest: Sendable {
    var profileID: UUID { get }
    var ephemeral: Bool { get }
    var erasesProfile: Bool { get }
    func validated() throws(WebsiteDataFailure) -> Self
    @MainActor func erase(on binding: WebKitEngineBinding, at now: Date) async -> Bool
}
extension DeleteProfileData {
    var erasesProfile: Bool { true }
    func validated() throws(WebsiteDataFailure) -> Self { self }
}
extension DeleteSiteData {
    var erasesProfile: Bool { false }
    func validated() throws(WebsiteDataFailure) -> Self {
        var seen: Set<Data> = []
        let hosts = hosts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter {
            seen.insert(Data($0.utf8)).inserted
        }
        guard !hosts.isEmpty, hosts.allSatisfy({ (1...253).contains($0.utf16.count) }) else { throw .invalidSiteHost }
        let categories = BrowsingDataCategory.all.filter { $0.clearsBySite && self.categories.contains($0) }
        guard !categories.isEmpty else { throw .noCategory }
        return Self(
            profileID: profileID, ephemeral: ephemeral, hosts: hosts, categories: categories)
    }
}
extension DeleteBrowsingData {
    var erasesProfile: Bool { false }
    func validated() throws(WebsiteDataFailure) -> Self {
        let categories = BrowsingDataCategory.all.filter(self.categories.contains)
        guard !categories.isEmpty else { throw .noCategory }
        return Self(
            profileID: profileID, ephemeral: ephemeral, range: range, categories: categories)
    }
}
extension BrowsingDataRange {
    func since(_ now: Date) -> Date? {
        let seconds: TimeInterval
        switch self {
        case .lastHour: seconds = 3_600
        case .lastDay: seconds = 86_400
        case .lastWeek: seconds = 7 * 86_400
        case .lastFourWeeks: seconds = 28 * 86_400
        default: return nil
        }
        return now.addingTimeInterval(-seconds)
    }
}
