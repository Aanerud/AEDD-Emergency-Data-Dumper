import Foundation
import Combine

enum RsyncError: LocalizedError {
    case processLaunchFailed
    case cancelled
    case failed(exitCode: Int32, message: String)
    case logFileCreationFailed

    var errorDescription: String? {
        switch self {
        case .processLaunchFailed:
            return "Failed to start rsync process"
        case .cancelled:
            return "Operation was cancelled"
        case .failed(let exitCode, let message):
            if [23, 24].contains(exitCode) {
                return "Completed with minor file I/O errors (exit code \(exitCode))"
            } else {
                return "Rsync failed with exit code \(exitCode): \(message)"
            }
        case .logFileCreationFailed:
            return "Failed to create log file"
        }
    }
}

class RsyncOperation: Operation, @unchecked Sendable {
    private let job: CopyJob
    private var process: Process?
    private let progressSubject = PassthroughSubject<Double, Never>()
    private let completionSubject = PassthroughSubject<Result<Void, Error>, Never>()

    var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    var completionPublisher: AnyPublisher<Result<Void, Error>, Never> {
        completionSubject.eraseToAnyPublisher()
    }

    init(job: CopyJob) {
        self.job = job
        super.init()
    }

    override func main() {
        guard !isCancelled else {
            completionSubject.send(.failure(RsyncError.cancelled))
            return
        }

        do {
            try executeRsyncJob()
        } catch {
            completionSubject.send(.failure(error))
        }
    }

    override func cancel() {
        super.cancel()

        if let process = process, process.isRunning {
            process.interrupt()

            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if process.isRunning {
                    process.terminate()

                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                }
            }
        }
    }

    private func executeRsyncJob() throws {
        guard let logURL = job.logURL else {
            throw RsyncError.logFileCreationFailed
        }

        try createLogFile(at: logURL)

        for sourceURL in job.sources {
            guard !isCancelled else {
                throw RsyncError.cancelled
            }

            try copySource(sourceURL, to: job.destination, logURL: logURL)
        }

        completionSubject.send(.success(()))
    }

    private func createLogFile(at url: URL) throws {
        let logDirectory = url.deletingLastPathComponent()

        if !FileManager.default.fileExists(atPath: logDirectory.path) {
            try FileManager.default.createDirectory(
                at: logDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let initialLogContent = """
        AEDD Copy Job Log
        Job ID: \(job.id)
        Created: \(job.createdAt)
        Server: \(job.serverHost)
        Sources: \(job.sources.map { $0.path }.joined(separator: ", "))
        Destination: \(job.destination.path)
        Args: \(job.rsyncArgs.joined(separator: " "))

        ==========================================

        """.data(using: .utf8) ?? Data()

        try initialLogContent.write(to: url)
    }

    private func copySource(_ source: URL, to destination: URL, logURL: URL) throws {
        let destinationPath = destination.appendingPathComponent(source.lastPathComponent)

        try FileManager.default.createDirectory(
            at: destinationPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let rsyncPath = getRsyncPath()
        let sourcePath = source.path.hasSuffix("/") ? source.path : source.path + "/"

        var arguments = job.rsyncArgs
        arguments.append(contentsOf: [sourcePath, destinationPath.path])

        let process = Process()
        self.process = process

        process.executableURL = URL(fileURLWithPath: rsyncPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let logFileHandle = try FileHandle(forWritingTo: logURL)

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        logFileHandle.seekToEndOfFile()

        let outputTask = Task {
            do {
                for try await line in outputPipe.fileHandleForReading.bytes.lines {
                    guard !Task.isCancelled else { break }

                    if let data = (line + "\n").data(using: .utf8) {
                        logFileHandle.write(data)
                    }

                    parseProgressFromLine(line)
                }
            } catch {
                // Handle error if needed
            }
        }

        let errorTask = Task {
            do {
                for try await line in errorPipe.fileHandleForReading.bytes.lines {
                    guard !Task.isCancelled else { break }

                    if let data = (line + "\n").data(using: .utf8) {
                        logFileHandle.write(data)
                    }

                    // Also parse progress from stderr since rsync outputs progress there
                    parseProgressFromLine(line)
                }
            } catch {
                // Handle error if needed
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            outputTask.cancel()
            errorTask.cancel()
            logFileHandle.closeFile()

            let exitCode = process.terminationStatus

            if exitCode == 0 {
                return
            } else if [23, 24].contains(exitCode) {
                return
            } else {
                let errorMessage = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
                throw RsyncError.failed(exitCode: exitCode, message: errorMessage)
            }

        } catch {
            outputTask.cancel()
            errorTask.cancel()
            try? logFileHandle.close()
            throw RsyncError.processLaunchFailed
        }
    }

    private func parseProgressFromLine(_ line: String) {
        // Handle percentage progress (from --progress flag)
        if line.contains("%") {
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            for component in components {
                if component.hasSuffix("%") {
                    let percentString = String(component.dropLast())
                    if let percent = Double(percentString) {
                        let progress = percent / 100.0
                        progressSubject.send(progress)
                        return
                    }
                }
            }
        }

        // Handle file count progress (to-chk= format)
        if line.contains("to-chk=") || line.contains("to-check=") {
            let regex = try? NSRegularExpression(pattern: "to-chk=([0-9]+)/([0-9]+)", options: [])
            if let match = regex?.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                let remaining = Double((line as NSString).substring(with: match.range(at: 1))) ?? 0
                let total = Double((line as NSString).substring(with: match.range(at: 2))) ?? 1
                let progress = max(0, (total - remaining) / total)
                progressSubject.send(progress)
                return
            }
        }

        // Handle building file list progress
        if line.contains("files...") {
            if let regex = try? NSRegularExpression(pattern: "([0-9,]+) files", options: []),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                let fileCountString = (line as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                if let fileCount = Double(fileCountString), fileCount > 0 {
                    // Show a small progress for file list building (5% max)
                    let buildProgress = min(0.05, fileCount / 10000.0 * 0.05)
                    progressSubject.send(buildProgress)
                }
            }
        }
    }

    private func getRsyncPath() -> String {
        let homebrewRsync = "/opt/homebrew/bin/rsync"
        let systemRsync = "/usr/bin/rsync"

        if FileManager.default.fileExists(atPath: homebrewRsync) {
            return homebrewRsync
        } else {
            return systemRsync
        }
    }
}