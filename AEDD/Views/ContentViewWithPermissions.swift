import SwiftUI
import Security
import UniformTypeIdentifiers
import ApplicationServices

// MARK: - Permission Types

enum PermissionStatus: Equatable {
    case checking
    case ready
    case needsSetup(reason: String)
    case failed(reason: String)

    var color: Color {
        switch self {
        case .checking: return .gray
        case .ready: return .green
        case .needsSetup: return .yellow
        case .failed: return .red
        }
    }

    var icon: String {
        switch self {
        case .checking: return "clock"
        case .ready: return "checkmark.circle.fill"
        case .needsSetup: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .checking: return "Checking..."
        case .ready: return "Ready"
        case .needsSetup: return "Setup Required"
        case .failed: return "Failed"
        }
    }

    var description: String {
        switch self {
        case .checking: return "Checking status..."
        case .ready: return "All systems operational"
        case .needsSetup(let reason): return reason
        case .failed(let reason): return reason
        }
    }
}

enum AutomationResult {
    case allowed, denied, notDetermined
}

// MARK: - Main ContentView

struct ContentViewWithPermissions: View {
    @EnvironmentObject var jobManager: JobManager
    @EnvironmentObject var smbManager: SMBManager
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var showingConnectionSheet = false
    @State private var showingShareSelector = false
    @State private var sources: [URL] = []
    @State private var destination: URL?
    @State private var currentCredentials: SMBCredentials?

    // Permission system
    @State private var networkStatus = PermissionStatus.checking
    @State private var filesStatus = PermissionStatus.checking
    @State private var automationStatus = PermissionStatus.checking
    @State private var toolsStatus = PermissionStatus.checking

    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var securityScopedDestinations: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(
                showingConnectionSheet: $showingConnectionSheet,
                showingShareSelector: $showingShareSelector
            )

            // Permission Status Bar
            PermissionStatusBarEmbedded(
                networkStatus: networkStatus,
                filesStatus: filesStatus,
                automationStatus: automationStatus,
                toolsStatus: toolsStatus,
                onNetworkFix: { await triggerNetworkPermission() },
                onFilesFix: { chooseDestinationFolder() },
                onAutomationFix: { await requestAutomationPermission() },
                onToolsFix: { showPermissionAlert("System tools missing. Please install Xcode Command Line Tools: xcode-select --install") }
            )
            .padding(.horizontal)
            .padding(.vertical, 8)

            HSplitView {
                VStack {
                    SourcesView(sources: $sources)
                        .frame(minWidth: 200)

                    Spacer()

                    SubmitJobView(
                        sources: sources,
                        destination: destination,
                        onSubmit: submitJob
                    )
                    .padding()
                }

                VStack {
                    DestinationView(destination: $destination)
                        .frame(minWidth: 200)

                    Spacer()
                }
            }
            .frame(minHeight: 300)

            JobQueueView()
                .frame(minHeight: 200)
        }
        .sheet(isPresented: $showingConnectionSheet) {
            ConnectionView(onConnected: { credentials in
                LogManager.shared.logInfo("🔗 ConnectionView: Connection successful, credentials received")
                currentCredentials = credentials
                showingShareSelector = true
                showingConnectionSheet = false
            })
        }
        .sheet(isPresented: $showingShareSelector) {
            if let credentials = currentCredentials {
                ShareSelectorView(credentials: credentials, onMounted: {
                    LogManager.shared.logInfo("📋 ShareSelectorView: Mount completed, hiding share selector")
                    showingShareSelector = false
                })
            } else {
                Text("No credentials available")
            }
        }
        .alert("Permission Status", isPresented: $showingPermissionAlert) {
            Button("OK") {}
        } message: {
            Text(permissionAlertMessage)
        }
        .onAppear {
            setupInitialState()
            Task {
                await checkAllPermissions()
            }
        }
    }

    // MARK: - Permission System

    private func checkAllPermissions() async {
        await MainActor.run {
            networkStatus = .checking
            filesStatus = .checking
            automationStatus = .checking
            toolsStatus = .checking
        }

        let network = await checkNetworkPermission()
        let files = checkFilesPermission()
        let automation = await checkAutomationPermission()
        let tools = checkRequiredTools()

        await MainActor.run {
            networkStatus = network
            filesStatus = files
            automationStatus = automation
            toolsStatus = tools

            LogManager.shared.logInfo("🚦 Permission Status - Network: \(network), Files: \(files), Automation: \(automation), Tools: \(tools)")
        }
    }

    private func checkNetworkPermission() async -> PermissionStatus {
        // Check entitlement first
        guard entitlementIsTrue("com.apple.security.network.client") else {
            return .failed(reason: "Missing network client entitlement")
        }

        // Test network connectivity
        let canConnect = await testNetworkConnection()
        return canConnect ? .ready : .needsSetup(reason: "Click to trigger Local Network permission")
    }

    private func checkFilesPermission() -> PermissionStatus {
        if securityScopedDestinations.isEmpty {
            return .needsSetup(reason: "Click to choose destination folder")
        }

        guard let destination = securityScopedDestinations.first else {
            return .needsSetup(reason: "Click to choose destination folder")
        }

        return canWriteToDestination(destination) ? .ready : .failed(reason: "Cannot write to destination")
    }

    private func checkAutomationPermission() async -> PermissionStatus {
        guard entitlementIsTrue("com.apple.security.automation.apple-events") else {
            return .failed(reason: "Missing Apple Events entitlement")
        }

        let status = await getFinderAutomationStatus(promptIfNeeded: false)
        switch status {
        case .allowed:
            return .ready
        case .notDetermined:
            return .needsSetup(reason: "Click to request Finder permission")
        case .denied:
            return .failed(reason: "Permission denied - check System Settings")
        }
    }

    private func checkRequiredTools() -> PermissionStatus {
        let tools = ["/usr/bin/smbutil", "/sbin/mount_smbfs", "/usr/bin/rsync"]
        let available = tools.filter { FileManager.default.isExecutableFile(atPath: $0) }

        if available.count == tools.count {
            return .ready
        } else {
            return .failed(reason: "\(tools.count - available.count) tools missing")
        }
    }

    // MARK: - Permission Actions

    private func triggerNetworkPermission() async {
        LogManager.shared.logInfo("🔐 Triggering network permission...")

        // This should trigger the Local Network permission prompt
        let hostname = ProcessInfo.processInfo.hostName
        LogManager.shared.logInfo("🔐 Retrieved hostname: \(hostname)")

        // Test network connection
        let success = await testNetworkConnection()

        let newStatus: PermissionStatus = success ? .ready : .needsSetup(reason: "Network test failed - try SMB connection")

        await MainActor.run {
            networkStatus = newStatus
            showPermissionAlert("Network permission test completed. \(success ? "Success!" : "Failed - try connecting to SMB server.")")
        }
    }

    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Destination Folder"
        panel.message = "Select where to copy files from SMB shares"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    self.addSecurityScopedDestination(url)
                    self.destination = url
                    let newStatus = self.checkFilesPermission()
                    self.filesStatus = newStatus
                    self.showPermissionAlert("Destination folder selected: \(url.lastPathComponent)")
                }
            }
        }
    }

    private func requestAutomationPermission() async {
        LogManager.shared.logInfo("🔐 Requesting automation permission...")

        let status = await getFinderAutomationStatus(promptIfNeeded: true)
        let newStatus: PermissionStatus = switch status {
        case .allowed: .ready
        case .notDetermined: .needsSetup(reason: "Permission dialog may have been dismissed")
        case .denied: .failed(reason: "Permission denied - check System Settings")
        }

        await MainActor.run {
            automationStatus = newStatus
            let message = switch status {
            case .allowed: "Automation permission granted!"
            case .denied: "Automation permission denied. Enable in System Settings → Privacy & Security → Automation"
            case .notDetermined: "Permission dialog appeared. Please grant permission when prompted."
            }
            showPermissionAlert(message)
        }
    }

    private func showPermissionAlert(_ message: String) {
        permissionAlertMessage = message
        showingPermissionAlert = true
    }

    // MARK: - Helper Functions

    private func entitlementIsTrue(_ key: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault) else { return false }
        defer { CFRelease(task) }

        var error: Unmanaged<CFError>?
        guard let value = SecTaskCopyValueForEntitlement(task, key as CFString, &error) else {
            return false
        }

        return (value as? Bool) == true
    }

    private func testNetworkConnection() async -> Bool {
        return await withCheckedContinuation { continuation in
            let socket = socket(AF_INET, SOCK_DGRAM, 0)
            guard socket >= 0 else {
                continuation.resume(returning: false)
                return
            }

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = CFSwapInt16HostToBig(139) // SMB port
            inet_pton(AF_INET, "192.168.0.81", &addr.sin_addr)

            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            close(socket)
            let success = result == 0 || errno == ECONNREFUSED
            LogManager.shared.logInfo("🔐 Network test result: \(success ? "success" : "failed") (errno: \(errno))")
            continuation.resume(returning: success)
        }
    }

    private func getFinderAutomationStatus(promptIfNeeded: Bool) async -> AutomationResult {
        return await withCheckedContinuation { continuation in
            let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
            let err = AEDeterminePermissionToAutomateTarget(
                finder.aeDesc,
                typeWildCard,
                typeWildCard,
                promptIfNeeded
            )

            switch err {
            case 0:
                continuation.resume(returning: .allowed)
            case procNotFound:
                continuation.resume(returning: .notDetermined)
            case errAEEventNotPermitted, errAEPrivilegeError:
                continuation.resume(returning: .denied)
            default:
                LogManager.shared.logError("Automation permission error: \(err)")
                continuation.resume(returning: .denied)
            }
        }
    }

    private func addSecurityScopedDestination(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            LogManager.shared.logError("Failed to start accessing security scoped resource: \(url)")
            return
        }

        securityScopedDestinations.append(url)
        LogManager.shared.logInfo("Added security-scoped destination: \(url.path)")
    }

    private func canWriteToDestination(_ url: URL) -> Bool {
        let testURL = url.appendingPathComponent(".aedd_write_test_\(UUID().uuidString)")

        do {
            try "AEDD write test".data(using: .utf8)?.write(to: testURL, options: .atomic)
            try FileManager.default.removeItem(at: testURL)
            return true
        } catch {
            LogManager.shared.logError("Write test failed at \(url.path): \(error)")
            return false
        }
    }

    // MARK: - Original Methods

    private func submitJob() {
        guard !sources.isEmpty, let destination = destination else { return }

        let host = smbManager.mountedShares.first?.host ?? "Unknown"
        let rsyncFlags = settingsManager.settings.defaultRsyncFlags

        let job = CopyJob(
            serverHost: host,
            sources: sources,
            destination: destination,
            rsyncArgs: rsyncFlags.arguments,
            createdAt: Date()
        )

        jobManager.addJob(job)

        self.sources = []
        self.destination = nil
    }

    private func setupInitialState() {
        // Original setup code
    }
}

// MARK: - Embedded Permission Status Bar

struct PermissionStatusBarEmbedded: View {
    let networkStatus: PermissionStatus
    let filesStatus: PermissionStatus
    let automationStatus: PermissionStatus
    let toolsStatus: PermissionStatus

    let onNetworkFix: () async -> Void
    let onFilesFix: () -> Void
    let onAutomationFix: () async -> Void
    let onToolsFix: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Title
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(.primary)
                Text("System Readiness")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()

                // Overall status indicator
                HStack(spacing: 4) {
                    Text(overallStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: overallStatusIcon)
                        .foregroundColor(overallStatusColor)
                        .font(.caption)
                }
            }

            // Permission lights
            HStack(spacing: 16) {
                PermissionLightEmbedded(
                    title: "Network",
                    status: networkStatus,
                    onAction: { Task { await onNetworkFix() } }
                )

                PermissionLightEmbedded(
                    title: "Files",
                    status: filesStatus,
                    onAction: { onFilesFix() }
                )

                PermissionLightEmbedded(
                    title: "Automation",
                    status: automationStatus,
                    onAction: { Task { await onAutomationFix() } }
                )

                PermissionLightEmbedded(
                    title: "Tools",
                    status: toolsStatus,
                    onAction: { onToolsFix() }
                )

                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }

    private var overallStatusText: String {
        let allStatuses = [networkStatus, filesStatus, automationStatus, toolsStatus]
        let readyCount = allStatuses.filter { if case .ready = $0 { return true }; return false }.count
        return readyCount == 4 ? "All systems ready" : "\(readyCount)/4 ready"
    }

    private var overallStatusIcon: String {
        let allStatuses = [networkStatus, filesStatus, automationStatus, toolsStatus]

        if allStatuses.contains(where: { if case .failed = $0 { return true }; return false }) {
            return "xmark.circle.fill"
        } else if allStatuses.contains(where: { if case .needsSetup = $0 { return true }; return false }) {
            return "exclamationmark.triangle.fill"
        } else if allStatuses.allSatisfy({ if case .ready = $0 { return true }; return false }) {
            return "checkmark.circle.fill"
        } else {
            return "clock"
        }
    }

    private var overallStatusColor: Color {
        let allStatuses = [networkStatus, filesStatus, automationStatus, toolsStatus]

        if allStatuses.contains(where: { if case .failed = $0 { return true }; return false }) {
            return .red
        } else if allStatuses.contains(where: { if case .needsSetup = $0 { return true }; return false }) {
            return .yellow
        } else if allStatuses.allSatisfy({ if case .ready = $0 { return true }; return false }) {
            return .green
        } else {
            return .gray
        }
    }
}

struct PermissionLightEmbedded: View {
    let title: String
    let status: PermissionStatus
    let onAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onAction) {
            VStack(spacing: 8) {
                // Status light
                HStack(spacing: 6) {
                    Image(systemName: status.icon)
                        .foregroundColor(status.color)
                        .font(.system(size: 16, weight: .semibold))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text(status.title)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Action hint
                if case .needsSetup = status {
                    Text("Click to fix")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .opacity(isHovered ? 1.0 : 0.7)
                } else if case .failed = status {
                    Text("Click for help")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .opacity(isHovered ? 1.0 : 0.7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(status.color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ContentViewWithPermissions()
        .environmentObject(JobManager())
        .environmentObject(SMBManager())
        .environmentObject(SettingsManager())
}