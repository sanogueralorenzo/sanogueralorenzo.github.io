import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

struct MobileDownloadRiskConfirmationRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let assessment: DownloadRiskAssessment
    /// The host the file came from, when known.
    let sourceHost: String?
    let spaceName: String
    /// The profile the download belongs to. Only windows browsing it present
    /// the request.
    let profileID: UUID

    init(
        id: UUID = UUID(),
        assessment: DownloadRiskAssessment,
        sourceHost: String?,
        spaceName: String,
        profileID: UUID
    ) {
        self.id = id
        self.assessment = assessment
        self.sourceHost = sourceHost
        self.spaceName = spaceName
        self.profileID = profileID
    }

    var title: String {
        "Download “\(assessment.sanitizedFilename)”?"
    }

    var sourceLabel: String? {
        sourceHost
    }

    var message: String {
        var paragraphs = assessment.reasons.map { String(localized: $0.message) }
        if let sourceLabel {
            paragraphs.append("Source: \(sourceLabel)")
        }
        paragraphs.append("This request belongs only to the \(spaceName) Space.")
        paragraphs.append("Open this file only if you trust its source.")
        return paragraphs.joined(separator: "\n\n")
    }
}
