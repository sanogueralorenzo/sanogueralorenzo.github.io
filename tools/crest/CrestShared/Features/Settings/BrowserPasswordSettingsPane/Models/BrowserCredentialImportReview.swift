import Foundation

/// One account of a password import, as the review names it: its site and
/// the username the core's group spells, which no other group of the plan
/// shares.
struct BrowserCredentialImportGroupID:
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    // MARK: - Variables

    let origin: CredentialOrigin
    let username: String

    var description: String {
        "BrowserCredentialImportGroupID(origin: \(origin), username: <redacted>)"
    }

    var debugDescription: String { description }

    // MARK: - Initializers

    init(_ group: CredentialImportGroup) {
        origin = group.origin
        username = group.username
    }
}

extension CredentialImportGroup {
    /// The account as the review names it.
    var reviewID: BrowserCredentialImportGroupID { BrowserCredentialImportGroupID(self) }
}

/// Which password the person keeps for an account.
enum BrowserCredentialImportSelection: Equatable, Hashable, Sendable {
    case existing
    case imported(rowNumber: Int)
    case skip

    // MARK: - Actions - Choosing

    /// Whether `group` offers this choice: keeping the saved password needs
    /// one, and importing a row needs the account to bring that row.
    func isValid(for group: CredentialImportGroup) -> Bool {
        switch self {
        case .existing: group.existingID != nil
        case .imported(let rowNumber): group.candidates.contains(where: { $0.rowNumber == rowNumber })
        case .skip: true
        }
    }
}

struct BrowserCredentialImportSummary: Equatable, Sendable, Identifiable {
    let id = UUID()
    let acceptedCount: Int
    let skippedCount: Int
    let warningCount: Int
    let rejectedCount: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.acceptedCount == rhs.acceptedCount
            && lhs.skippedCount == rhs.skippedCount
            && lhs.warningCount == rhs.warningCount
            && lhs.rejectedCount == rhs.rejectedCount
    }
}

struct BrowserCredentialImportResolution: Sendable {
    let credentials: [BrowserCredential]
    let summary: BrowserCredentialImportSummary
}

/// A password import under review: the core's plan for the file against the
/// Space's saved passwords, the password the person keeps for each account,
/// and the saved passwords the plan was made against. The core decides what
/// each choice does; this applies the choices to the Keychain inventory.
struct BrowserCredentialImportReview:
    Identifiable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    // MARK: - Variables

    let id = UUID()
    let plan: CredentialImportPlan
    let destination: BrowserSpaceRuntimeAssignment
    private let existingCredentials: [BrowserCredential]
    private let synchronizesWithICloud: Bool
    private var selections: [BrowserCredentialImportGroupID: BrowserCredentialImportSelection]

    var groups: [CredentialImportGroup] { plan.groups }

    /// How many accounts the person's choices import.
    var proposedImportCount: Int {
        plan.groups.count { group in
            if case .imported = selection(for: group) { return true }
            return false
        }
    }

    /// How many accounts need the person to choose.
    var conflictCount: Int { plan.groups.count(where: \.requiresChoice) }

    var description: String {
        "BrowserCredentialImportReview(format: \(plan.format.name), destination: \(destination.spaceID), groups: \(plan.groups.count), secrets: <redacted>)"
    }

    var debugDescription: String { description }

    // MARK: - Initializers

    /// A review of `plan`, made against `existingCredentials`, the passwords
    /// the Space at `destination` keeps, starting from the choices the plan
    /// proposes.
    init(
        plan: CredentialImportPlan,
        existingCredentials: [BrowserCredential],
        destination: BrowserSpaceRuntimeAssignment,
        synchronizesWithICloud: Bool
    ) {
        self.plan = plan
        self.existingCredentials = existingCredentials
        self.destination = destination
        self.synchronizesWithICloud = synchronizesWithICloud
        selections = Dictionary(
            plan.groups.map { group in
                (
                    BrowserCredentialImportGroupID(group),
                    group.suggestedRow.map { BrowserCredentialImportSelection.imported(rowNumber: $0) } ?? .existing
                )
            },
            uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Actions - Choosing

    func selection(for group: CredentialImportGroup) -> BrowserCredentialImportSelection {
        selections[BrowserCredentialImportGroupID(group)] ?? .skip
    }

    /// Keeps `selection` for the account `id` names, when the account offers it.
    mutating func select(_ selection: BrowserCredentialImportSelection, for id: BrowserCredentialImportGroupID) {
        guard let group = plan.groups.first(where: { BrowserCredentialImportGroupID($0) == id }),
            selection.isValid(for: group)
        else { return }
        selections[id] = selection
    }

    /// The saved password the account would change, for the person to compare.
    func existingPassword(for group: CredentialImportGroup) -> String? {
        existingCredentials.first { $0.descriptor.id == group.existingID }?.password
    }

    /// The accounts whose site, username or row names match `query`.
    func groups(matching query: String) -> [CredentialImportGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return plan.groups }
        return plan.groups.filter { group in
            group.origin.description.localizedCaseInsensitiveContains(query)
                || group.username.localizedCaseInsensitiveContains(query)
                || group.candidates.contains { $0.displayName?.localizedCaseInsensitiveContains(query) == true }
        }
    }

    // MARK: - Actions - Resolving

    /// Whether the Space still keeps the passwords the plan was made against.
    func matchesExistingInventory(_ credentials: [BrowserCredential]) -> Bool {
        let order: (BrowserCredential, BrowserCredential) -> Bool = {
            $0.descriptor.id.uuidString < $1.descriptor.id.uuidString
        }
        return existingCredentials.sorted(by: order) == credentials.sorted(by: order)
    }

    /// The Space's passwords once the person's choices apply at `now`: each
    /// chosen password added or replacing the saved one as the core decided,
    /// with how many rows that accepts, skips, warns about and rejects.
    func resolvedInventory(now: Date = .now) throws -> BrowserCredentialImportResolution {
        var resolved = existingCredentials
        var acceptedCount = 0
        for group in plan.groups {
            guard case .imported(let rowNumber) = selection(for: group),
                let candidate = group.candidates.first(where: { $0.rowNumber == rowNumber }),
                candidate.effect.changesPasswords
            else { continue }
            if let existingID = group.existingID {
                guard let index = resolved.firstIndex(where: { $0.descriptor.id == existingID }) else {
                    throw BrowserCredentialSensitiveAccessError.malformedCredentialInventory
                }
                var descriptor = resolved[index].descriptor
                descriptor.username = candidate.username
                descriptor.displayName = candidate.displayName ?? descriptor.displayName
                descriptor.updatedAt = now
                resolved[index] = BrowserCredential(descriptor: descriptor, password: candidate.password)
            } else {
                resolved.append(
                    BrowserCredential(
                        descriptor: CredentialDescriptor(
                            spaceID: destination.spaceID,
                            origin: group.origin,
                            username: candidate.username,
                            displayName: candidate.displayName,
                            createdAt: now,
                            isSynchronizable: synchronizesWithICloud
                        ),
                        password: candidate.password
                    ))
            }
            acceptedCount += 1
        }
        return BrowserCredentialImportResolution(
            credentials: resolved,
            summary: BrowserCredentialImportSummary(
                acceptedCount: acceptedCount,
                skippedCount: plan.validRowCount - acceptedCount,
                warningCount: plan.warnings.count,
                rejectedCount: plan.rejections.count
            )
        )
    }
}
