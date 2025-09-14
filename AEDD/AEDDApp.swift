import SwiftUI

@main
struct AEDDApp: App {
    @StateObject private var jobManager = JobManager()
    @StateObject private var smbManager = SMBManager()
    @StateObject private var settingsManager = SettingsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(jobManager)
                .environmentObject(smbManager)
                .environmentObject(settingsManager)
                .onAppear {
                    LogManager.shared.setup()
                }
        }
        .windowToolbarStyle(UnifiedWindowToolbarStyle())
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settingsManager)
        }
    }
}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Open Logs Folder") {
                LogManager.shared.openLogsFolder()
            }
            .keyboardShortcut("L", modifiers: [.command, .shift])
        }
    }
}