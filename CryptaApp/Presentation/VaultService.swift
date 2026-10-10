import Foundation
import CryptaCore

/// The presentation boundary is injectable; production always uses the real CryptaCore actor.
public protocol VaultService: Sendable {
    func create(at url: URL, passphrase: String, name: String, createdAt: Date, parameters: KDFParameters) async throws -> Vault
    func open(at url: URL, passphrase: String) async throws
    func readVault() async throws -> Vault
    func save(vault: Vault, modifiedAt: Date) async throws -> Vault
    func changePassphrase(current: String, new: String, parameters: KDFParameters) async throws
    func lock() async
}

extension VaultEngine: VaultService {}

public enum EntryKind: String, CaseIterable, Identifiable, Sendable {
    case credential, apiToken, secureNote, customSecret
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .credential: "Credential"
        case .apiToken: "API key or token"
        case .secureNote: "Secure note"
        case .customSecret: "Custom secret"
        }
    }
    var plural: String {
        switch self {
        case .credential: "Credentials"
        case .apiToken: "API keys & tokens"
        case .secureNote: "Secure notes"
        case .customSecret: "Custom secrets"
        }
    }
    var symbol: String {
        switch self {
        case .credential: "key.horizontal"
        case .apiToken: "terminal"
        case .secureNote: "note.text"
        case .customSecret: "square.grid.2x2"
        }
    }
}

public enum VaultScreen: Sendable { case welcome, create, locked, unlocked }
public enum VaultFilter: Hashable, Sendable { case all, favorites }

struct UserFacingError {
    static func message(_ error: Error) -> String {
        guard let error = error as? VaultError else {
            return "The operation could not be completed. Your last confirmed save is unchanged unless a storage error was reported."
        }
        switch error {
        case .authenticationFailed: return "The passphrase is incorrect, or this vault has been damaged or modified."
        case .unsupportedFormat, .unsupportedPayload: return "This vault uses a format or entry type this version of Crypta cannot open. Try a compatible version. The file has not been changed."
        case .invalidFormat, .invalidPayload: return "The vault or entry is invalid. Check required fields, dates, tags, and field lengths."
        case .resourceLimit: return "A file, field, or collection exceeds Crypta’s limits. Metadata is limited to 4 KiB, secret text to 1 MiB, and the vault payload to 16 MiB."
        case .invalidPassphrase: return "Enter a nonempty master passphrase."
        case .conflict: return "This vault changed or is being written elsewhere. Your draft is still here. Do not overwrite the other copy; keep one writer, then reopen the current file."
        case .unsafeFile: return "Choose a regular vault file, not a symbolic link, hard link, or special file."
        case .fileAccess: return "Crypta could not read or save this file. Check folder access, free space, and whether the drive is available, then try again."
        case .durabilityUncertain: return "Storage failed after the file was replaced. Crypta has locked the vault. Reopen and inspect it before making another change."
        case .locked: return "Unlock the vault before continuing."
        case .cryptoUnavailable, .allocationFailed: return "Crypta could not allocate the resources required for encryption. Close other applications and try again. Encryption settings have not been weakened."
        }
    }
}
