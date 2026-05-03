import AppKit
import Foundation

struct BrowserApplication: Sendable {
  let bundleIdentifier: String
  let displayName: String
}

struct BrowserURLContext: Sendable {
  let browser: BrowserApplication
  let urlString: String
}

enum CurrentBrowserURLReader {
  static func frontmostBrowserApplication() throws -> BrowserApplication {
    guard let application = NSWorkspace.shared.frontmostApplication,
      let bundleIdentifier = application.bundleIdentifier
    else {
      throw CodexCoreCLIClient.Error(message: "Could not determine the frontmost application.")
    }

    let displayName =
      application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? application.localizedName!.trimmingCharacters(in: .whitespacesAndNewlines)
      : bundleIdentifier

    return BrowserApplication(bundleIdentifier: bundleIdentifier, displayName: displayName)
  }

  static func readURL(from browser: BrowserApplication) throws -> BrowserURLContext {
    let script = try appleScript(for: browser.bundleIdentifier)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let stdoutText =
      String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderrText =
      String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
      let message = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
      throw CodexCoreCLIClient.Error(
        message: message.isEmpty
          ? "Could not read the current tab URL from \(browser.displayName)."
          : message
      )
    }

    let urlString = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !urlString.isEmpty else {
      throw CodexCoreCLIClient.Error(
        message: "The active tab in \(browser.displayName) does not have a readable URL.")
    }

    return BrowserURLContext(browser: browser, urlString: urlString)
  }

  private static func appleScript(for bundleIdentifier: String) throws -> String {
    switch bundleIdentifier {
    case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
      return """
        tell application id "\(bundleIdentifier)"
          if not (exists front window) then error "No browser window."
          return URL of current tab of front window
        end tell
        """
    case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
      "company.thebrowser.Browser":
      return """
        tell application id "\(bundleIdentifier)"
          if not (exists front window) then error "No browser window."
          return URL of active tab of front window
        end tell
        """
    default:
      throw CodexCoreCLIClient.Error(
        message:
          "The frontmost app is not a supported browser. Use Safari, Chrome, Arc, Brave, or Edge.")
    }
  }
}
