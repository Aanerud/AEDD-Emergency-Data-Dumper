import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var smbManager: SMBManager
    @Binding var showingConnectionSheet: Bool
    @Binding var showingShareSelector: Bool
    @State private var showingSettings = false

    var body: some View {
        HStack {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.title)
                .foregroundColor(.accentColor)

            Text("AEDD - Emergency Data Dumper")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            HStack(spacing: 12) {
                Button("Connect to Server") {
                    showingConnectionSheet = true
                }
                .disabled(smbManager.isConnecting)

                Divider()
                    .frame(height: 20)

                Button("Unmount All") {
                    Task {
                        await smbManager.unmountAll()
                    }
                }
                .disabled(smbManager.mountedShares.isEmpty)

                Button("Settings") {
                    showingSettings = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(SMBManager())
                .environmentObject(SettingsManager())
        }
    }
}

#Preview {
    ToolbarView(
        showingConnectionSheet: .constant(false),
        showingShareSelector: .constant(false)
    )
    .environmentObject(SMBManager())
}