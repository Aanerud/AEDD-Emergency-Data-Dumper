import SwiftUI

struct PermissionStatusBarView: View {
    let networkStatus: PermissionStatus
    let filesStatus: PermissionStatus
    let automationStatus: PermissionStatus
    let toolsStatus: PermissionStatus
    let onPermissionAction: (PermissionType, PermissionAction) -> Void

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
                PermissionLight(
                    type: .network,
                    status: networkStatus,
                    onAction: onPermissionAction
                )

                PermissionLight(
                    type: .files,
                    status: filesStatus,
                    onAction: onPermissionAction
                )

                PermissionLight(
                    type: .automation,
                    status: automationStatus,
                    onAction: onPermissionAction
                )

                PermissionLight(
                    type: .tools,
                    status: toolsStatus,
                    onAction: onPermissionAction
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

        if readyCount == 4 {
            return "All systems ready"
        } else {
            return "\(readyCount)/4 ready"
        }
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

struct PermissionLight: View {
    let type: PermissionType
    let status: PermissionStatus
    let onAction: (PermissionType, PermissionAction) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            switch status {
            case .needsSetup, .failed:
                onAction(type, .fix)
            default:
                onAction(type, .help)
            }
        }) {
            VStack(spacing: 8) {
                // Status light
                HStack(spacing: 6) {
                    Image(systemName: status.icon)
                        .foregroundColor(status.color)
                        .font(.system(size: 16, weight: .semibold))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.title)
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

struct PermissionHelpSheet: View {
    let type: HelpType
    let onAction: (PermissionAction) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: permissionType.icon)
                    .font(.title)
                    .foregroundColor(.blue)
                Text(permissionType.helpTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("×") {
                    presentationMode.wrappedValue.dismiss()
                }
                .font(.title2)
                .foregroundColor(.secondary)
                .buttonStyle(PlainButtonStyle())
            }

            // Description
            Text(permissionType.helpDescription)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            // Specific help content
            helpContent

            Spacer()

            // Actions
            HStack {
                if canFix {
                    Button("Fix This Issue") {
                        onAction(.fix)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Open System Settings") {
                    onAction(.openSettings)
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }

    private var permissionType: PermissionType {
        switch type {
        case .network: return .network
        case .files: return .files
        case .automation: return .automation
        case .tools: return .tools
        }
    }

    private var canFix: Bool {
        switch type {
        case .network, .files, .automation: return true
        case .tools: return false
        }
    }

    @ViewBuilder
    private var helpContent: some View {
        switch type {
        case .network:
            VStack(alignment: .leading, spacing: 8) {
                Text("What this does:")
                    .font(.headline)
                Text("• Tests network connectivity to SMB shares")
                Text("• Triggers macOS Local Network permission prompt")
                Text("• Ensures app can discover network resources")
            }

        case .files:
            VStack(alignment: .leading, spacing: 8) {
                Text("What this does:")
                    .font(.headline)
                Text("• Allows app to read from SMB shares")
                Text("• Gives write access to your chosen destination")
                Text("• Uses security-scoped bookmarks for persistent access")
            }

        case .automation:
            VStack(alignment: .leading, spacing: 8) {
                Text("What this does:")
                    .font(.headline)
                Text("• Enables interaction with Finder")
                Text("• Allows seamless SMB mounting")
                Text("• Provides integrated file management")
            }

        case .tools:
            VStack(alignment: .leading, spacing: 8) {
                Text("Required tools:")
                    .font(.headline)
                Text("• /usr/bin/smbutil - SMB share discovery")
                    .font(.caption)
                    .fontFamily(.monospaced)
                Text("• /sbin/mount_smbfs - SMB mounting")
                    .font(.caption)
                    .fontFamily(.monospaced)
                Text("• /usr/bin/rsync - File synchronization")
                    .font(.caption)
                    .fontFamily(.monospaced)

                Text("If tools are missing, install Xcode Command Line Tools:")
                    .foregroundColor(.secondary)
                Text("xcode-select --install")
                    .font(.caption)
                    .fontFamily(.monospaced)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
            }
        }
    }
}

#Preview {
    PermissionStatusBarView(
        networkStatus: .needsSetup(reason: "Local network permission required"),
        filesStatus: .ready,
        automationStatus: .failed(reason: "Permission denied"),
        toolsStatus: .needsSetup(reason: "1 tool missing")
    ) { type, action in
        print("Action: \(action) for \(type)")
    }
    .padding()
}