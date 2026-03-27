import Foundation

struct AppPaths {
  let root: URL
  let configFile: URL
  let activityFile: URL
  let reviewsRoot: URL
  let reposRoot: URL
  let worktreesRoot: URL

  init(fileManager: FileManager = .default) {
    let appSupport = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
      .appendingPathComponent("GitHub PR Reviews", isDirectory: true)
    root = appSupport
    configFile = appSupport.appendingPathComponent("config.json")
    activityFile = appSupport.appendingPathComponent("activity.json")
    reviewsRoot = appSupport.appendingPathComponent("reviews", isDirectory: true)
    reposRoot = appSupport.appendingPathComponent("repos", isDirectory: true)
    worktreesRoot = appSupport.appendingPathComponent("worktrees", isDirectory: true)
  }

  func ensureExists(fileManager: FileManager = .default) throws {
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: reviewsRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: reposRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: worktreesRoot, withIntermediateDirectories: true)
  }
}

actor ConfigStore {
  private let paths: AppPaths
  private let fileManager: FileManager
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(paths: AppPaths = AppPaths(), fileManager: FileManager = .default) {
    self.paths = paths
    self.fileManager = fileManager
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  }

  func load() throws -> AppConfig {
    try paths.ensureExists(fileManager: fileManager)
    guard fileManager.fileExists(atPath: paths.configFile.path) else {
      try save(AppConfig.default)
      return .default
    }
    return try decoder.decode(AppConfig.self, from: Data(contentsOf: paths.configFile))
  }

  func save(_ config: AppConfig) throws {
    try paths.ensureExists(fileManager: fileManager)
    let data = try encoder.encode(config)
    try data.write(to: paths.configFile, options: .atomic)
  }
}

actor ActivityStore {
  private let paths: AppPaths
  private let fileManager: FileManager
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(paths: AppPaths = AppPaths(), fileManager: FileManager = .default) {
    self.paths = paths
    self.fileManager = fileManager
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  }

  func load() throws -> [String: ActivityRecord] {
    try paths.ensureExists(fileManager: fileManager)
    guard fileManager.fileExists(atPath: paths.activityFile.path) else {
      return [:]
    }
    return try decoder.decode([String: ActivityRecord].self, from: Data(contentsOf: paths.activityFile))
  }

  func upsert(_ record: ActivityRecord) throws -> [String: ActivityRecord] {
    var current = try load()
    current[record.pullRequestURL] = record
    try persist(current)
    return current
  }

  func clearFinished() throws -> [String: ActivityRecord] {
    let current = try load().filter { _, value in value.status == .running }
    try persist(current)
    return current
  }

  private func persist(_ records: [String: ActivityRecord]) throws {
    try paths.ensureExists(fileManager: fileManager)
    let data = try encoder.encode(records)
    try data.write(to: paths.activityFile, options: .atomic)
  }
}
