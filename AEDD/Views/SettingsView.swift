import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showingImportDialog = false
    @State private var showingCredentialsManager = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            TabView {
            RsyncSettingsView()
                .tabItem {
                    Label("Rsync", systemImage: "arrow.triangle.2.circlepath")
                }

            ServerSettingsView()
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }

            LogsSettingsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }

            CredentialsSettingsView()
                .tabItem {
                    Label("Credentials", systemImage: "key")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            DebugSettingsView()
                .tabItem {
                    Label("Debug", systemImage: "wrench.and.screwdriver")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 550)
        .onDisappear {
            settingsManager.saveSettings()
        }
    }
}

struct RsyncSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rsync Default Options")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Configure the default rsync behavior for copy operations.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Preserve metadata (extended attributes, creation times, flags)",
                       isOn: .init(
                           get: { settingsManager.settings.defaultRsyncFlags.preserveMetadata },
                           set: { newValue in
                               settingsManager.settings.defaultRsyncFlags.preserveMetadata = newValue
                           }
                       ))

                Toggle("Verify resumed copies (--append-verify)",
                       isOn: .init(
                           get: { settingsManager.settings.defaultRsyncFlags.verifyResumedCopies },
                           set: { newValue in
                               settingsManager.settings.defaultRsyncFlags.verifyResumedCopies = newValue
                           }
                       ))

                Toggle("Show hidden files (include .DS_Store)",
                       isOn: .init(
                           get: { settingsManager.settings.defaultRsyncFlags.showHiddenFiles },
                           set: { newValue in
                               settingsManager.settings.defaultRsyncFlags.showHiddenFiles = newValue
                           }
                       ))

                Toggle("Follow symlinks (-L)",
                       isOn: .init(
                           get: { settingsManager.settings.defaultRsyncFlags.followSymlinks },
                           set: { newValue in
                               settingsManager.settings.defaultRsyncFlags.followSymlinks = newValue
                           }
                       ))
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview command:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("rsync \(settingsManager.settings.defaultRsyncFlags.arguments.joined(separator: " ")) SOURCE DEST")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
            }
        }
        .padding()
    }
}

struct ServerSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var newHost = ""
    @State private var newAlias = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Server Configuration")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Server")
                    .font(.headline)

                HStack {
                    Text("Server IP:")
                    TextField("192.168.1.20", text: .init(
                        get: { settingsManager.settings.defaultServer },
                        set: { newValue in
                            settingsManager.settings.defaultServer = newValue
                            settingsManager.saveSettings()
                        }
                    ))
                    .frame(width: 150)
                }

                Text("This server will be used for connections.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Text("Server Aliases (Optional)")
                .font(.headline)

            Text("Add custom display names for servers.")
                .foregroundColor(.secondary)

            List {
                ForEach(Array(settingsManager.settings.serverAliases.keys.sorted()), id: \.self) { host in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host)
                                .font(.body)
                            Text(settingsManager.settings.serverAliases[host] ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Edit") {

                        }
                        .buttonStyle(.plain)

                        Button("Remove") {
                            settingsManager.removeServerAlias(for: host)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(height: 200)

            HStack {
                TextField("Server IP", text: $newHost)
                TextField("Display Name", text: $newAlias)
                Button("Add") {
                    if !newHost.isEmpty && !newAlias.isEmpty {
                        settingsManager.updateServerAlias(newAlias, for: newHost)
                        newHost = ""
                        newAlias = ""
                    }
                }
                .disabled(newHost.isEmpty || newAlias.isEmpty)
            }

            Spacer()
        }
        .padding()
    }
}

struct LogsSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showingLogsFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Log Management")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Log retention (days):")
                    TextField("Days", value: .init(
                        get: { settingsManager.settings.logRetentionDays },
                        set: { newValue in
                            settingsManager.settings.logRetentionDays = max(1, min(365, newValue))
                        }
                    ), format: .number)
                    .frame(width: 80)
                    .onSubmit {
                        settingsManager.saveSettings()
                    }
                }

                Text("Log files older than \(settingsManager.settings.logRetentionDays) days will be automatically deleted.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Current logs:")
                    .font(.headline)

                HStack {
                    Text("Total size: \(LogManager.shared.getLogFileSize())")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Open Logs Folder") {
                        LogManager.shared.openLogsFolder()
                    }
                    .buttonStyle(.bordered)

                    Button("Archive Logs") {
                        if let archiveURL = LogManager.shared.archiveLogs() {
                            NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding()
    }
}

struct CredentialsSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var storedCredentials: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stored Credentials")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Manage SMB credentials stored in the system keychain.")
                .foregroundColor(.secondary)

            if storedCredentials.isEmpty {
                VStack {
                    Spacer()
                    Text("No stored credentials")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(storedCredentials, id: \.self) { credential in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(credential)
                                    .font(.body)
                                Text("SMB Credential")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Delete") {
                                settingsManager.deleteStoredCredentials(credential)
                                refreshCredentials()
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            HStack {
                Button("Refresh") {
                    refreshCredentials()
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Spacer()
        }
        .padding()
        .onAppear {
            refreshCredentials()
        }
    }

    private func refreshCredentials() {
        storedCredentials = settingsManager.getStoredCredentials()
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showingImportDialog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General Settings")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Always mount read-only", isOn: .constant(true))
                    .disabled(true)

                Text("This setting is enforced for security and cannot be changed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Settings Management")
                    .font(.headline)

                HStack {
                    Button("Export Settings") {
                        if let url = settingsManager.exportSettings() {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Import Settings") {
                        showingImportDialog = true
                    }
                    .buttonStyle(.bordered)

                    Button("Reset to Defaults") {
                        settingsManager.resetToDefaults()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("Aanerud EMC - Emergency Data Dumper")
                    .font(.headline)
                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showingImportDialog,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                _ = settingsManager.importSettings(from: url)
            case .failure:
                break
            }
        }
    }
}

struct DebugSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var testOutput = ""
    @State private var isTestingConnection = false
    @State private var testHost = "192.168.0.81"
    @State private var testUsername = "aanerud"
    @State private var testPassword = "platino"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Debug & Testing")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Test SMB connections directly to debug issues.")
                .foregroundColor(.secondary)

            GroupBox("Manual SMB Test") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Host:")
                        TextField("Server Host", text: $testHost)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Username:")
                        TextField("Username", text: $testUsername)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Password:")
                        SecureField("Password", text: $testPassword)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Button(isTestingConnection ? "Testing..." : "Test SMB Connection") {
                            testSMBConnection()
                        }
                        .disabled(isTestingConnection)
                        .buttonStyle(.borderedProminent)

                        Button("Test Manual CLI") {
                            testManualCLI()
                        }
                        .buttonStyle(.bordered)

                        Button("Clear Output") {
                            testOutput = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            GroupBox("Test Output") {
                ScrollView {
                    Text(testOutput.isEmpty ? "No test output yet..." : testOutput)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 200)
            }

            Spacer()
        }
        .padding()
    }

    private func testSMBConnection() {
        Task {
            await MainActor.run {
                isTestingConnection = true
                testOutput = "=== SMB Connection Test Started ===\n"
                testOutput += "Host: \(testHost)\n"
                testOutput += "Username: \(testUsername)\n"
                testOutput += "Time: \(Date())\n\n"
            }

            let credentials = SMBCredentials(username: testUsername, password: testPassword, saveToKeychain: false)
            let smbManager = SMBManager()

            // Connect to SMB server
            await smbManager.connect(to: testHost, credentials: credentials)

            // Check the results
            await MainActor.run {
                if let error = smbManager.connectionError {
                    testOutput += "❌ CONNECTION ERROR: \(error.localizedDescription)\n"
                    testOutput += "\n=== Test Failed ===\n"
                } else {
                    let shares = smbManager.availableShares
                    testOutput += "✅ SUCCESS: Found \(shares.count) shares:\n"
                    for share in shares {
                        testOutput += "  - \(share.name) (\(share.type))\n"
                    }
                    testOutput += "\n=== Test Complete ===\n"
                }
            }

            await MainActor.run {
                isTestingConnection = false
            }
        }
    }

    private func testManualCLI() {
        Task {
            await MainActor.run {
                testOutput = "=== Manual CLI Test Started ===\n"
                testOutput += "Testing smbutil command manually...\n\n"
            }

            // Test the raw smbutil command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
            process.arguments = ["view", "//\(testUsername)@\(testHost)"]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Set minimal environment
            process.environment = [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": NSHomeDirectory(),
                "USER": NSUserName()
            ]

            await MainActor.run {
                testOutput += "Command: /usr/bin/smbutil view //\(testUsername)@\(testHost)\n"
                testOutput += "Environment: PATH, HOME, USER set\n"
                testOutput += "Starting process...\n\n"
            }

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                await MainActor.run {
                    testOutput += "Exit Code: \(process.terminationStatus)\n"
                    testOutput += "STDOUT:\n\(output)\n"
                    if !errorOutput.isEmpty {
                        testOutput += "STDERR:\n\(errorOutput)\n"
                    }
                    testOutput += "\n=== Manual CLI Test Complete ===\n"
                }
            } catch {
                await MainActor.run {
                    testOutput += "❌ Process launch failed: \(error)\n"
                    testOutput += "\n=== Manual CLI Test Failed ===\n"
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}