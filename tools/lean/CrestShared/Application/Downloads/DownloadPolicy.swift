import Foundation

enum DownloadLedgerError: Error, Equatable {
    case invalidIdentity, duplicate
    case limitReached(Int)
    case invalidProgress, invalidSample, invalidRetention
    case invalidText(DownloadTextField)
    case unknownPrompt(UUID)
    case answerMismatch(UUID)
}

extension DownloadTextField {
    func validate(_ value: String) throws(DownloadLedgerError) {
        guard !value.isEmpty, value.utf16.count <= maximumLength else { throw .invalidText(self) }
    }
}

extension DownloadTelemetry {
    var isValid: Bool {
        bytesReceived >= 0 && (totalBytes ?? 0) >= 0
            && [bytesPerSecond, estimatedTimeRemaining].allSatisfy { $0 == nil || ($0!.isFinite && $0! >= 0) }
    }

    func stopped(finalByteCount: Int64? = nil, completed: Bool = false) -> Self {
        let bytes = max(bytesReceived, finalByteCount ?? 0)
        return Self(
            bytesReceived: bytes, totalBytes: completed ? bytes : totalBytes,
            bytesPerSecond: nil, estimatedTimeRemaining: nil, isPaused: false)
    }
}

extension DownloadTransferEstimator {
    var isValid: Bool {
        publishedBytes >= 0 && (knownTotalBytes ?? 1) > 0 && (measurementBytes ?? 0) >= 0
            && (measurementBytes == nil) == (measurementUptime == nil)
            && (measurementUptime?.isFinite ?? true)
            && (smoothedBytesPerSecond.map { $0.isFinite && $0 > 0 } ?? true)
    }

    func sample(completed: Int64, total: Int64, fraction: Double, paused: Bool, uptime: Double)
        throws(DownloadLedgerError) -> DownloadProgressReading
    {
        guard isValid, uptime.isFinite else { throw .invalidSample }
        var next = self
        next.publishedBytes = max(publishedBytes, max(completed, 0))
        if !next.totalIsUnreliable, total > 0 {
            if total < next.publishedBytes {
                next.knownTotalBytes = nil
                next.totalIsUnreliable = true
            } else {
                next.knownTotalBytes = max(knownTotalBytes ?? 0, total)
            }
        }
        if paused {
            next.measurementBytes = next.publishedBytes
            next.measurementUptime = uptime
            next.smoothedBytesPerSecond = nil
        } else if let bytes = measurementBytes, let measuredAt = measurementUptime {
            let elapsed = uptime - measuredAt
            if elapsed.isFinite, elapsed >= Self.minimumRateInterval {
                next.measurementBytes = next.publishedBytes
                next.measurementUptime = uptime
                let transferred = next.publishedBytes - bytes
                let instantaneous = Double(transferred) / elapsed
                if transferred > 0, instantaneous.isFinite, instantaneous > 0 {
                    next.smoothedBytesPerSecond =
                        smoothedBytesPerSecond.map {
                            $0 * (1 - Self.smoothingWeight) + instantaneous * Self.smoothingWeight
                        } ?? instantaneous
                }
            }
        } else {
            next.measurementBytes = next.publishedBytes
            next.measurementUptime = uptime
        }
        let progress = next.knownTotalBytes.map { Double(next.publishedBytes) / Double($0) } ?? fraction
        let rate = paused ? nil : next.smoothedBytesPerSecond
        let estimate: Double? = next.knownTotalBytes.flatMap { total in
            guard let rate, rate.isFinite, rate > 0 else { return nil }
            let remaining = max(total - next.publishedBytes, 0)
            guard remaining > 0 else { return nil }
            let value = Double(remaining) / rate
            return value.isFinite && value >= Self.minimumUsefulEstimate && value <= Self.maximumUsefulEstimate
                ? value : nil
        }
        return DownloadProgressReading(
            estimator: next,
            telemetry: DownloadTelemetry(
                bytesReceived: next.publishedBytes, totalBytes: next.knownTotalBytes,
                bytesPerSecond: rate, estimatedTimeRemaining: estimate, isPaused: paused),
            progress: progress.isFinite ? min(max(progress, 0), 1) : 0)
    }
}

extension DownloadRiskFacts {
    private static let codeExtensions: Set<String> = [
        "app", "application", "bat", "bin", "cmd", "com", "command", "csh", "dmg", "exe", "jar", "ksh",
        "mobileconfig", "mpkg", "msi", "pkg", "ps1", "reg", "run", "scpt", "scr", "sh", "tool", "vbs", "workflow",
        "zsh",
    ]
    private static let codeMIMETypes: Set<String> = [
        "application/x-apple-diskimage", "application/x-bat", "application/x-executable", "application/x-mach-binary",
        "application/x-msdownload", "application/x-msi", "application/x-powershell", "application/x-sh",
        "application/x-shellscript",
    ]

    var runsCode: Bool {
        let dot = sanitizedFilename.lastIndex(of: ".")
        let suffix =
            dot.flatMap {
                $0 > sanitizedFilename.startIndex
                    ? String(sanitizedFilename[sanitizedFilename.index(after: $0)...]).lowercased() : nil
            } ?? ""
        return extensionRunsCode || mimeTypeRunsCode || Self.codeExtensions.contains(suffix)
            || mimeType.map { Self.codeMIMETypes.contains($0.lowercased()) } == true
    }

    var hasDeceptiveFilename: Bool {
        suggestedFilename.unicodeScalars.contains {
            $0.value == 0x061C || (0x200B...0x200F).contains($0.value) || (0x202A...0x202E).contains($0.value)
                || (0x2066...0x2069).contains($0.value) || $0.value == 0xFEFF
        }
    }

    func assessment() throws(DownloadLedgerError) -> DownloadRiskAssessment {
        try DownloadTextField.filename.validate(sanitizedFilename)
        guard suggestedFilename.utf16.count <= DownloadTextField.filename.maximumLength * 4 else {
            throw .invalidText(.filename)
        }
        if let mimeType, !mimeType.isEmpty { try DownloadTextField.mimeType.validate(mimeType) }
        var reasons: [DownloadRiskReason] = []
        if runsCode { reasons.append(.executableOrInstaller) }
        if hasDeceptiveFilename { reasons.append(.deceptiveFilename) }
        if runsCode, typesRelated == false { reasons.append(.dangerousTypeMismatch) }
        return DownloadRiskAssessment(sanitizedFilename: sanitizedFilename, reasons: reasons)
    }
}

extension DownloadProgress {
    func answer() throws(DownloadLedgerError) -> DownloadProgressReading {
        try (estimator ?? .initial).sample(
            completed: completedUnitCount, total: totalUnitCount,
            fraction: fractionCompleted, paused: isPaused, uptime: uptime)
    }
}

extension DownloadRisk {
    func answer() throws(DownloadLedgerError) -> DownloadRiskVerdict {
        let assessment = try facts.assessment()
        return DownloadRiskVerdict(
            assessment: assessment,
            requiresConfirmation: assessment.reasons.contains { !isUserInitiated || $0.confirmsUserInitiated })
    }
}

extension AutomaticDownloadCheck {
    var verdict: AutomaticDownloadVerdict {
        var allowance = !userInitiated && hasAllowedAutomaticDownload
        let action: AutomaticDownloadAction
        if userInitiated || userApprovedRetry || savedDecision.grants {
            action = .allow
        } else if savedDecision.denies {
            action = .deny
        } else {
            action = allowance ? .requestPermission : .allow
        }
        if !userInitiated, !userApprovedRetry, savedDecision.asks, action == .allow { allowance = true }
        return AutomaticDownloadVerdict(action: action, hasAllowedAutomaticDownload: allowance)
    }
}
