import Foundation

/// Headless, single-vault engine. Blocking native operations execute on this actor, never the UI actor.
/// Reads and writes the current payload structure. Unsupported data is never installed or saved.
public actor VaultEngine {
    private struct Session {
        let key: SecretBuffer
        var container: VaultFormat.Container
        let url: URL
        var version: EncryptedFileStore.Version
    }
    private var session: Session?
    private let store: EncryptedFileStore

    public init() { store = EncryptedFileStore() }
    init(store: EncryptedFileStore) { self.store = store }

    public static var cryptoVersion: String { Crypto.version }
    public var isUnlocked: Bool { session != nil }
    /// A capability report, not a claim that Swift's other plaintext copies are locked.
    public var isKeyMemoryLocked: Bool { session?.key.isMemoryLocked ?? false }

    public static func passphrasesMatch(_ first: String, _ second: String) -> Bool {
        first.utf8.elementsEqual(second.utf8)
    }

    /// Refuses to overwrite an existing file. On failure, this engine remains locked.
    @discardableResult
    public func create(at url: URL, passphrase: String, name: String, createdAt: Date = Date(),
                       parameters: KDFParameters = .standard) throws -> Vault {
        guard session == nil else { throw VaultError.conflict }
        try Task.checkCancellation()
        try parameters.validate()
        let core = try VaultFormat.core()
        let vault = Vault(vaultID: try VaultID(bytes: core.subdata(in: 16..<32)), name: name,
                          createdAt: try VaultValidation.timestamp(createdAt))
        let payload = try VaultCodec.encode(vault, expectedID: vault.vaultID)
        let slot = try VaultFormat.slot(parameters: parameters)
        let key = try Crypto.randomKey()
        let kek = try Crypto.derive(passphrase, salt: slot.subdata(in: 16..<32), parameters: parameters, creating: true)
        defer { kek.wipe() }
        let wrapped = try Crypto.sealKey(key, key: kek, nonce: slot.subdata(in: 32..<56), aad: VaultFormat.wrapLabel + core + slot)
        let bytes = core + slot + wrapped + (try VaultFormat.payload(payload, core: core, key: key))
        try Task.checkCancellation()
        let snapshot = try store.commit(bytes, to: url, expecting: nil)
        session = Session(key: key, container: try VaultFormat.parse(bytes), url: url, version: snapshot.version)
        return vault
    }

    /// No session is installed until both tags, payload schema and bound vault identity validate.
    public func open(at url: URL, passphrase: String) throws {
        guard session == nil else { throw VaultError.conflict }
        try Task.checkCancellation()
        let snapshot = try store.read(url)
        let container = try VaultFormat.parse(snapshot.bytes)
        let key = try unwrap(container, passphrase: passphrase)
        let (plaintext, length) = try Crypto.open(container.ciphertext, key: key,
                                                 nonce: container.payloadNonce, aad: container.payloadAAD)
        defer { plaintext.wipe() }
        _ = try VaultCodec.decode(plaintext.copyData(count: length), expectedID: VaultID(bytes: container.core.subdata(in: 16..<32)))
        try Task.checkCancellation()
        session = Session(key: key, container: container, url: url, version: snapshot.version)
    }

    /// Caller owns the returned plaintext and must release it on lock. The engine does not cache it.
    public func readVault() throws -> Vault {
        guard let session else { throw VaultError.locked }
        let (plaintext, length) = try Crypto.open(session.container.ciphertext, key: session.key,
            nonce: session.container.payloadNonce, aad: session.container.payloadAAD)
        defer { plaintext.wipe() }
        return try VaultCodec.decode(plaintext.copyData(count: length),
                                     expectedID: VaultID(bytes: session.container.core.subdata(in: 16..<32)))
    }

    /// Acknowledges only a committed encrypted save. Pre-rename failure preserves this session.
    @discardableResult
    public func save(vault: Vault, modifiedAt: Date = Date()) throws -> Vault {
        guard let current = session else { throw VaultError.locked }
        try Task.checkCancellation()
        let previous = try readVault()
        guard vault.vaultID == previous.vaultID, vault.createdAt == previous.createdAt else { throw VaultError.invalidPayload }
        guard vault.revision == previous.revision, vault.modifiedAt == previous.modifiedAt else { throw VaultError.conflict }
        try VaultValidation.validate(vault, expectedID: previous.vaultID)
        let previousEntries = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.id, $0) })
        for entry in vault.entries {
            if let stored = previousEntries[entry.id] {
                guard entry.createdAt == stored.createdAt, entry.modifiedAt >= stored.modifiedAt else { throw VaultError.invalidPayload }
            }
        }
        var updated = vault
        try updated.advance(modifiedAt: max(previous.modifiedAt, VaultValidation.timestamp(modifiedAt)))
        let payload = try VaultCodec.encode(updated, expectedID: previous.vaultID)
        let bytes = current.container.bytes.subdata(in: 0..<160)
            + (try VaultFormat.payload(payload, core: current.container.core, key: current.key))
        try Task.checkCancellation()
        try commit(bytes, current: current)
        return updated
    }

    public func changePassphrase(current old: String, new: String,
                                 parameters: KDFParameters = .standard) throws {
        guard let current = session else { throw VaultError.locked }
        try Task.checkCancellation()
        // Verify the current file before spending time deriving keys or changing the envelope.
        guard try store.read(current.url).version == current.version else { throw VaultError.conflict }
        let recovered = try unwrap(current.container, passphrase: old)
        defer { recovered.wipe() }
        guard Crypto.equal(recovered, current.key) else { throw VaultError.authenticationFailed }
        let slot = try VaultFormat.slot(parameters: parameters)
        let kek = try Crypto.derive(new, salt: slot.subdata(in: 16..<32), parameters: parameters, creating: true)
        defer { kek.wipe() }
        let wrapped = try Crypto.sealKey(current.key, key: kek, nonce: slot.subdata(in: 32..<56),
            aad: VaultFormat.wrapLabel + current.container.core + slot)
        let bytes = current.container.core + slot + wrapped
            + current.container.bytes.subdata(in: 160..<current.container.bytes.count)
        try Task.checkCancellation()
        try commit(bytes, current: current)
    }

    /// Serial with every operation: there are no suspension points inside a transaction.
    /// UI must obscure immediately before awaiting this call; native KDF work is not interruptible.
    public func lock() {
        session?.key.wipe()
        session = nil
    }

    private func unwrap(_ container: VaultFormat.Container, passphrase: String) throws -> SecretBuffer {
        let kek = try Crypto.derive(passphrase, salt: container.salt, parameters: container.parameters)
        defer { kek.wipe() }
        let (key, count) = try Crypto.open(container.wrappedKey, key: kek,
                                          nonce: container.wrapNonce, aad: container.wrapAAD)
        guard count == 32 else { throw VaultError.authenticationFailed }
        return key
    }

    private func commit(_ bytes: Data, current: Session) throws {
        do {
            let snapshot = try store.commit(bytes, to: current.url, expecting: current.version)
            session = Session(key: current.key, container: try VaultFormat.parse(bytes), url: current.url, version: snapshot.version)
        } catch VaultError.durabilityUncertain {
            // Disk may hold the new envelope. Require explicit re-open, never a blind retry.
            lock()
            throw VaultError.durabilityUncertain
        }
    }
}
