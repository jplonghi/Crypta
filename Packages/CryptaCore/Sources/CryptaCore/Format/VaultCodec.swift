import Foundation

/// Only this codec crosses the authenticated payload/model boundary in production.
enum VaultCodec {
    static func decode(_ data: Data, expectedID: VaultID) throws -> Vault {
        try JSONValidator.validate(data, payloadSchema: true)
        do {
            let vault = try JSONDecoder().decode(Vault.self, from: data)
            guard vault.vaultID == expectedID else { throw VaultError.invalidPayload }
            return vault
        } catch let error as VaultError { throw error }
        catch { throw VaultError.invalidPayload } // Never expose decoder descriptions containing field values.
    }

    static func encode(_ vault: Vault, expectedID: VaultID) throws -> Data {
        // Bound collections and total unescaped string bytes before allocating encoded output.
        try VaultValidation.validate(vault, expectedID: expectedID)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let bytes = try encoder.encode(vault)
            guard bytes.count <= VaultFormat.maxPayloadBytes else { throw VaultError.resourceLimit }
            try JSONValidator.validate(bytes, payloadSchema: true)
            return bytes
        } catch let error as VaultError { throw error }
        catch { throw VaultError.invalidPayload }
    }
}
