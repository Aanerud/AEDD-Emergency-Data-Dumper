import Foundation

struct AppSettings: Codable {
    var defaultRsyncFlags: RsyncFlags = RsyncFlags()
    var logRetentionDays: Int = 30
    var alwaysMountReadOnly: Bool = true
    var defaultServer: String = "192.168.1.20"
    var serverAliases: [String: String] = [:]

    static let shared = AppSettings()
}

struct RsyncFlags: Codable {
    var preserveMetadata: Bool = true
    var verifyResumedCopies: Bool = true
    var showHiddenFiles: Bool = false
    var followSymlinks: Bool = false

    var arguments: [String] {
        var args: [String] = []

        if preserveMetadata {
            // Use standard rsync archive mode (equivalent to -rlptgoD)
            args.append("-a")
        } else {
            args.append("-r")
        }

        // Standard rsync options available on macOS
        args.append(contentsOf: ["--partial", "--progress"])

        if !showHiddenFiles {
            args.append("--exclude=.DS_Store")
        }

        if followSymlinks {
            args.append("-L")
        }

        return args
    }
}

enum ServerHost: String, CaseIterable {
    case server1 = "192.168.1.20"
    case server2 = "192.168.1.23"

    var displayName: String {
        return AppSettings.shared.serverAliases[self.rawValue] ?? self.rawValue
    }

    static let conflictingHosts = [
        "production.ad.uhoert.no",
        "192.168.1.20",
        "192.168.1.21",
        "192.168.1.22",
        "192.168.1.23"
    ]
}