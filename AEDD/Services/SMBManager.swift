import Foundation
import Combine
import AppKit
import Security

@MainActor
class SMBManager: ObservableObject {
    @Published var availableShares: [SMBShare] = []
    @Published var mountedShares: [SMBShare] = []
    @Published var isConnecting = false
    @Published var connectionError: SMBConnectionError?

    private var storedCredentials: SMBCredentials?

    nonisolated private let keychainService = KeychainService()

    func connect(to host: String, credentials: SMBCredentials) async {
        await MainActor.run {
            isConnecting = true
            connectionError = nil
        }

        LogManager.shared.logInfo("=== SMB CONNECTION ATTEMPT STARTED ===")
        LogManager.shared.logInfo("Target server: \(host)")
        LogManager.shared.logInfo("Username: \(credentials.username)")

        // Trigger local network permission prompt by calling NSProcessInfo.hostName
        await triggerLocalNetworkPermission()

        // Step 1: Network diagnostics
        await performNetworkDiagnostics(host: host)

        // Step 2: SMB-specific diagnostics
        await performSMBDiagnostics(host: host)

        do {
            if credentials.saveToKeychain {
                try await keychainService.savePassword(credentials.password, for: credentials.keychainAccount, host: host)
                LogManager.shared.logInfo("Credentials saved to keychain successfully")
            }

            let shares = try await enumerateSharesWithRetry(host: host, credentials: credentials)
            let validShares = shares.filter { $0.isValidForMounting }

            await MainActor.run {
                self.availableShares = validShares
                self.connectionError = nil
                self.storedCredentials = credentials
            }

            LogManager.shared.logInfo("Successfully enumerated \(shares.count) shares from \(host), \(validShares.count) valid for mounting")
            LogManager.shared.logSMBConnection(host, success: true)
            LogManager.shared.logInfo("=== SMB CONNECTION SUCCESSFUL ===")

        } catch {
            let smbError = error as? SMBConnectionError ?? .networkError

            await MainActor.run {
                self.connectionError = smbError
                self.availableShares = []
            }

            LogManager.shared.logError("Failed to connect to SMB server \(host): \(error.localizedDescription)")
            LogManager.shared.logSMBConnection(host, success: false)
            LogManager.shared.logError("=== SMB CONNECTION FAILED ===")
        }

        await MainActor.run {
            isConnecting = false
        }
    }

    func mountShares(_ shares: [SMBShare]) async throws {
        guard let credentials = storedCredentials else {
            throw SMBConnectionError.noCredentialsStored
        }

        try await unmountConflictingMounts(for: shares.first?.host ?? "")

        for share in shares {
            try await mountShare(share, credentials: credentials)
            openInFinder(share.mountPath)
        }

        refreshMountedShares()
    }

    func unmountAll() async {
        let mountsToUnmount = mountedShares
        for share in mountsToUnmount {
            try? await unmountShare(share)
        }
        refreshMountedShares()
    }

    private func enumerateShares(host: String, credentials: SMBCredentials) async throws -> [SMBShare] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let shares = try self.performShareEnumeration(host: host, credentials: credentials)
                    continuation.resume(returning: shares)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func enumerateSharesWithRetry(host: String, credentials: SMBCredentials) async throws -> [SMBShare] {
        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            LogManager.shared.logInfo("SMB connection attempt \(attempt) of \(maxAttempts)")

            do {
                // Try different smbutil command formats
                return try await tryDifferentSMBFormats(host: host, credentials: credentials, attempt: attempt)
            } catch {
                lastError = error
                LogManager.shared.logError("Attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt < maxAttempts {
                    LogManager.shared.logInfo("Waiting 2 seconds before retry...")
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                }
            }
        }

        throw lastError ?? SMBConnectionError.shareEnumerationFailed
    }

    private func tryDifferentSMBFormats(host: String, credentials: SMBCredentials, attempt: Int) async throws -> [SMBShare] {
        switch attempt {
        case 1:
            // Primary format: //user@host (username only, no domain)
            LogManager.shared.logInfo("Trying username-only format: //\(credentials.formattedUsername)@\(host)")
            return try await enumerateShares(host: host, credentials: credentials)

        case 2:
            // Fallback: try with original username if it was different
            if credentials.formattedUsername != credentials.username {
                let altCredentials = SMBCredentials(username: credentials.username, password: credentials.password, saveToKeychain: false)
                LogManager.shared.logInfo("Trying original username format: //\(credentials.username)@\(host)")
                return try await enumerateShares(host: host, credentials: altCredentials)
            } else {
                throw SMBConnectionError.shareEnumerationFailed
            }

        case 3:
            // Final attempt with guest access
            LogManager.shared.logInfo("Trying guest access to \(host)")
            return try await enumerateSharesAsGuest(host: host)

        default:
            throw SMBConnectionError.shareEnumerationFailed
        }
    }

    private func enumerateSharesAsGuest(host: String) async throws -> [SMBShare] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let shares = try self.performGuestShareEnumeration(host: host)
                    continuation.resume(returning: shares)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated func performShareEnumeration(host: String, credentials: SMBCredentials) throws -> [SMBShare] {
        // Try direct approach first (bypasses TTY issues), fallback to expect if needed
        do {
            return try performShareEnumerationDirect(host: host, credentials: credentials)
        } catch {
            LogManager.shared.logInfo("Direct approach failed, trying expect script: \(error)")
            return try performShareEnumerationWithExpect(host: host, credentials: credentials)
        }
    }

    private nonisolated func performShareEnumerationDirect(host: String, credentials: SMBCredentials) throws -> [SMBShare] {
        LogManager.shared.logInfo("Attempting direct SMB enumeration via keychain-stored mount")

        // Try mounting a test connection first to validate credentials and get shares
        // This approach uses the mount command which can read from keychain if we set it up
        let testMountPoint = URL(fileURLWithPath: "/tmp/aedd_test_\(UUID().uuidString.prefix(8))")

        do {
            // Create temporary mount point
            try FileManager.default.createDirectory(at: testMountPoint, withIntermediateDirectories: true)
            LogManager.shared.logInfo("Created test mount point: \(testMountPoint.path)")

            // Try to connect using mount_smbfs with minimal share (often IPC$ or similar)
            // First, let's try to query the server without mounting by using a different approach
            return try queryServerSharesWithSMBUtil(host: host, credentials: credentials)
        } catch {
            // Clean up test mount point
            try? FileManager.default.removeItem(at: testMountPoint)
            throw error
        }
    }

    private nonisolated func queryServerSharesWithSMBUtil(host: String, credentials: SMBCredentials) throws -> [SMBShare] {
        LogManager.shared.logInfo("Querying SMB shares using smbutil with process environment")

        // Use a different approach - pass credentials via stdin instead of expecting TTY
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
        process.arguments = ["view", "//\(credentials.formattedUsername)@\(host)"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set environment to avoid TTY requirements
        var environment = ProcessInfo.processInfo.environment
        environment["SMB_USER"] = credentials.formattedUsername
        environment["SMB_PASSWORD"] = credentials.password
        environment["TERM"] = "dumb" // Disable terminal features
        environment["HOME"] = FileManager.default.temporaryDirectory.path
        process.environment = environment

        LogManager.shared.logInfo("Starting direct smbutil process with environment setup")

        do {
            try process.run()

            // Send password via stdin
            if let passwordData = "\(credentials.password)\n".data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(passwordData)
                inputPipe.fileHandleForWriting.closeFile()
            }

            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            LogManager.shared.logInfo("Direct smbutil completed with exit code: \(process.terminationStatus)")
            LogManager.shared.logInfo("Direct output: \(output)")
            if !errorOutput.isEmpty {
                LogManager.shared.logInfo("Direct stderr: \(errorOutput)")
            }

            if process.terminationStatus == 0 {
                let shares = parseSharesOutput(output, host: host)
                LogManager.shared.logInfo("Found \(shares.count) shares via direct method")
                return shares
            } else {
                throw SMBConnectionError.shareEnumerationFailed
            }
        } catch {
            LogManager.shared.logError("Direct smbutil execution error: \(error)")
            throw SMBConnectionError.shareEnumerationFailed
        }
    }

    private nonisolated func performShareEnumerationWithExpect(host: String, credentials: SMBCredentials) throws -> [SMBShare] {
        // Create temporary expect script
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("smbutil_expect_\(UUID().uuidString.prefix(8)).exp")

        let expectScript = """
#!/usr/bin/expect -f
set timeout 30
log_user 1
spawn smbutil view //\(credentials.formattedUsername)@\(host)
expect {
    "Password for *:" {
        send "\(credentials.password)\\r"
        exp_continue
    }
    eof
}
"""

        let smbURL = "//\(credentials.formattedUsername)@\(host)"
        LogManager.shared.logInfo("Executing smbutil via expect script: smbutil view \(smbURL)")
        LogManager.shared.logDebug("Using expect script for TTY emulation")

        do {
            // Write expect script to temp file
            try expectScript.write(to: scriptPath, atomically: true, encoding: .utf8)
            LogManager.shared.logInfo("📝 Expect script written to: \(scriptPath.path)")

            // Make script executable
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", scriptPath.path]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()
            LogManager.shared.logInfo("🔧 Script made executable with chmod")

            // Debug: Print the exact script content
            LogManager.shared.logInfo("📄 Expect script content:")
            LogManager.shared.logInfo(expectScript)

            // Try running the script with full environment
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
            process.arguments = [scriptPath.path]

            // Set environment variables like in terminal
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
            env["USER"] = NSUserName()
            env["HOME"] = NSHomeDirectory()
            env["SHELL"] = "/bin/zsh"
            process.environment = env

            LogManager.shared.logInfo("🌍 Process environment set: PATH=\(env["PATH"] ?? ""), USER=\(env["USER"] ?? ""), HOME=\(env["HOME"] ?? "")")

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            LogManager.shared.logInfo("🚀 Starting expect process...")
            try process.run()
            process.waitUntilExit()
            LogManager.shared.logInfo("✅ Expect process completed")

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            // Clean up temp script
            try? FileManager.default.removeItem(at: scriptPath)

            LogManager.shared.logInfo("expect script completed with exit code: \(process.terminationStatus)")
            LogManager.shared.logInfo("expect output length: \(output.count) characters")
            LogManager.shared.logInfo("expect output: \(output)")
            if !errorOutput.isEmpty {
                LogManager.shared.logError("expect stderr: \(errorOutput)")
            }

            // Debug: Show each line of output
            let outputLines = output.components(separatedBy: .newlines)
            LogManager.shared.logInfo("expect output has \(outputLines.count) lines:")
            for (index, line) in outputLines.enumerated() {
                LogManager.shared.logInfo("Line \(index): '\(line)'")
            }

            guard process.terminationStatus == 0 else {
                LogManager.shared.logError("expect script failed for \(host) with exit code \(process.terminationStatus)")
                throw SMBConnectionError.shareEnumerationFailed
            }

            let shares = parseSharesOutput(output, host: host)
            LogManager.shared.logInfo("Found \(shares.count) shares via expect: \(shares.map { $0.name }.joined(separator: ", "))")

            // Debug: Show what parseSharesOutput is doing
            LogManager.shared.logInfo("=== PARSING DEBUG ===")
            LogManager.shared.logInfo("Raw output sent to parser: '\(output)'")
            LogManager.shared.logInfo("Parser found \(shares.count) valid shares")

            return shares

        } catch let error as SMBConnectionError {
            // Clean up temp script on error
            try? FileManager.default.removeItem(at: scriptPath)
            throw error
        } catch {
            // Clean up temp script on error
            try? FileManager.default.removeItem(at: scriptPath)
            LogManager.shared.logError("expect script execution error: \(error)")
            throw SMBConnectionError.shareEnumerationFailed
        }
    }

    private nonisolated func performGuestShareEnumeration(host: String) throws -> [SMBShare] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
        process.arguments = ["view", "-G", "//\(host)"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        LogManager.shared.logInfo("Executing smbutil guest access: smbutil view -G //\(host)")

        do {
            try process.run()

            // Set a reasonable timeout
            let timeout = DispatchTime.now() + .seconds(30)
            let semaphore = DispatchSemaphore(value: 0)

            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                semaphore.signal()
            }

            let timeoutResult = semaphore.wait(timeout: timeout)
            if timeoutResult == .timedOut {
                LogManager.shared.logError("smbutil guest command timed out after 30 seconds")
                process.terminate()
                throw SMBConnectionError.shareEnumerationFailed
            }

            LogManager.shared.logInfo("smbutil guest process completed with exit code: \(process.terminationStatus)")

            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let stdOutput = String(data: outputData, encoding: .utf8) ?? ""

                LogManager.shared.logError("smbutil guest failed for \(host) with exit code \(process.terminationStatus)")
                LogManager.shared.logError("smbutil guest stderr: \(errorOutput)")
                LogManager.shared.logError("smbutil guest stdout: \(stdOutput)")

                throw SMBConnectionError.shareEnumerationFailed
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""

            LogManager.shared.logInfo("smbutil guest output: \(output)")
            let shares = parseSharesOutput(output, host: host)
            LogManager.shared.logInfo("Found \(shares.count) shares with guest access: \(shares.map { $0.name }.joined(separator: ", "))")

            return shares

        } catch let error as SMBConnectionError {
            LogManager.shared.logError("Guest connection error: \(error)")
            throw error
        } catch {
            LogManager.shared.logError("smbutil guest execution error: \(error)")
            throw SMBConnectionError.shareEnumerationFailed
        }
    }

    private nonisolated func parseSharesOutput(_ output: String, host: String) -> [SMBShare] {
        var shares: [SMBShare] = []

        LogManager.shared.logInfo("=== PARSE SHARES DEBUG START ===")
        LogManager.shared.logInfo("Input output length: \(output.count)")
        LogManager.shared.logInfo("Input output: '\(output)'")

        let lines = output.components(separatedBy: .newlines)
        LogManager.shared.logInfo("Split into \(lines.count) lines")

        for (lineIndex, line) in lines.enumerated() {
            LogManager.shared.logInfo("Processing line \(lineIndex): '\(line)'")

            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            LogManager.shared.logInfo("Line \(lineIndex) has \(components.count) components: \(components)")

            if components.count >= 2 {
                let shareName = components[0]
                let shareType = components[1]

                LogManager.shared.logInfo("Share candidate: name='\(shareName)', type='\(shareType)'")

                if shareType.lowercased() == "disk" && !shareName.contains("$") {
                    let share = SMBShare(name: shareName, type: shareType, host: host)
                    shares.append(share)
                    LogManager.shared.logInfo("✅ Added share: \(shareName)")
                } else {
                    LogManager.shared.logInfo("❌ Rejected share: name='\(shareName)', type='\(shareType)' (type not disk or contains $)")
                }
            } else {
                LogManager.shared.logInfo("❌ Line \(lineIndex) skipped: insufficient components (\(components.count))")
            }
        }

        LogManager.shared.logInfo("=== PARSE SHARES DEBUG END: Found \(shares.count) shares ===")
        return shares
    }

    private func unmountConflictingMounts(for host: String) async throws {
        let conflictingHosts = ServerHost.conflictingHosts
        if !conflictingHosts.contains(host) { return }

        let mounts = try getMountedSMBShares()
        for mount in mounts {
            if conflictingHosts.contains(where: { mount.source.contains($0) }) {
                try await unmountByPath(mount.mountPoint)
            }
        }
    }

    private nonisolated func getMountedSMBShares() throws -> [(source: String, mountPoint: String)] {
        let process = Process()
        process.launchPath = "/sbin/mount"
        process.arguments = []

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        var mounts: [(source: String, mountPoint: String)] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if line.contains("smbfs") && line.contains("/Volumes/") {
                let components = line.components(separatedBy: " on ")
                if components.count >= 2 {
                    let source = components[0]
                    let remaining = components[1]
                    if let mountEnd = remaining.range(of: " (") {
                        let mountPoint = String(remaining[..<mountEnd.lowerBound])
                        mounts.append((source: source, mountPoint: mountPoint))
                    }
                }
            }
        }

        return mounts
    }

    private func mountShare(_ share: SMBShare, credentials: SMBCredentials) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.performMount(share: share, credentials: credentials)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated func performMount(share: SMBShare, credentials: SMBCredentials) throws {
        LogManager.shared.logInfo("Attempting to mount share '\(share.name)' from \(share.host)")

        // Use simple mount volume command that handles everything as logged-in user
        let mountCommand = "mount volume \"smb://\(credentials.formattedUsername):\(credentials.password)@\(share.host)/\(share.name)\""

        let appleScript = """
        \(mountCommand)
        """

        LogManager.shared.logInfo("Executing mount volume command: \(mountCommand)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown mount error"
                LogManager.shared.logError("mount_smbfs failed with exit code \(process.terminationStatus): \(errorOutput)")
                throw SMBConnectionError.mountFailed(share.name)
            }

            // Give the mount command time to complete
            Thread.sleep(forTimeInterval: 1.0)

            // Verify the mount was successful by checking if files are accessible
            let mountPoint = share.mountPath
            let testRead = Process()
            testRead.executableURL = URL(fileURLWithPath: "/bin/ls")
            testRead.arguments = [mountPoint.path]

            do {
                try testRead.run()
                testRead.waitUntilExit()

                if testRead.terminationStatus == 0 {
                    LogManager.shared.logInfo("Successfully mounted and verified share '\(share.name)' at \(mountPoint.path)")
                } else {
                    LogManager.shared.logError("Mount directory exists but share not accessible at \(mountPoint.path)")
                    throw SMBConnectionError.mountFailed(share.name)
                }
            } catch {
                LogManager.shared.logError("Failed to verify mount at \(mountPoint.path): \(error)")
                throw SMBConnectionError.mountFailed(share.name)
            }

        } catch {
            LogManager.shared.logError("Failed to execute mount command for \(share.name): \(error)")
            throw SMBConnectionError.mountFailed(share.name)
        }
    }

    private func unmountShare(_ share: SMBShare) async throws {
        try await unmountByPath(share.mountPath.path)
    }

    private nonisolated func unmountByPath(_ path: String) async throws {
        let diskutilProcess = Process()
        diskutilProcess.launchPath = "/usr/sbin/diskutil"
        diskutilProcess.arguments = ["unmount", path]

        try diskutilProcess.run()
        diskutilProcess.waitUntilExit()

        if diskutilProcess.terminationStatus != 0 {
            let umountProcess = Process()
            umountProcess.launchPath = "/sbin/umount"
            umountProcess.arguments = ["-f", path]

            try umountProcess.run()
            umountProcess.waitUntilExit()

            guard umountProcess.terminationStatus == 0 else {
                throw SMBConnectionError.unmountFailed(path)
            }
        }
    }

    private func openInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func refreshMountedShares() {
        Task {
            do {
                let mounts = try getMountedSMBShares()
                var mounted: [SMBShare] = []

                for mount in mounts {
                    if let volumeName = URL(fileURLWithPath: mount.mountPoint).lastPathComponent.isEmpty
                        ? nil : URL(fileURLWithPath: mount.mountPoint).lastPathComponent,
                       let host = extractHost(from: mount.source) {
                        mounted.append(SMBShare(name: volumeName, type: "Disk", host: host))
                    }
                }

                await MainActor.run {
                    self.mountedShares = mounted
                }
            } catch {
                await MainActor.run {
                    self.mountedShares = []
                }
            }
        }
    }

    private nonisolated func extractHost(from source: String) -> String? {
        if let range = source.range(of: "@"),
           let endRange = source.range(of: "/", range: range.upperBound..<source.endIndex) {
            return String(source[range.upperBound..<endRange.lowerBound])
        }
        return nil
    }

    // MARK: - Local Network Permission

    private nonisolated func triggerLocalNetworkPermission() async {
        // This API call triggers the macOS Sequoia local network privacy permission prompt
        let _ = ProcessInfo.processInfo.hostName

        // Also try some other APIs that might trigger permission
        await tryBonjourService()
    }

    private nonisolated func tryBonjourService() async {
        // Create a simple NSNetService browser to trigger local network permission
        let browser = NetServiceBrowser()
        browser.searchForServices(ofType: "_smb._tcp.", inDomain: "local.")

        // Give it a moment to trigger the permission prompt
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        browser.stop()
    }

    // MARK: - Network Diagnostics

    private nonisolated func performNetworkDiagnostics(host: String) async {
        LogManager.shared.logInfo("--- Network Diagnostics for \(host) ---")

        // Test basic connectivity with ping
        await testPing(host: host)

        // Test SMB ports
        await testSMBPorts(host: host)

        // Test network route
        await testNetworkRoute(host: host)

        LogManager.shared.logInfo("--- Network Diagnostics Complete ---")
    }

    private nonisolated func testPing(host: String) async {
        LogManager.shared.logInfo("Testing ping connectivity to \(host)...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "3", "-W", "2000", host]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            let timeout = DispatchTime.now() + .seconds(10)
            let semaphore = DispatchSemaphore(value: 0)

            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                semaphore.signal()
            }

            let timeoutResult = semaphore.wait(timeout: timeout)
            if timeoutResult == .timedOut {
                LogManager.shared.logError("Ping test timed out")
                process.terminate()
                return
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            LogManager.shared.logInfo("Ping result (exit code \(process.terminationStatus)):")
            LogManager.shared.logInfo("Ping output: \(output)")
            if !errorOutput.isEmpty {
                LogManager.shared.logError("Ping error: \(errorOutput)")
            }

        } catch {
            LogManager.shared.logError("Failed to execute ping: \(error)")
        }
    }

    private nonisolated func testSMBPorts(host: String) async {
        LogManager.shared.logInfo("Testing SMB port connectivity...")

        // Test common SMB ports: 445 (SMB over TCP), 139 (NetBIOS)
        for port in [445, 139] {
            await testPort(host: host, port: port)
        }
    }

    private nonisolated func testPort(host: String, port: Int) async {
        LogManager.shared.logInfo("Testing port \(port) on \(host)...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = ["-z", "-v", "-w", "5", host, "\(port)"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            let timeout = DispatchTime.now() + .seconds(10)
            let semaphore = DispatchSemaphore(value: 0)

            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                semaphore.signal()
            }

            let timeoutResult = semaphore.wait(timeout: timeout)
            if timeoutResult == .timedOut {
                LogManager.shared.logError("Port \(port) test timed out")
                process.terminate()
                return
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            LogManager.shared.logInfo("Port \(port) test result (exit code \(process.terminationStatus)):")
            if !output.isEmpty {
                LogManager.shared.logInfo("Port \(port) output: \(output)")
            }
            if !errorOutput.isEmpty {
                LogManager.shared.logInfo("Port \(port) info: \(errorOutput)")
            }

        } catch {
            LogManager.shared.logError("Failed to test port \(port): \(error)")
        }
    }

    private nonisolated func testNetworkRoute(host: String) async {
        LogManager.shared.logInfo("Testing network route to \(host)...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/traceroute")
        process.arguments = ["-m", "5", host]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            let timeout = DispatchTime.now() + .seconds(15)
            let semaphore = DispatchSemaphore(value: 0)

            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                semaphore.signal()
            }

            let timeoutResult = semaphore.wait(timeout: timeout)
            if timeoutResult == .timedOut {
                LogManager.shared.logError("Traceroute test timed out")
                process.terminate()
                return
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            LogManager.shared.logInfo("Network route result:")
            LogManager.shared.logInfo("Route output: \(output)")
            if !errorOutput.isEmpty {
                LogManager.shared.logError("Route error: \(errorOutput)")
            }

        } catch {
            LogManager.shared.logError("Failed to execute traceroute: \(error)")
        }
    }

    private nonisolated func performSMBDiagnostics(host: String) async {
        LogManager.shared.logInfo("--- SMB-Specific Diagnostics for \(host) ---")

        // Test SMB service availability
        await testSMBService(host: host)

        // Check system SMB client configuration
        await checkSMBClientConfig()

        LogManager.shared.logInfo("--- SMB Diagnostics Complete ---")
    }

    private nonisolated func testSMBService(host: String) async {
        LogManager.shared.logInfo("Testing SMB service availability on \(host)...")

        // Try a simple smbutil without credentials first
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
        process.arguments = ["status", host]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            let timeout = DispatchTime.now() + .seconds(10)
            let semaphore = DispatchSemaphore(value: 0)

            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                semaphore.signal()
            }

            let timeoutResult = semaphore.wait(timeout: timeout)
            if timeoutResult == .timedOut {
                LogManager.shared.logError("SMB service test timed out")
                process.terminate()
                return
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            LogManager.shared.logInfo("SMB service test result (exit code \(process.terminationStatus)):")
            LogManager.shared.logInfo("SMB status output: \(output)")
            if !errorOutput.isEmpty {
                LogManager.shared.logInfo("SMB status error: \(errorOutput)")
            }

        } catch {
            LogManager.shared.logError("Failed to test SMB service: \(error)")
        }
    }

    private nonisolated func checkSMBClientConfig() async {
        LogManager.shared.logInfo("Checking SMB client configuration...")

        // Check if SMB client is configured
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
        process.arguments = ["help"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""

            LogManager.shared.logInfo("SMB client available commands:")
            LogManager.shared.logInfo("\(output)")

        } catch {
            LogManager.shared.logError("Failed to check SMB client config: \(error)")
        }
    }
}