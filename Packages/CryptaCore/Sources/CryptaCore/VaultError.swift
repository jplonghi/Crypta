import Foundation

/// Deliberately contains no path, passphrase, or plaintext diagnostic context.
public enum VaultError: Error, Equatable, Sendable {
    case invalidFormat, unsupportedFormat, resourceLimit, invalidPassphrase
    case authenticationFailed, cryptoUnavailable, allocationFailed, locked
    case invalidPayload, unsupportedPayload, conflict, unsafeFile, fileAccess, durabilityUncertain
}
