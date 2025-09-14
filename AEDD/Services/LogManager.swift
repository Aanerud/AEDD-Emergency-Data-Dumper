import Foundation
import os.log
import AppKit

class LogManager {
    static let shared = LogManager()

    private let logger = Logger(subsystem: "no.uhoert.aedd", category: "main")
    private let logRetentionDays: TimeInterval = 30 * 24 * 60 * 60
    private let logQueue = DispatchQueue(label: "logQueue", qos: .utility)

    private lazy var currentLogFile: URL = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: Date())
        return logsDirectory.appendingPathComponent("aedd-\(dateString).log")
    }()

    private lazy var logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    lazy var logsDirectory: URL = {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let logsPath = homeDirectory.appendingPathComponent("Library/Logs/Aanerud-EMC-Emergency-Dumper")
        return logsPath
    }()

    private init() {}

    func setup() {
        createLogsDirectory()
        cleanupOldLogs()
    }

    func log(_ message: String, level: OSLogType = .default) {
        let timestamp = logFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"

        // Log to system console
        logger.log(level: level, "\(message)")

        // Also write to file
        writeToFile(logMessage)
    }

    func logError(_ message: String) {
        let timestamp = logFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] ERROR: \(message)"

        logger.error("\(message)")
        writeToFile(logMessage)
    }

    func logDebug(_ message: String) {
        let timestamp = logFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] DEBUG: \(message)"

        logger.debug("\(message)")
        writeToFile(logMessage)
    }

    func logInfo(_ message: String) {
        let timestamp = logFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] INFO: \(message)"

        logger.info("\(message)")
        writeToFile(logMessage)
    }

    func openLogsFolder() {
        NSWorkspace.shared.open(logsDirectory)
    }

    private func writeToFile(_ message: String) {
        logQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let logLine = message + "\n"
                let logData = logLine.data(using: .utf8) ?? Data()

                if FileManager.default.fileExists(atPath: self.currentLogFile.path) {
                    // Append to existing file
                    let fileHandle = try FileHandle(forWritingTo: self.currentLogFile)
                    defer { fileHandle.closeFile() }
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(logData)
                } else {
                    // Create new file
                    try logData.write(to: self.currentLogFile)
                }
            } catch {
                // If file writing fails, at least log to console
                print("LogManager: Failed to write to log file: \(error)")
            }
        }
    }

    func createJobLogFile(for jobId: UUID) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "\(jobId.uuidString.prefix(8))_\(timestamp).log"
        return logsDirectory.appendingPathComponent(filename)
    }

    private func createLogsDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: logsDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            logger.error("Failed to create logs directory: \(error.localizedDescription)")
        }
    }

    private func cleanupOldLogs() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: logsDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: []
            )

            let cutoffDate = Date().addingTimeInterval(-logRetentionDays)

            for fileURL in contents {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
                    if let creationDate = resourceValues.creationDate,
                       creationDate < cutoffDate {
                        try FileManager.default.removeItem(at: fileURL)
                        logger.debug("Deleted old log file: \(fileURL.lastPathComponent)")
                    }
                } catch {
                    logger.error("Failed to check/delete log file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("Failed to cleanup old logs: \(error.localizedDescription)")
        }
    }

    func archiveLogs() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let archiveName = "AEDD-Logs-\(formatter.string(from: Date())).zip"
        let tempDirectory = FileManager.default.temporaryDirectory
        let archiveURL = tempDirectory.appendingPathComponent(archiveName)

        do {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            task.arguments = ["-r", archiveURL.path, logsDirectory.path]

            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                return archiveURL
            } else {
                logger.error("Failed to create logs archive")
                return nil
            }
        } catch {
            logger.error("Failed to create logs archive: \(error.localizedDescription)")
            return nil
        }
    }

    func getLogFiles() -> [URL] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: logsDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: []
            )

            return contents
                .filter { $0.pathExtension == "log" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            logger.error("Failed to get log files: \(error.localizedDescription)")
            return []
        }
    }

    func deleteLogFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            logger.info("Deleted log file: \(url.lastPathComponent)")
        } catch {
            logger.error("Failed to delete log file: \(error.localizedDescription)")
        }
    }

    func getLogFileSize() -> String {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: logsDirectory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: []
            )

            let totalSize = contents.reduce(0) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return total + size
            }

            return ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
        } catch {
            return "Unknown"
        }
    }
}

extension LogManager {
    func logJobStart(_ jobId: String, displayName: String) {
        logInfo("Starting job \(jobId): \(displayName)")
    }

    func logJobComplete(_ jobId: String, displayName: String, result: Result<Void, Error>) {
        switch result {
        case .success:
            logInfo("Completed job \(jobId): \(displayName)")
        case .failure(let error):
            logError("Failed job \(jobId): \(displayName) - \(error.localizedDescription)")
        }
    }

    func logSMBConnection(_ host: String, success: Bool) {
        if success {
            logInfo("Successfully connected to SMB server: \(host)")
        } else {
            logError("Failed to connect to SMB server: \(host)")
        }
    }

    func logMountOperation(_ share: String, host: String, success: Bool) {
        if success {
            logInfo("Successfully mounted share: \(share) from \(host)")
        } else {
            logError("Failed to mount share: \(share) from \(host)")
        }
    }
}