import Foundation

enum BrowserPlatformUserAgent {
    static let applicationName: String? = {
        let operatingSystemMajorVersion =
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return "Version/\(operatingSystemMajorVersion).0 Safari/604.1"
    }()
}
