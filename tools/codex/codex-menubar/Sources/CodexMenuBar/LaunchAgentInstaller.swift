import Foundation

struct LaunchAgentInstaller {
  private static let preferredAppExecutablePath =
    "/Applications/Codex Menu Bar.app/Contents/MacOS/CodexMenuBar"

  static func ensureLaunchAgentPlistExists() throws {
    let fileManager = FileManager.default
    let home = fileManager.homeDirectoryForCurrentUser
    let launchAgentsDirectory =
      home
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("LaunchAgents", isDirectory: true)
    try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

    let label = Bundle.main.bundleIdentifier ?? "io.github.sanogueralorenzo.codex.menubar"
    let executablePath = resolveExecutablePath(fileManager: fileManager)
    guard let executablePath else {
      return
    }

    let plistURL = launchAgentsDirectory.appendingPathComponent("\(label).plist")
    let plistContents = makePlistContents(label: label, executablePath: executablePath)

    let existingContents = (try? String(contentsOf: plistURL, encoding: .utf8)) ?? ""
    if existingContents != plistContents {
      try plistContents.write(to: plistURL, atomically: true, encoding: .utf8)
    }
  }

  private static func resolveExecutablePath(fileManager: FileManager) -> String? {
    if fileManager.isExecutableFile(atPath: preferredAppExecutablePath) {
      return preferredAppExecutablePath
    }
    return nil
  }

  private static func makePlistContents(label: String, executablePath: String) -> String {
    let escapedLabel = xmlEscaped(label)
    let escapedExecutable = xmlEscaped(executablePath)
    let stdoutPath = xmlEscaped("/tmp/codex-menu-menubar.out.log")
    let stderrPath = xmlEscaped("/tmp/codex-menu-menubar.err.log")

    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>\(escapedLabel)</string>
        <key>ProgramArguments</key>
        <array>
          <string>\(escapedExecutable)</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <false/>
        <key>LimitLoadToSessionType</key>
        <array>
          <string>Aqua</string>
        </array>
        <key>StandardOutPath</key>
        <string>\(stdoutPath)</string>
        <key>StandardErrorPath</key>
        <string>\(stderrPath)</string>
      </dict>
      </plist>
      """
  }

  private static func xmlEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}
