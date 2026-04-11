import Foundation

enum CLIProcessEnvironment {
  static func make(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String]
  {
    var env = base
    var mergedPaths: [String] = []

    let requiredPaths = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin",
    ]

    for path in requiredPaths {
      appendUnique(path: path, to: &mergedPaths)
    }

    let existingPath = env["PATH"] ?? ""
    for token in existingPath.split(separator: ":").map(String.init) {
      appendUnique(path: token, to: &mergedPaths)
    }

    env["PATH"] = mergedPaths.joined(separator: ":")
    if env["HOME"] == nil || env["HOME"]?.isEmpty == true {
      env["HOME"] = NSHomeDirectory()
    }
    return env
  }

  private static func appendUnique(path: String, to paths: inout [String]) {
    guard !path.isEmpty else {
      return
    }
    if !paths.contains(path) {
      paths.append(path)
    }
  }
}
