import Foundation
import UniformTypeIdentifiers

@MainActor
class BookmarkManager: ObservableObject {
    @Published var securityScopedDestinations: [URL] = []

    private let bookmarksKey = "SecurityScopedBookmarks"
    private var accessingURLs: Set<URL> = []

    init() {
        loadBookmarks()
    }

    deinit {
        stopAccessingAllURLs()
    }

    // MARK: - Bookmark Management

    func addDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Destination Folder"
        panel.message = "Select where to copy files from SMB shares"

        panel.begin { response in
            Task { @MainActor in
                if response == .OK, let url = panel.url {
                    self.addSecurityScopedURL(url)
                }
            }
        }
    }

    private func addSecurityScopedURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            LogManager.shared.logError("Failed to start accessing security scoped resource: \(url)")
            return
        }

        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            // Store bookmark
            var bookmarks = loadStoredBookmarks()
            bookmarks.append(bookmarkData)
            saveBookmarks(bookmarks)

            // Add to active list
            securityScopedDestinations.append(url)
            accessingURLs.insert(url)

            LogManager.shared.logInfo("Added security-scoped destination: \(url.path)")

        } catch {
            LogManager.shared.logError("Failed to create bookmark for \(url): \(error)")
            url.stopAccessingSecurityScopedResource()
        }
    }

    func removeDestination(_ url: URL) {
        // Stop accessing if we're currently accessing it
        if accessingURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            accessingURLs.remove(url)
        }

        // Remove from active list
        securityScopedDestinations.removeAll { $0 == url }

        // Remove from stored bookmarks
        let bookmarks = loadStoredBookmarks()
        let updatedBookmarks = bookmarks.filter { bookmarkData in
            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                return resolvedURL != url
            } catch {
                // Remove invalid bookmarks
                return false
            }
        }
        saveBookmarks(updatedBookmarks)

        LogManager.shared.logInfo("Removed destination: \(url.path)")
    }

    private func loadBookmarks() {
        let bookmarks = loadStoredBookmarks()

        for bookmarkData in bookmarks {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    LogManager.shared.logWarning("Bookmark is stale for: \(url.path)")
                    continue
                }

                guard url.startAccessingSecurityScopedResource() else {
                    LogManager.shared.logError("Failed to start accessing security scoped resource: \(url)")
                    continue
                }

                securityScopedDestinations.append(url)
                accessingURLs.insert(url)
                LogManager.shared.logInfo("Restored security-scoped access to: \(url.path)")

            } catch {
                LogManager.shared.logError("Failed to resolve bookmark: \(error)")
            }
        }
    }

    private func loadStoredBookmarks() -> [Data] {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([Data].self, from: data)
        } catch {
            LogManager.shared.logError("Failed to decode bookmarks: \(error)")
            return []
        }
    }

    private func saveBookmarks(_ bookmarks: [Data]) {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            UserDefaults.standard.set(data, forKey: bookmarksKey)
            LogManager.shared.logInfo("Saved \(bookmarks.count) bookmarks")
        } catch {
            LogManager.shared.logError("Failed to encode bookmarks: \(error)")
        }
    }

    private func stopAccessingAllURLs() {
        for url in accessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessingURLs.removeAll()
    }

    // MARK: - Validation

    func validateDestination(_ url: URL) -> Bool {
        let testURL = url.appendingPathComponent(".aedd_write_test_\(UUID().uuidString)")

        do {
            try "AEDD write test".data(using: .utf8)?.write(to: testURL, options: .atomic)
            try FileManager.default.removeItem(at: testURL)
            return true
        } catch {
            LogManager.shared.logError("Destination validation failed for \(url.path): \(error)")
            return false
        }
    }

    // MARK: - File Operations

    func canWriteToDestination(_ url: URL) -> Bool {
        guard securityScopedDestinations.contains(url) else { return false }
        return validateDestination(url)
    }

    func chooseDestinationForDrop() -> URL? {
        if securityScopedDestinations.isEmpty {
            // No destinations available, prompt user to add one
            DispatchQueue.main.async {
                self.addDestination()
            }
            return nil
        }

        if securityScopedDestinations.count == 1 {
            return securityScopedDestinations.first
        }

        // Multiple destinations - could show picker UI
        // For now, return first valid one
        return securityScopedDestinations.first { canWriteToDestination($0) }
    }

    // MARK: - Volume Access

    func requestVolumeAccess(for url: URL) -> Bool {
        // For network volumes, the system should prompt for access automatically
        // when we try to read/write. This method can be used to pre-check.

        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .volumeIsLocalKey,
                .volumeIsRemovableKey,
                .volumeIsNetworkKey
            ])

            if let isNetwork = resourceValues.volumeIsNetwork, isNetwork {
                LogManager.shared.logInfo("Accessing network volume: \(url.path)")
            }

            if let isRemovable = resourceValues.volumeIsRemovable, isRemovable {
                LogManager.shared.logInfo("Accessing removable volume: \(url.path)")
            }

            return true
        } catch {
            LogManager.shared.logError("Failed to get volume info for \(url.path): \(error)")
            return false
        }
    }
}

// MARK: - Extensions

extension URL {
    var isNetworkVolume: Bool {
        do {
            let resourceValues = try resourceValues(forKeys: [.volumeIsNetworkKey])
            return resourceValues.volumeIsNetwork == true
        } catch {
            return false
        }
    }

    var isRemovableVolume: Bool {
        do {
            let resourceValues = try resourceValues(forKeys: [.volumeIsRemovableKey])
            return resourceValues.volumeIsRemovable == true
        } catch {
            return false
        }
    }

    var displayName: String {
        do {
            let resourceValues = try resourceValues(forKeys: [.localizedNameKey])
            return resourceValues.localizedName ?? lastPathComponent
        } catch {
            return lastPathComponent
        }
    }
}