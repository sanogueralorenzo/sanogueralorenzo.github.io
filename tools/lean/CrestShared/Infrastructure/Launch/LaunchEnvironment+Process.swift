import Foundation

extension BrowserLaunchEnvironment {
    static var current: BrowserLaunchEnvironment {
        let process = ProcessInfo.processInfo
        let environment = process.environment
        return BrowserLaunchEnvironment(
            values: environment,
            isXCTestRuntime: NSClassFromString("XCTestCase") != nil
                || environment["XCTestConfigurationFilePath"] != nil
                || environment["XCTestBundlePath"] != nil
                || environment["XCTestSessionIdentifier"] != nil
                || environment["XCInjectBundleInto"] != nil
                || process.arguments.contains { $0.hasPrefix("-XCTest") },
            isSwiftUIPreviewRuntime:
                environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        )
    }
}
