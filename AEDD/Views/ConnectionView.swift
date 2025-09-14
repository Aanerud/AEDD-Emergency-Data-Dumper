import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var smbManager: SMBManager
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var saveToKeychain = false
    @State private var selectedHost = ""

    let onConnected: (SMBCredentials) -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "network")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Connect to SMB Server")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Enter your credentials to connect to the server and browse available shares.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("e.g., AD\\username", text: $username)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

            }

            Button("Connect") {
                connectToServer(settingsManager.settings.defaultServer)
            }
            .buttonStyle(.borderedProminent)
            .disabled(smbManager.isConnecting || username.isEmpty || password.isEmpty)

            if smbManager.isConnecting {
                VStack(spacing: 8) {
                    Text("Connecting to \(settingsManager.settings.defaultServer)...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Running network diagnostics...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = smbManager.connectionError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            selectedHost = settingsManager.settings.defaultServer
        }
    }

    private func connectToServer(_ host: String) {
        let credentials = SMBCredentials(
            username: username,
            password: password,
            saveToKeychain: saveToKeychain
        )

        Task {
            await smbManager.connect(to: host, credentials: credentials)

            if smbManager.connectionError == nil {
                await MainActor.run {
                    onConnected(credentials)
                }
            }
        }
    }
}

#Preview {
    ConnectionView(onConnected: { _ in })
        .environmentObject(SMBManager())
        .environmentObject(SettingsManager())
}