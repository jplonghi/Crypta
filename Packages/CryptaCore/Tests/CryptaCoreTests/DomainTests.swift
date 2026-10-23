import Foundation
import Testing
@testable import CryptaCore

private func sampleVault() throws -> Vault {
    let bytes = try fixture("reference-payload.json")
    let id = try VaultID(hex: "000102030405060708090a0b0c0d0e0f")
    var vault = try VaultCodec.decode(bytes, expectedID: id)
    vault.entries = [
        VaultEntry(title: " Credential ", createdAt: 10, modifiedAt: 20, tags: ["Production 🗝️", "é"], isFavorite: true,
                   fields: .credential(.init(username: "alice@example.com", password: "public-secret 🔑\0after", websiteURL: "https://example.com/a?x=1", notes: "line 1\nline 2"))),
        VaultEntry(title: "Token", createdAt: 10, modifiedAt: 20, fields: .apiToken(.init(service: "Example", token: "public-token", environment: .production, expiresAt: 253_402_300_799_999, notes: "notes"))),
        VaultEntry(title: "Secure note", createdAt: 10, modifiedAt: 20, fields: .secureNote(.init(content: "public-note 📝\nSecond line"))),
        VaultEntry(title: "Custom", createdAt: 10, modifiedAt: 20, tags: ["Production 🗝️"], fields: .customSecret(.init(customFields: [
            .init(name: "visible", value: "plain-display-secret", isSecret: false),
            .init(name: "hidden", value: "hidden-display-secret", isSecret: true)
        ])))
    ]
    return vault
}

private func jsonObject(_ vault: Vault) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: VaultCodec.encode(vault, expectedID: vault.vaultID)) as? [String: Any])
}
private func jsonBytes(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}
private func editEntry(_ object: inout [String: Any], _ edit: (inout [String: Any]) -> Void) throws {
    var entries = try #require(object["entries"] as? [[String: Any]])
    edit(&entries[0]); object["entries"] = entries
}

/// Makes intentionally invalid but authenticated containers using only public fixture key material.
private func container(with payload: Data) throws -> Data {
    let original = try fixture("reference-v1.crypta")
    let nonce = try Crypto.random(24)
    var descriptor = nonce
    VaultFormat.append(UInt64(payload.count + 16), size: 8, to: &descriptor)
    let core = original.subdata(in: 0..<48)
    let key = try SecretBuffer(Data(80..<112))
    return original.subdata(in: 0..<160) + descriptor
        + (try Crypto.seal(payload, key: key, nonce: nonce, aad: VaultFormat.payloadLabel + core + descriptor))
}

@Suite(.serialized)
struct DomainTests {
    @Test func allTypesRoundTripThroughEncryptedFile() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let engine = VaultEngine()
        var vault = try await engine.create(at: directory.vault, passphrase: testPassphrase, name: "Typed vault", createdAt: Date(timeIntervalSince1970: 0), parameters: testParameters)
        let model = try sampleVault()
        vault.entries = model.entries
        let saved = try await engine.save(vault: vault, modifiedAt: Date(timeIntervalSince1970: 1))
        #expect(saved.revision == 1)
        #expect(saved.modifiedAt == 1000)
        #expect(saved.entries == model.entries)
        // Includes values marked for plain display: display preferences do not bypass encryption.
        let bytes = try Data(contentsOf: directory.vault)
        for text in ["Typed vault", "alice@example.com", "public-secret", "public-token", "public-note", "plain-display-secret", "hidden-display-secret", "Production"] {
            #expect(bytes.range(of: Data(text.utf8)) == nil)
        }
        await engine.lock()
        let reopened = VaultEngine()
        try await reopened.open(at: directory.vault, passphrase: testPassphrase)
        let reopenedVault = try await reopened.readVault()
        #expect(reopenedVault == saved)
        #expect(Array(reopenedVault.entries[0].tags[1].utf8) == Array("é".utf8))
        #expect(reopenedVault.entries[0].isFavorite)
        let object = try jsonObject(saved)
        #expect(Set(object.keys) == Set(["vaultID", "name", "createdAt", "modifiedAt", "revision", "entries"]))
        let entries = try #require(object["entries"] as? [[String: Any]])
        for entry in entries {
            #expect(Set(entry.keys) == Set(["id", "type", "title", "createdAt", "modifiedAt", "tags", "isFavorite", "fields"]))
        }
        let json = try VaultCodec.encode(saved, expectedID: saved.vaultID)
        #expect(json == (try VaultCodec.encode(saved, expectedID: saved.vaultID)))
        #expect(try VaultCodec.decode(json, expectedID: saved.vaultID) == saved)
        for environment in TokenEnvironment.allCases {
            var variant = saved
            variant.entries[1].fields = .apiToken(.init(environment: environment, expiresAt: nil))
            let encoded = try VaultCodec.encode(variant, expectedID: variant.vaultID)
            #expect(try VaultCodec.decode(encoded, expectedID: variant.vaultID) == variant)
        }
    }

    @Test func typedEditsDeletionAndStaleSnapshot() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let engine = VaultEngine()
        let blank = try await engine.create(at: directory.vault, passphrase: testPassphrase, name: "Vault", parameters: testParameters)
        var edited = blank
        edited.entries.append(.init(title: "Note", createdAt: 1, tags: ["Production 🗝️"], fields: .secureNote(.init(content: "one"))))
        var saved = try await engine.save(vault: edited)
        await #expect(throws: VaultError.conflict) { try await engine.save(vault: blank) }
        let before = try Data(contentsOf: directory.vault)
        var dangling = saved; dangling.entries[0].tags = ["Work", "work"]
        await #expect(throws: VaultError.invalidPayload) { try await engine.save(vault: dangling) }
        #expect(try Data(contentsOf: directory.vault) == before)
        let entryID = saved.entries[0].id
        saved.entries[0].fields = .secureNote(.init(content: "two"))
        saved.entries[0].modifiedAt = 2
        saved = try await engine.save(vault: saved)
        #expect(saved.entries[0].id == entryID)
        #expect(saved.entries[0].createdAt == 1)
        #expect(saved.revision == 2)
        saved.entries.removeAll()
        let removed = try await engine.save(vault: saved)
        #expect(removed.entries.isEmpty && removed.revision == 3)
        await engine.lock()
        await #expect(throws: VaultError.locked) { try await engine.save(vault: removed) }
    }

    @Test func unknownTypesFieldsAndMissingKeys() throws {
        let sample = try sampleVault()
        let baseline = try jsonObject(sample)
        var invalid = [[String: Any]]()
        var root = baseline; root["future"] = "do not discard"; invalid.append(root)
        root = baseline; try editEntry(&root) { $0["type"] = "attachment" }; invalid.append(root)
        root = baseline; try editEntry(&root) { $0["future"] = 1 }; invalid.append(root)
        root = baseline; try editEntry(&root) { var fields = $0["fields"] as? [String: Any] ?? [:]; fields["future"] = "value"; $0["fields"] = fields }; invalid.append(root)
        root = baseline
        var customEntries = try #require(root["entries"] as? [[String: Any]])
        var customFields = try #require(customEntries[3]["fields"] as? [String: Any])
        var fields = try #require(customFields["customFields"] as? [[String: Any]])
        fields[0]["future"] = "retain me"; customFields["customFields"] = fields
        customEntries[3]["fields"] = customFields; root["entries"] = customEntries; invalid.append(root)
        for object in invalid {
            #expect(throws: VaultError.unsupportedPayload) { try VaultCodec.decode(jsonBytes(object), expectedID: sample.vaultID) }
        }
        root = baseline; root.removeValue(forKey: "name")
        #expect(throws: VaultError.invalidPayload) { try VaultCodec.decode(jsonBytes(root), expectedID: sample.vaultID) }
        root = baseline; try editEntry(&root) { $0.removeValue(forKey: "isFavorite") }
        #expect(throws: VaultError.invalidPayload) { try VaultCodec.decode(jsonBytes(root), expectedID: sample.vaultID) }
        // Required nullable fields must actually be present, even when their value is null.
        var token = sample; token.entries = [sample.entries[1]]
        root = try jsonObject(token)
        try editEntry(&root) { var fields = $0["fields"] as? [String: Any] ?? [:]; fields.removeValue(forKey: "expiresAt"); $0["fields"] = fields }
        #expect(throws: VaultError.invalidPayload) { try VaultCodec.decode(jsonBytes(root), expectedID: sample.vaultID) }
        root = try jsonObject(token)
        try editEntry(&root) { var fields = $0["fields"] as? [String: Any] ?? [:]; fields["environment"] = "future"; $0["fields"] = fields }
        #expect(throws: VaultError.unsupportedPayload) { try VaultCodec.decode(jsonBytes(root), expectedID: sample.vaultID) }
    }

    @Test func invalidAuthenticatedPayloadNeverUnlocks() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let baseline = try jsonObject(sampleVault())
        for kind in 0..<4 {
            var object = baseline
            switch kind {
            case 0: object.removeValue(forKey: "name")
            case 1: object["vaultID"] = String(repeating: "f", count: 32)
            case 2: object["future"] = "retain me"
            default: try editEntry(&object) { $0["type"] = "attachment" }
            }
            let bytes = try container(with: jsonBytes(object))
            try bytes.write(to: directory.vault)
            let engine = VaultEngine()
            await #expect(throws: (any Error).self) { try await engine.open(at: directory.vault, passphrase: testPassphrase) }
            #expect(await !engine.isUnlocked)
            await #expect(throws: VaultError.locked) { try await engine.readVault() }
            #expect(try Data(contentsOf: directory.vault) == bytes)
        }
    }

    @Test func identitiesReferencesAndChronology() throws {
        let original = try sampleVault()
        var invalid = [Vault]()
        var v = original; v.entries.append(v.entries[0]); invalid.append(v)
        v = original; v.entries[0].tags = ["Work", "WORK"]; invalid.append(v)
        v = original; v.entries[0].tags = [" "]; invalid.append(v)
        v = original; v.entries[0].modifiedAt = 9; invalid.append(v)
        v = original; v.entries[0].title = " \n\t"; invalid.append(v)
        v = original; v.entries[1].fields = .apiToken(.init(expiresAt: -1)); invalid.append(v)
        let field = CustomField(name: "duplicate")
        v = original; v.entries[3].fields = .customSecret(.init(customFields: [field, field])); invalid.append(v)
        for vault in invalid {
            #expect(throws: VaultError.invalidPayload) { try VaultCodec.encode(vault, expectedID: original.vaultID) }
        }
        let otherID = try VaultID(hex: String(repeating: "f", count: 32))
        #expect(throws: VaultError.invalidPayload) { try VaultCodec.encode(original, expectedID: otherID) }
        var object = try jsonObject(original)
        try editEntry(&object) { $0["id"] = "AAAAAAAA-AAAA-4AAA-AAAA-AAAAAAAAAAAA" }
        #expect(throws: VaultError.invalidPayload) { try VaultCodec.decode(jsonBytes(object), expectedID: original.vaultID) }
    }

    @Test func integersAreExactAndBounded() throws {
        let bytes = try fixture("reference-payload.json")
        let id = try sampleVault().vaultID
        let text = String(decoding: bytes, as: UTF8.self)
        for number in ["-1", "0.1", "0e0", "9007199254740992", "18446744073709551616", "true"] {
            let modified = text.replacingOccurrences(of: "\"revision\":0", with: "\"revision\":\(number)")
            #expect(throws: (any Error).self) { try VaultCodec.decode(Data(modified.utf8), expectedID: id) }
        }
        for number in ["-1", "253402300800000", "0.0", "0e0", "null", "false"] {
            let modified = text.replacingOccurrences(of: "\"createdAt\":0", with: "\"createdAt\":\(number)")
            #expect(throws: (any Error).self) { try VaultCodec.decode(Data(modified.utf8), expectedID: id) }
        }
        let maximum = text.replacingOccurrences(of: "\"revision\":0", with: "\"revision\":9007199254740991")
        #expect(try VaultCodec.decode(Data(maximum.utf8), expectedID: id).revision == 9_007_199_254_740_991)
    }

    @Test func resourceBoundsBeforeDecodeAndEncode() throws {
        let sample = try sampleVault()
        var invalid = [Vault]()
        var v = sample; v.name = String(repeating: "é", count: 2049); invalid.append(v)
        v = sample; v.entries[0].tags = Array(repeating: "tag", count: VaultTags.maximumCount + 1); invalid.append(v)
        v = sample; v.entries = Array(repeating: v.entries[0], count: 10_001); invalid.append(v)
        v = sample; v.entries[2].fields = .secureNote(.init(content: String(repeating: "x", count: 1_048_577))); invalid.append(v)
        v = sample; v.entries[3].fields = .customSecret(.init(customFields: Array(repeating: .init(name: "field"), count: 101))); invalid.append(v)
        for vault in invalid {
            #expect(throws: VaultError.resourceLimit) { try VaultCodec.encode(vault, expectedID: vault.vaultID) }
        }
        var maximum = sample; maximum.entries[2].fields = .secureNote(.init(content: String(repeating: "x", count: 1_048_576)))
        let encoded = try VaultCodec.encode(maximum, expectedID: maximum.vaultID)
        #expect(try VaultCodec.decode(encoded, expectedID: maximum.vaultID) == maximum)
        // Wrong element types prove the scanner hits count limits BEFORE typed decoding begins.
        let excessive = "{\"entries\":[{\"tags\":[" + Array(repeating: "true", count: VaultTags.maximumCount + 1).joined(separator: ",") + "]}]}"
        #expect(throws: VaultError.resourceLimit) { try VaultCodec.decode(Data(excessive.utf8), expectedID: sample.vaultID) }
        let tooManyEntries = "{\"entries\":[" + Array(repeating: "false", count: 10_001).joined(separator: ",") + "]}"
        #expect(throws: VaultError.resourceLimit) { try VaultCodec.decode(Data(tooManyEntries.utf8), expectedID: sample.vaultID) }
    }

    @Test func tagsNormalizeAndRespectCurrentLimit() throws {
        #expect(VaultTags.unique([" Work ", "WORK", "", "Personal", "personal"]) == ["Work", "Personal"])
        #expect(VaultTags.unique(["é", "e\u{301}"]) == ["é"])
        #expect(VaultTags.key("Straße") == VaultTags.key("STRASSE"))
        var vault = try sampleVault()
        vault.entries[0].tags = (0..<VaultTags.maximumCount).map { "tag-\($0)" }
        let encoded = try VaultCodec.encode(vault, expectedID: vault.vaultID)
        #expect(try VaultCodec.decode(encoded, expectedID: vault.vaultID) == vault)
        vault.entries[0].tags.append("one-too-many")
        #expect(throws: VaultError.resourceLimit) { try VaultCodec.encode(vault, expectedID: vault.vaultID) }
        var object = try jsonObject(sampleVault())
        try editEntry(&object) { $0["tags"] = vault.entries[0].tags }
        #expect(throws: VaultError.resourceLimit) { try VaultCodec.decode(jsonBytes(object), expectedID: vault.vaultID) }
    }

    @Test func revisionFailureIsTransactional() async throws {
        let directory = try TestDirectory(); defer { directory.remove() }
        let bytes = try fixture("reference-v1.crypta")
        try bytes.write(to: directory.vault)
        let engine = VaultEngine(store: .init(checkpoint: { if $0 == .beforeRename { throw VaultError.fileAccess } }))
        try await engine.open(at: directory.vault, passphrase: testPassphrase)
        let original = try await engine.readVault()
        var edited = original; edited.name = "Uncommitted"
        await #expect(throws: VaultError.fileAccess) { try await engine.save(vault: edited) }
        #expect(try await engine.readVault() == original)
        #expect(try Data(contentsOf: directory.vault) == bytes)
        var future = try jsonObject(original); future["revision"] = VaultValidation.maxRevision
        let fullRevision = try container(with: jsonBytes(future))
        try fullRevision.write(to: directory.vault)
        let maxEngine = VaultEngine()
        try await maxEngine.open(at: directory.vault, passphrase: testPassphrase)
        let last = try await maxEngine.readVault()
        await #expect(throws: VaultError.resourceLimit) { try await maxEngine.save(vault: last) }
        #expect(try Data(contentsOf: directory.vault) == fullRevision)
        #expect(try await maxEngine.readVault() == last)
    }

}
