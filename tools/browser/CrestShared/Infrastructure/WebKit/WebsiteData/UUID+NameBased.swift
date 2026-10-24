import CryptoKit
import Foundation

extension UUID {
    /// The name-based (version 5) UUID for `name` in `namespace`, as RFC 9562
    /// section 5.5 defines it.
    init(name: Data, namespace: UUID) {
        var input = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        input.append(name)
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        self.init(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
