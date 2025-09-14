import SwiftUI

struct PermissionStatusBar: View {
    @StateObject private var permissionVM = PermissionViewModel()
    @Binding var activeDestinations: [URL]

    var body: some View {
        HStack(spacing: 16) {
            // Network Status
            StatusLight(
                state: permissionVM.network,
                title: "Network",
                icon: "network"
            ) {
                permissionVM.openNetworkHelp()
            }

            // Files Access Status
            StatusLight(
                state: permissionVM.files,
                title: "Files",
                icon: "folder"
            ) {
                permissionVM.openFilesHelp()
            }

            // Automation Status
            StatusLight(
                state: permissionVM.automation,
                title: "Automation",
                icon: "applescript"
            ) {
                permissionVM.openAutomationHelp()
            }

            // Tools Status
            StatusLight(
                state: permissionVM.tools,
                title: "Tools",
                icon: "terminal"
            ) {
                permissionVM.openToolsHelp()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .onChange(of: activeDestinations) { destinations in
            permissionVM.refresh(with: destinations)
        }
        .onAppear {
            permissionVM.refresh(with: activeDestinations)
        }
        .sheet(isPresented: $permissionVM.showingNetworkHelp) {
            NetworkHelpSheet()
        }
        .sheet(isPresented: $permissionVM.showingFilesHelp) {
            FilesHelpSheet(onChooseFolder: {
                // This will be handled by parent view
            })
        }
        .sheet(isPresented: $permissionVM.showingAutomationHelp) {
            AutomationHelpSheet {
                permissionVM.requestAutomationConsent()
            }
        }
        .sheet(isPresented: $permissionVM.showingToolsHelp) {
            ToolsHelpSheet()
        }
    }
}

struct StatusLight: View {
    let state: LightState
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: state.systemName)
                    .foregroundColor(state.color)
                    .font(.system(size: 12, weight: .semibold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(state.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)
        )
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Help Sheets

struct NetworkHelpSheet: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "network")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Network Access")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }

            Text("This app requires network access to connect to SMB shares.")
                .font(.body)

            VStack(alignment: .leading, spacing: 8) {
                Text("Required entitlements:")
                    .font(.headline)
                Text("• com.apple.security.network.client")
                    .font(.caption)
                    .fontFamily(.monospaced)
                Text("• com.apple.security.files.network-access")
                    .font(.caption)
                    .fontFamily(.monospaced)
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)

            Text("If the network light is red, the app must be rebuilt with proper network entitlements.")
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

struct FilesHelpSheet: View {
    @Environment(\.presentationMode) var presentationMode
    let onChooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "folder")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Files & Folders Access")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }

            Text("The app needs permission to write files to your chosen destination.")
                .font(.body)

            VStack(alignment: .leading, spacing: 8) {
                Text("Status meanings:")
                    .font(.headline)
                Text("🟡 Yellow: No destination folder selected")
                Text("🟢 Green: Can write to selected destination")
                Text("🔴 Red: Cannot write to destination (permission denied)")
            }

            Button("Choose Destination Folder...") {
                onChooseFolder()
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }
}

struct AutomationHelpSheet: View {
    @Environment(\.presentationMode) var presentationMode
    let onRequestPermission: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "applescript")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Automation Permission")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }

            Text("Automation permission allows the app to interact with Finder for mounting SMB shares.")
                .font(.body)

            VStack(alignment: .leading, spacing: 8) {
                Text("Status meanings:")
                    .font(.headline)
                Text("🟡 Yellow: Permission not yet requested")
                Text("🟢 Green: Permission granted")
                Text("🔴 Red: Permission denied or missing entitlement")
            }

            Button("Request Automation Permission") {
                onRequestPermission()
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderedProminent)

            Text("If permission is denied, you can re-enable it in System Settings → Privacy & Security → Automation.")
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .padding()
        .frame(width: 450, height: 300)
    }
}

struct ToolsHelpSheet: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "terminal")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Required Tools")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }

            Text("The app requires these command-line tools to function:")
                .font(.body)

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
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)

            Text("These tools are typically included with macOS and Xcode Command Line Tools.")
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450, height: 300)
    }
}

// MARK: - Extensions

extension LightState {
    var description: String {
        switch self {
        case .green: return "Ready"
        case .yellow: return "Setup"
        case .red: return "Missing"
        }
    }
}