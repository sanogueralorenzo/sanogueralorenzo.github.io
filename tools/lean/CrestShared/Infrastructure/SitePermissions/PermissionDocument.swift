import CoreFoundation
import Foundation

/// Reads the defaults document Crest already imports once. Malformed entries
/// contribute nothing; the ledger then enforces identity, scope and limits.
enum PermissionDocument {
    static func read(_ data: Data?) -> [PermissionRecord] {
        guard let data, let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any], depth(rows) <= 8 else {
            return []
        }
        return rows.compactMap { value -> PermissionRecord? in
            guard let row = value as? [String: Any], let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                let space = ((row["spaceID"] as? [String: Any])?["rawValue"] as? String ?? row["spaceID"] as? String)
                    .flatMap(UUID.init(uuidString:)),
                let origin = row["origin"] as? [String: Any], let scheme = origin["scheme"] as? String,
                let host = origin["host"] as? String, let port = origin["port"] as? Int,
                (Int(Int32.min)...Int(Int32.max)).contains(port),
                let portNumber = origin["port"] as? NSNumber, CFGetTypeID(portNumber) != CFBooleanGetTypeID(),
                let permission = SitePermission.named(row["permission"] as? String),
                let decision = SitePermissionDecision.named(row["decision"] as? String),
                let time = row["modifiedAt"] as? Double,
                let number = row["modifiedAt"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                row["detail"] == nil || row["detail"] is NSNull || row["detail"] is String
            else { return nil }
            return PermissionRecord(
                id: id, spaceID: space, origin: SiteOrigin(scheme: scheme, host: host, port: port),
                permission: permission,
                detail: row["detail"] as? String, decision: decision, modifiedAt: time)
        }.prefix(PermissionLedger.maximumRecords).map { $0 }
    }
    private static func depth(_ value: Any) -> Int {
        if let array = value as? [Any] { return 1 + (array.map(depth).max() ?? 0) }
        if let dictionary = value as? [String: Any] { return 1 + (dictionary.values.map(depth).max() ?? 0) }
        return 0
    }
}
