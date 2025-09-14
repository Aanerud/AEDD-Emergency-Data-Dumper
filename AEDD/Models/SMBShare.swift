import Foundation

struct SMBShare: Identifiable, Equatable, Codable, Hashable {
    let name: String
    let type: String
    let host: String

    var id: String {
        return "\(host)_\(name)"
    }

    var mountPath: URL {
        return URL(fileURLWithPath: "/Volumes/\(name)")
    }

    var isValidForMounting: Bool {
        return type.lowercased() == "disk" && !name.contains("$")
    }

    static func == (lhs: SMBShare, rhs: SMBShare) -> Bool {
        return lhs.name == rhs.name && lhs.host == rhs.host
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(host)
    }
}

struct SMBCredentials: Codable {
    let username: String
    let password: String
    let saveToKeychain: Bool

    var formattedUsername: String {
        // Extract just the username part, removing domain prefix
        if username.contains("\\") {
            let components = username.components(separatedBy: "\\")
            if components.count == 2 {
                return components[1] // Return just the username part
            }
        }
        return username
    }

    var keychainAccount: String {
        return username
    }
}

enum SMBConnectionError: LocalizedError {
    case authenticationFailed
    case hostUnreachable
    case shareEnumerationFailed
    case mountFailed(String)
    case unmountFailed(String)
    case invalidCredentials
    case networkError
    case noCredentialsStored

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Authentication failed. Please check your username and password."
        case .hostUnreachable:
            return "Cannot reach the server. Please check the network connection."
        case .shareEnumerationFailed:
            return "Failed to list shares on the server."
        case .mountFailed(let share):
            return "Failed to mount share '\(share)'."
        case .unmountFailed(let path):
            return "Failed to unmount '\(path)'."
        case .invalidCredentials:
            return "Invalid credentials provided."
        case .networkError:
            return "Network error occurred."
        case .noCredentialsStored:
            return "No credentials stored. Please connect to the server first."
        }
    }
}