import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
class SettingsManager: ObservableObject {
    @Published var settings = AppSettings.shared

    private let userDefaults = UserDefaults.standard
    private let settingsKey = "AEDDSettings"
    private var keychainService = KeychainService()

    init() {
        loadSettings()
    }

    func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            userDefaults.set(data, forKey: settingsKey)
            LogManager.shared.logInfo("Settings saved successfully")
        } catch {
            LogManager.shared.logError("Failed to save settings: \(error.localizedDescription)")
        }
    }

    func loadSettings() {
        guard let data = userDefaults.data(forKey: settingsKey) else {
            settings = AppSettings.shared
            return
        }

        do {
            settings = try JSONDecoder().decode(AppSettings.self, from: data)
            LogManager.shared.logDebug("Settings loaded successfully")
        } catch {
            LogManager.shared.logError("Failed to load settings: \(error.localizedDescription)")
            settings = AppSettings.shared
        }
    }

    func resetToDefaults() {
        settings = AppSettings()
        saveSettings()
        LogManager.shared.logInfo("Settings reset to defaults")
    }

    func updateDefaultServer(_ server: String) {
        settings.defaultServer = server
        saveSettings()
    }

    func updateServerAlias(_ alias: String, for host: String) {
        settings.serverAliases[host] = alias
        saveSettings()
    }

    func removeServerAlias(for host: String) {
        settings.serverAliases.removeValue(forKey: host)
        saveSettings()
    }

    func updateLogRetention(days: Int) {
        settings.logRetentionDays = max(1, min(365, days))
        saveSettings()
    }

    func updateRsyncFlags(_ flags: RsyncFlags) {
        settings.defaultRsyncFlags = flags
        saveSettings()
    }

    func getStoredCredentials() -> [String] {
        do {
            return try keychainService.listStoredCredentials()
        } catch {
            LogManager.shared.logError("Failed to list stored credentials: \(error.localizedDescription)")
            return []
        }
    }

    func deleteStoredCredentials(_ account: String) {
        let components = account.components(separatedBy: "@")
        guard components.count == 2 else { return }

        let username = components[0]
        let host = components[1]

        do {
            try keychainService.deleteCredentials(for: username, host: host)
            LogManager.shared.logInfo("Deleted stored credentials for \(account)")
        } catch {
            LogManager.shared.logError("Failed to delete credentials for \(account): \(error.localizedDescription)")
        }
    }

    func exportSettings() -> URL? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(settings)

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType.json]
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            savePanel.nameFieldStringValue = "AEDD-Settings-\(formatter.string(from: Date())).json"

            if savePanel.runModal() == .OK, let url = savePanel.url {
                try data.write(to: url)
                return url
            }
        } catch {
            LogManager.shared.logError("Failed to export settings: \(error.localizedDescription)")
        }
        return nil
    }

    func importSettings(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let importedSettings = try JSONDecoder().decode(AppSettings.self, from: data)
            settings = importedSettings
            saveSettings()
            LogManager.shared.logInfo("Settings imported successfully from \(url.lastPathComponent)")
            return true
        } catch {
            LogManager.shared.logError("Failed to import settings: \(error.localizedDescription)")
            return false
        }
    }
}