import Darwin
import Foundation

extension URL {
    // MARK: - Static Variables

    private static let localHostnameSuffixes = [
        "localhost",
        "local",
        "test",
        "internal",
        "lan",
        "home.arpa",
    ]

    // MARK: - Variables

    /// Whether this address is the person's own development work — a local
    /// file, a single-label host, a private or loopback address, or a host
    /// under a local-only suffix — so developer mode turns on by itself.
    var isLocalDevelopmentAddress: Bool {
        if isFileURL { return true }

        guard let rawHost = host()?.lowercased() else { return false }
        let hostName = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !hostName.isEmpty else { return false }

        if let address = Self.addressBytes(for: hostName, family: AF_INET, count: 4) {
            return Self.isLocalIPv4(address)
        }

        let unscopedHost = String(hostName.prefix { $0 != "%" })
        if let address = Self.addressBytes(
            for: unscopedHost,
            family: AF_INET6,
            count: 16
        ) {
            return Self.isLocalIPv6(address)
        }

        if !hostName.contains(".") { return true }

        return Self.localHostnameSuffixes.contains { suffix in
            hostName == suffix || hostName.hasSuffix(".\(suffix)")
        }
    }

    private static func addressBytes(
        for host: String,
        family: Int32,
        count: Int
    ) -> [UInt8]? {
        var address = [UInt8](repeating: 0, count: count)
        let result = address.withUnsafeMutableBytes { buffer in
            host.withCString { source in
                inet_pton(family, source, buffer.baseAddress)
            }
        }
        return result == 1 ? address : nil
    }

    private static func isLocalIPv4(_ address: [UInt8]) -> Bool {
        guard address.count == 4 else { return false }
        switch (address[0], address[1]) {
        case (0, 0) where address[2] == 0 && address[3] == 0:
            return true
        case (10, _), (127, _), (169, 254), (192, 168):
            return true
        case (172, 16...31):
            return true
        default:
            return false
        }
    }

    private static func isLocalIPv6(_ address: [UInt8]) -> Bool {
        guard address.count == 16 else { return false }

        if address.allSatisfy({ $0 == 0 }) { return true }
        if address.dropLast().allSatisfy({ $0 == 0 }), address.last == 1 {
            return true
        }
        if address[0] & 0xFE == 0xFC { return true }
        if address[0] == 0xFE, address[1] & 0xC0 == 0x80 { return true }

        let isIPv4Mapped =
            address.prefix(10).allSatisfy({ $0 == 0 })
            && address[10] == 0xFF
            && address[11] == 0xFF
        return isIPv4Mapped && isLocalIPv4(Array(address.suffix(4)))
    }
}
