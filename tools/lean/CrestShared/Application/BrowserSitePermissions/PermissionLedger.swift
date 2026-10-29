import Foundation

struct PermissionRecord: Equatable {
    let id: UUID
    let spaceID: UUID
    let origin: SiteOrigin
    let permission: SitePermission
    let detail: String?
    var decision: SitePermissionDecision
    var modifiedAt: Double
    var state: SitePermissionRecordState {
        SitePermissionRecordState(
            id: id, spaceID: spaceID, origin: origin, permission: permission, detail: detail, decision: decision)
    }
}

enum PermissionFailure: LocalizedError, Equatable {
    case invalidOrigin, invalidDetail, invalidGrant, limitReached
    case storage(StorageFailure)
    var errorDescription: String? {
        if case .limitReached = self {
            return String(
                localized:
                    "Crest can keep up to \(PermissionLedger.maximumRecords) saved site permissions. Reset some to save more."
            )
        }
        if case .storage(let reason) = self { return Rejection.saveFailed(SaveFailed(reason: reason)).errorDescription }
        return nil
    }
}

/// The ledger owns persistent records and process-only overrides. A key uses
/// UTF-8 bytes so canonically equivalent spellings remain distinct, as in Crest.
struct PermissionLedger {
    static let maximumRecords = 4_096
    static let maximumDetailLength = 256
    private(set) var records: [PermissionRecord] = []
    private var session: [UUID: [Key: SitePermissionDecision]] = [:]
    private struct Key: Hashable {
        let scheme: Data
        let host: Data
        let port: Int
        let permission: SitePermission
        let detail: Data?
        init(_ origin: SiteOrigin, _ permission: SitePermission, _ detail: String?) {
            scheme = Data(origin.scheme.utf8)
            host = Data(origin.host.utf8)
            port = origin.port
            self.permission = permission
            self.detail = detail.map { Data($0.utf8) }
        }
    }
    static func valid(_ origin: SiteOrigin) -> Bool {
        (1...64).contains(origin.scheme.utf16.count) && (1...1_024).contains(origin.host.utf16.count)
            && (-1...65_535).contains(origin.port)
    }
    private static func valid(_ detail: String?) -> Bool {
        detail.map { (1...maximumDetailLength).contains($0.utf16.count) } ?? true
    }
    private func key(_ record: PermissionRecord) -> Key { Key(record.origin, record.permission, record.detail) }
    mutating func restore(_ input: [PermissionRecord]) {
        var seen: [UUID: Set<Key>] = [:]
        var identities: Set<UUID> = []
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        records = []
        for record in input {
            if records.count == Self.maximumRecords { break }
            guard record.id != zero, record.spaceID != zero, Self.valid(record.origin), Self.valid(record.detail),
                record.decision.isPersistent, !(record.permission.isAskedBySystem && record.decision.grants),
                record.modifiedAt.isFinite,
                identities.insert(record.id).inserted, seen[record.spaceID, default: []].insert(key(record)).inserted
            else { continue }
            records.append(record)
        }
    }
    func decision(_ space: UUID, _ origin: SiteOrigin, _ permission: SitePermission, _ detail: String? = nil)
        -> SitePermissionDecision
    {
        guard Self.valid(origin), Self.valid(detail) else { return .ask }
        for candidate in detail == nil
            ? [Key(origin, permission, nil)] : [Key(origin, permission, detail), Key(origin, permission, nil)]
        {
            if let answer = session[space]?[candidate] { return answer }
            if let record = records.first(where: { $0.spaceID == space && key($0) == candidate }) {
                return record.decision
            }
        }
        return .ask
    }
    func mediaDecision(_ space: UUID, _ origin: SiteOrigin, _ media: SitePermission) -> SitePermissionDecision {
        let devices = media.devices.map { decision(space, origin, $0) }
        let combinations = media.combinations.map { decision(space, origin, $0) }
        let strongest = (devices + combinations).max { $0.precedence < $1.precedence } ?? .ask
        if strongest.denies { return strongest }
        return combinations.first(where: \.grants) ?? devices.max { $0.precedence < $1.precedence } ?? .ask
    }
    /// Returns whether the persistent records changed. Identity survives edits.
    mutating func set(
        _ space: UUID, _ origin: SiteOrigin, _ permission: SitePermission, _ detail: String?,
        _ decision: SitePermissionDecision,
        id: UUID = UUID(), now: Double = Date().timeIntervalSinceReferenceDate
    ) throws(PermissionFailure) -> Bool {
        guard Self.valid(origin) else { throw .invalidOrigin }
        guard Self.valid(detail) else { throw .invalidDetail }
        guard !(permission.isAskedBySystem && decision.grants) else { throw .invalidGrant }
        let choice = Key(origin, permission, detail)
        let index = records.firstIndex { $0.spaceID == space && key($0) == choice }
        if decision.isPersistent {
            guard index != nil || records.count < Self.maximumRecords else { throw .limitReached }
            session[space]?[choice] = nil
            if let index {
                records[index].decision = decision
                records[index].modifiedAt = now
            } else {
                records.append(
                    PermissionRecord(
                        id: id, spaceID: space, origin: origin, permission: permission, detail: detail,
                        decision: decision, modifiedAt: now))
            }
            return true
        }
        if decision.asks {
            session[space]?[choice] = nil
            if let index {
                records.remove(at: index)
                return true
            }
        } else {
            session[space, default: [:]][choice] = decision
        }
        return false
    }
    mutating func reset(_ id: UUID) -> PermissionRecord? {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        return records.remove(at: index)
    }
    mutating func resetSpace(_ space: UUID) -> Bool {
        session[space] = nil
        let count = records.count
        records.removeAll { $0.spaceID == space }
        return records.count != count
    }
    static func precedes(_ left: PermissionRecord, _ right: PermissionRecord) -> Bool {
        let a = Array(left.origin.displayName.utf16)
        let b = Array(right.origin.displayName.utf16)
        var i = 0
        var j = 0
        while i < a.count && j < b.count {
            if (48...57).contains(a[i]), (48...57).contains(b[j]) {
                let startI = i
                let startJ = j
                while i < a.count && (48...57).contains(a[i]) { i += 1 }
                while j < b.count && (48...57).contains(b[j]) { j += 1 }
                let x = a[startI..<i].drop(while: { $0 == 48 })
                let y = b[startJ..<j].drop(while: { $0 == 48 })
                if x.count != y.count { return x.count < y.count }
                if !x.elementsEqual(y) { return x.lexicographicallyPrecedes(y) }
            } else {
                if a[i] != b[j] { return a[i] < b[j] }
                i += 1
                j += 1
            }
        }
        if a.count - i != b.count - j { return a.count - i < b.count - j }
        if left.permission != right.permission {
            return left.permission.name.utf16.lexicographicallyPrecedes(right.permission.name.utf16)
        }
        return (left.detail ?? "").utf16.lexicographicallyPrecedes((right.detail ?? "").utf16)
    }
}
