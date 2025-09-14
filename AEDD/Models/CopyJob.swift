import Foundation

enum JobState: String, CaseIterable, Codable {
    case pending = "Pending"
    case running = "Running"
    case completed = "Done"
    case failed = "Failed"
    case cancelled = "Cancelled"

    var isActive: Bool {
        return self == .running
    }

    var isFinished: Bool {
        return [.completed, .failed, .cancelled].contains(self)
    }
}

struct CopyJob: Identifiable, Codable, Equatable {
    let id = UUID()
    let serverHost: String
    let sources: [URL]
    let destination: URL
    let rsyncArgs: [String]
    let createdAt: Date

    var state: JobState = .pending
    var progress: Double = 0.0
    var startedAt: Date?
    var completedAt: Date?
    var error: String?
    var logURL: URL?
    var processID: Int32?

    var displayName: String {
        let sourceCount = sources.count
        let sourceName = sourceCount == 1 ? sources.first?.lastPathComponent ?? "Unknown" : "\(sourceCount) folders"
        return "\(serverHost) → \(sourceName)"
    }

    var elapsedTime: TimeInterval {
        guard let startedAt = startedAt else { return 0 }
        let endTime = completedAt ?? Date()
        return endTime.timeIntervalSince(startedAt)
    }

    var formattedElapsedTime: String {
        let elapsed = elapsedTime
        if elapsed < 60 {
            return String(format: "%.0fs", elapsed)
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            let seconds = Int(elapsed.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(elapsed / 3600)
            let minutes = Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }

    static func == (lhs: CopyJob, rhs: CopyJob) -> Bool {
        return lhs.id == rhs.id
    }
}

extension CopyJob {
    func generateLogURL() -> URL {
        let logsDir = LogManager.shared.logsDirectory
        let timestamp = DateFormatter.logFormatter.string(from: createdAt)
        let filename = "\(id.uuidString.prefix(8))_\(timestamp).log"
        return logsDir.appendingPathComponent(filename)
    }
}

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}