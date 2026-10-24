import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit

enum BrowserPerformanceProcessReporter {
    private static let prefix = "CREST_PERFORMANCE_WEB_CONTENT_PID="

    static func line(webContentPID: pid_t) -> String? {
        guard webContentPID > 0 else { return nil }
        return "\(prefix)\(webContentPID)\n"
    }

    static func report(webContentPID: pid_t) {
        guard let line = line(webContentPID: webContentPID) else { return }
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    #if CREST_PERFORMANCE_HARNESS
        static func report(webView: WKWebView) {
            let selector = NSSelectorFromString("_webProcessIdentifier")
            guard webView.responds(to: selector),
                let processIdentifier = webView.value(forKey: "_webProcessIdentifier") as? NSNumber
            else {
                return
            }
            report(webContentPID: processIdentifier.int32Value)
        }
    #endif
}
