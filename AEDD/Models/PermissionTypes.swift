import SwiftUI

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

enum PermissionType: CaseIterable {
    case network
    case files
    case automation
    case tools

    var title: String {
        switch self {
        case .network: return "Network"
        case .files: return "Files"
        case .automation: return "Automation"
        case .tools: return "Tools"
        }
    }

    var icon: String {
        switch self {
        case .network: return "network"
        case .files: return "folder"
        case .automation: return "applescript"
        case .tools: return "terminal"
        }
    }

    var helpTitle: String {
        switch self {
        case .network: return "Network Access"
        case .files: return "Files & Folders"
        case .automation: return "Automation"
        case .tools: return "System Tools"
        }
    }

    var helpDescription: String {
        switch self {
        case .network:
            return "Network access is required to discover and connect to SMB shares. The app needs permission to access your local network."
        case .files:
            return "File access is required to read from SMB shares and write to your chosen destination folder."
        case .automation:
            return "Automation permission allows the app to interact with Finder for mounting SMB shares seamlessly."
        case .tools:
            return "System tools (smbutil, mount_smbfs, rsync) are required for SMB operations and file copying."
        }
    }
}

enum PermissionAction {
    case fix
    case help
    case openSettings
}

enum HelpType {
    case network
    case files
    case automation
    case tools
}

enum AutomationResult {
    case allowed
    case denied
    case notDetermined
}