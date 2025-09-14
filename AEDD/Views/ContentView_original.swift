import SwiftUI
import Security
import UniformTypeIdentifiers
import ApplicationServices

struct ContentView: View {
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

    @State private var showingPermissionHelp = false
    @State private var selectedHelpType: HelpType?
    @State private var securityScopedDestinations: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(
                showingConnectionSheet: $showingConnectionSheet,
                showingShareSelector: $showingShareSelector
            )

            // Permission Status Bar
            PermissionStatusBarView(
                networkStatus: networkStatus,
                filesStatus: filesStatus,
                automationStatus: automationStatus,
                toolsStatus: toolsStatus,
                onPermissionAction: handlePermissionAction
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
                LogManager.shared.logInfo("🔗 ConnectionView: Setting currentCredentials and showing share selector")
                currentCredentials = credentials
                showingShareSelector = true
                showingConnectionSheet = false
                LogManager.shared.logInfo("🔗 ConnectionView: Hiding connection sheet, showing share selector")
            })
        }
        .sheet(isPresented: $showingShareSelector) {
            if let credentials = currentCredentials {
                ShareSelectorView(credentials: credentials, onMounted: {
                    LogManager.shared.logInfo("📋 ShareSelectorView: Mount completed, hiding share selector")
                    showingShareSelector = false
                })
                .onAppear {
                    LogManager.shared.logInfo("📋 ShareSelectorView: Opening with credentials for user: \(credentials.username)")
                }
            } else {
                Text("No credentials available")
                    .onAppear {
                        LogManager.shared.logError("📋 ShareSelectorView: No credentials available!")
                    }
            }
        }
        .onChange(of: showingConnectionSheet) { isShowing in
            LogManager.shared.logInfo("🪟 Window State: Connection sheet is now \(isShowing ? "SHOWING" : "HIDDEN")")
        }
        .onChange(of: showingShareSelector) { isShowing in
            LogManager.shared.logInfo("🪟 Window State: Share selector is now \(isShowing ? "SHOWING" : "HIDDEN")")
        }
        .sheet(isPresented: $showingPermissionHelp) {
            if let helpType = selectedHelpType {
                PermissionHelpSheet(
                    type: helpType,
                    onAction: { action in
                        handlePermissionAction(type: helpType, action: action)
                    }
                )
            }
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

        // Test network connectivity to trigger permission if needed
        let canConnect = await testNetworkConnection()
        return canConnect ? .ready : .needsSetup(reason: "Local network permission required")
    }

    private func checkFilesPermission() -> PermissionStatus {
        if securityScopedDestinations.isEmpty {
            return .needsSetup(reason: "No destination folder selected")
        }

        // Test if we can write to the first destination
        guard let destination = securityScopedDestinations.first else {
            return .needsSetup(reason: "No destination folder selected")
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
            return .needsSetup(reason: "Automation permission not requested")
        case .denied:
            return .failed(reason: "Automation permission denied")
        }
    }

    private func checkRequiredTools() -> PermissionStatus {
        let tools = [
            "/usr/bin/smbutil",
            "/sbin/mount_smbfs",
            "/usr/bin/rsync"
        ]

        let available = tools.filter { FileManager.default.isExecutableFile(atPath: $0) }

        if available.count == tools.count {
            return .ready
        } else if available.count > 0 {
            return .needsSetup(reason: "\(tools.count - available.count) tools missing")
        } else {
            return .failed(reason: "All required tools missing")
        }
    }

    // MARK: - Permission Actions

    private func handlePermissionAction(type: PermissionType, action: PermissionAction) {
        Task {
            switch (type, action) {
            case (.network, .fix):
                await triggerNetworkPermission()
            case (.files, .fix):
                chooseDestinationFolder()
            case (.automation, .fix):
                await requestAutomationPermission()
            case (.tools, .fix):
                openSystemPreferences()
            default:
                selectedHelpType = type
                showingPermissionHelp = true
            }
        }
    }

    private func triggerNetworkPermission() async {
        LogManager.shared.logInfo("🔐 Triggering network permission...")

        // This should trigger the Local Network permission prompt
        let hostname = ProcessInfo.processInfo.hostName
        LogManager.shared.logInfo("🔐 Retrieved hostname: \(hostname)")

        // Test network connection which should trigger permission
        await testNetworkConnection()

        // Recheck status
        let newStatus = await checkNetworkPermission()
        await MainActor.run {
            networkStatus = newStatus
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
                }
            }
        }
    }

    private func requestAutomationPermission() async {
        LogManager.shared.logInfo("🔐 Requesting automation permission...")

        let status = await getFinderAutomationStatus(promptIfNeeded: true)
        let newStatus: PermissionStatus = switch status {
        case .allowed: .ready
        case .notDetermined: .needsSetup(reason: "Permission not granted")
        case .denied: .failed(reason: "Permission denied in System Settings")
        }

        await MainActor.run {
            automationStatus = newStatus
        }
    }

    private func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
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

    }
}

#Preview {
    ContentView()
        .environmentObject(JobManager())
        .environmentObject(SMBManager())
        .environmentObject(SettingsManager())
}