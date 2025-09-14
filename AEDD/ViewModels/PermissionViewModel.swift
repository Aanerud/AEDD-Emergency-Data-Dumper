import Foundation
import SwiftUI
import Security
import UniformTypeIdentifiers
import ApplicationServices

enum LightState: CaseIterable {
    case green, yellow, red

    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    var systemName: String {
        switch self {
        case .green: return "checkmark.circle.fill"
        case .yellow: return "exclamationmark.triangle.fill"
        case .red: return "xmark.circle.fill"
        }
    }
}

enum AutomationStatus {
    case allowed, denied, notDetermined
}

@MainActor
final class PermissionViewModel: ObservableObject {
    @Published var network = LightState.red
    @Published var files = LightState.yellow
    @Published var automation = LightState.yellow
    @Published var tools = LightState.red

    @Published var showingNetworkHelp = false
    @Published var showingFilesHelp = false
    @Published var showingAutomationHelp = false
    @Published var showingToolsHelp = false

    private var activeDestinations: [URL] = []

    init() {
        refresh()
    }

    func refresh(with destinations: [URL] = []) {
        activeDestinations = destinations

        Task { @MainActor in
            network = await checkNetworkEntitlement()
            automation = await checkAutomationStatus()
            files = checkFilesAccess()
            tools = checkRequiredTools()

            LogManager.shared.logInfo("🚦 Permission Status - Network: \(network), Files: \(files), Automation: \(automation), Tools: \(tools)")
        }
    }

    // MARK: - Entitlement Checking

    private func entitlementIsTrue(_ key: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault) else {
            LogManager.shared.logError("Failed to create security task for entitlement check")
            return false
        }

        defer { CFRelease(task) }

        var error: Unmanaged<CFError>?
        guard let value = SecTaskCopyValueForEntitlement(task, key as CFString, &error) else {
            if let error = error?.takeRetainedValue() {
                LogManager.shared.logError("Entitlement check failed for \(key): \(error)")
            }
            return false
        }

        let result = (value as? Bool) == true
        LogManager.shared.logInfo("Entitlement \(key): \(result)")
        return result
    }

    private func checkNetworkEntitlement() async -> LightState {
        let hasNetworkClient = entitlementIsTrue("com.apple.security.network.client")
        let hasNetworkAccess = entitlementIsTrue("com.apple.security.files.network-access")

        if hasNetworkClient && hasNetworkAccess {
            // Try a quick network test
            return await testNetworkConnectivity() ? .green : .yellow
        }

        return .red
    }

    private func testNetworkConnectivity() async -> Bool {
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
            continuation.resume(returning: result == 0 || errno == ECONNREFUSED) // Connection attempt is what matters
        }
    }

    // MARK: - Automation Status

    private func checkAutomationStatus() async -> LightState {
        guard entitlementIsTrue("com.apple.security.automation.apple-events") else {
            return .red
        }

        switch await getFinderAutomationStatus(promptIfNeeded: false) {
        case .allowed: return .green
        case .notDetermined: return .yellow
        case .denied: return .red
        }
    }

    private func getFinderAutomationStatus(promptIfNeeded: Bool) async -> AutomationStatus {
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
                LogManager.shared.logError("Automation permission check failed with error: \(err)")
                continuation.resume(returning: .denied)
            }
        }
    }

    func requestAutomationConsent() {
        Task { @MainActor in
            let status = await getFinderAutomationStatus(promptIfNeeded: true)
            automation = switch status {
            case .allowed: .green
            case .notDetermined: .yellow
            case .denied: .red
            }
        }
    }

    // MARK: - Files Access

    private func checkFilesAccess() -> LightState {
        guard !activeDestinations.isEmpty else { return .yellow }

        // Test if we can write to the first active destination
        guard let destination = activeDestinations.first else { return .yellow }
        return canWriteTestFile(to: destination) ? .green : .red
    }

    private func canWriteTestFile(to destination: URL) -> Bool {
        let testURL = destination.appendingPathComponent(".aedd_write_test_\(UUID().uuidString)")

        do {
            try "AEDD write test".data(using: .utf8)?.write(to: testURL, options: .atomic)
            try FileManager.default.removeItem(at: testURL)
            LogManager.shared.logInfo("Write test successful at: \(destination.path)")
            return true
        } catch {
            LogManager.shared.logError("Write test failed at \(destination.path): \(error)")
            return false
        }
    }

    // MARK: - Tools Check

    private func checkRequiredTools() -> LightState {
        let requiredTools = [
            "/sbin/mount_smbfs",
            "/usr/bin/smbutil",
            "/usr/bin/rsync"
        ]

        let availableTools = requiredTools.filter { FileManager.default.isExecutableFile(atPath: $0) }

        LogManager.shared.logInfo("Tools check: \(availableTools.count)/\(requiredTools.count) available")

        if availableTools.count == requiredTools.count {
            return .green
        } else if availableTools.count > 0 {
            return .yellow
        } else {
            return .red
        }
    }

    // MARK: - Help Actions

    func openNetworkHelp() {
        showingNetworkHelp = true
    }

    func openFilesHelp() {
        showingFilesHelp = true
    }

    func openAutomationHelp() {
        showingAutomationHelp = true
    }

    func openToolsHelp() {
        showingToolsHelp = true
    }

    func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
    }
}