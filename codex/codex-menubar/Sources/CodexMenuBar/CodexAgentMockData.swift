import Foundation

// MOCK DATA ONLY
// This is temporary placeholder data for Codex Agent menu rendering.
// Replace with real task source + actions when backend integration is ready.
struct CodexAgentMockTask {
    enum Status: String {
        case planning = "Planning"
        case coding = "Coding"
        case review = "Review"
        case waiting = "Waiting"
        case completed = "Completed"
        case failed = "Failed"
    }

    let ticket: String
    let status: Status
    let isPaused: Bool
}

enum CodexAgentMockData {
    static let runningTasks: [CodexAgentMockTask] = [
        CodexAgentMockTask(ticket: "TS-1234", status: .coding, isPaused: false),
        CodexAgentMockTask(ticket: "TS-1235", status: .review, isPaused: false),
        CodexAgentMockTask(ticket: "TS-1236", status: .waiting, isPaused: true)
    ]

    static let recentTasks: [CodexAgentMockTask] = [
        CodexAgentMockTask(ticket: "TS-1231", status: .completed, isPaused: false),
        CodexAgentMockTask(ticket: "TS-1232", status: .completed, isPaused: false),
        CodexAgentMockTask(ticket: "TS-1233", status: .failed, isPaused: false)
    ]
}
