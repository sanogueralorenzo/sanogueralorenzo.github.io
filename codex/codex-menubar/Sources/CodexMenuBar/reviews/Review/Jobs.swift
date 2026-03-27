import Foundation

actor ReviewJobStore {
  private let paths: AppPaths
  private let fileManager: FileManager
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(paths: AppPaths = AppPaths(), fileManager: FileManager = .default) {
    self.paths = paths
    self.fileManager = fileManager
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  }

  func create(reference: PullRequestReference, pullRequest: String) throws -> ReviewJobSnapshot {
    try paths.ensureExists(fileManager: fileManager)
    let job = ReviewJobSnapshot(
      id: UUID().uuidString,
      pullRequest: pullRequest,
      owner: reference.owner,
      repo: reference.repo,
      number: reference.number,
      url: nil,
      status: .queued,
      currentStep: "queued",
      createdAt: nowUTC(),
      startedAt: nil,
      finishedAt: nil,
      postedComments: 0,
      failedComments: 0,
      failedCommentDetails: [],
      summary: nil,
      error: nil
    )
    try write(snapshot: job)
    try appendEvent(jobID: job.id, event: ReviewJobEvent(timestamp: nowUTC(), kind: "queued", step: "queued", message: "Review job created."))
    return job
  }

  func loadAll() throws -> [ReviewJobSnapshot] {
    try paths.ensureExists(fileManager: fileManager)
    guard fileManager.fileExists(atPath: paths.reviewsRoot.path) else { return [] }
    let entries = try fileManager.contentsOfDirectory(at: paths.reviewsRoot, includingPropertiesForKeys: nil)
    let jobs = try entries
      .filter { $0.hasDirectoryPath }
      .compactMap { directory -> ReviewJobSnapshot? in
        let jobPath = directory.appendingPathComponent("job.json")
        guard fileManager.fileExists(atPath: jobPath.path) else { return nil }
        return try loadJob(at: jobPath)
      }
    return jobs.sorted { $0.createdAt > $1.createdAt }
  }

  func setPullRequestURL(_ url: String, for jobID: String) throws -> ReviewJobSnapshot {
    var snapshot = try load(jobID: jobID)
    snapshot.url = url
    try write(snapshot: snapshot)
    return snapshot
  }

  func setStatus(_ status: ReviewJobStatus, step: String, message: String, for jobID: String) throws -> ReviewJobSnapshot {
    var snapshot = try load(jobID: jobID)
    if snapshot.startedAt == nil && status != .queued {
      snapshot.startedAt = nowUTC()
    }
    snapshot.status = status
    snapshot.currentStep = step
    try write(snapshot: snapshot)
    try appendEvent(jobID: jobID, event: ReviewJobEvent(timestamp: nowUTC(), kind: "step", step: step, message: message))
    return snapshot
  }

  func complete(_ result: ReviewRunResult, step: String, for jobID: String) throws -> ReviewJobSnapshot {
    var snapshot = try load(jobID: jobID)
    snapshot.status = .completed
    snapshot.currentStep = step
    snapshot.finishedAt = nowUTC()
    snapshot.postedComments = result.postedComments
    snapshot.failedComments = result.failedComments
    snapshot.failedCommentDetails = result.failedCommentDetails
    snapshot.summary = result.summary
    snapshot.error = nil
    snapshot.url = result.url
    try write(snapshot: snapshot)
    try appendEvent(jobID: jobID, event: ReviewJobEvent(timestamp: nowUTC(), kind: "completed", step: step, message: "Review job completed."))
    return snapshot
  }

  func fail(_ error: Error, step: String, for jobID: String) throws -> ReviewJobSnapshot {
    var snapshot = try load(jobID: jobID)
    snapshot.status = .failed
    snapshot.currentStep = step
    if snapshot.startedAt == nil {
      snapshot.startedAt = nowUTC()
    }
    snapshot.finishedAt = nowUTC()
    snapshot.error = error.localizedDescription
    try write(snapshot: snapshot)
    try appendEvent(jobID: jobID, event: ReviewJobEvent(timestamp: nowUTC(), kind: "failed", step: step, message: error.localizedDescription))
    return snapshot
  }

  func clearFinished() throws {
    let jobs = try loadAll().filter { $0.isFinished }
    for job in jobs {
      try? fileManager.removeItem(at: jobDirectory(jobID: job.id))
    }
  }

  private func load(jobID: String) throws -> ReviewJobSnapshot {
    try loadJob(at: jobDirectory(jobID: jobID).appendingPathComponent("job.json"))
  }

  private func loadJob(at jobPath: URL) throws -> ReviewJobSnapshot {
    let data = try Data(contentsOf: jobPath)
    return try decoder.decode(ReviewJobSnapshot.self, from: data)
  }

  private func write(snapshot: ReviewJobSnapshot) throws {
    let directory = jobDirectory(jobID: snapshot.id)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try encoder.encode(snapshot)
    try data.write(to: directory.appendingPathComponent("job.json"), options: .atomic)
  }

  private func appendEvent(jobID: String, event: ReviewJobEvent) throws {
    let directory = jobDirectory(jobID: jobID)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("events.jsonl")
    let payload = try JSONEncoder().encode(event)
    if fileManager.fileExists(atPath: file.path) {
      let handle = try FileHandle(forWritingTo: file)
      defer { try? handle.close() }
      try handle.seekToEnd()
      handle.write(payload)
      handle.write(Data("\n".utf8))
    } else {
      try (payload + Data("\n".utf8)).write(to: file, options: .atomic)
    }
  }

  private func jobDirectory(jobID: String) -> URL {
    paths.reviewsRoot.appendingPathComponent(jobID, isDirectory: true)
  }
}

func nowUTC() -> String {
  ISO8601DateFormatter().string(from: .now)
}
