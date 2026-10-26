import CoreServices
import Foundation

enum BrowserPlatformDownloadQuarantine {
    static func apply(
        _ quarantine: BrowserDownloadQuarantine,
        to destinationURL: URL
    ) throws {
        var properties: [String: Any] = [
            kLSQuarantineAgentNameKey as String: quarantine.agentName,
            kLSQuarantineAgentBundleIdentifierKey as String:
                quarantine.agentBundleIdentifier,
            kLSQuarantineTimeStampKey as String: quarantine.timestamp,
            kLSQuarantineTypeKey as String:
                kLSQuarantineTypeWebDownload as String,
        ]
        if let sourceURL = quarantine.sourceURL {
            properties[kLSQuarantineOriginURLKey as String] = sourceURL
            properties[kLSQuarantineDataURLKey as String] = sourceURL
        }

        var resourceValues = URLResourceValues()
        resourceValues.quarantineProperties = properties
        var mutableURL = destinationURL
        try mutableURL.setResourceValues(resourceValues)
    }
}
