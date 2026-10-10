import Foundation

/// Reproducible mutation fuzzing; optional AddressSanitizer, never invokes a KDF.
/// Apple Swift does not provide -sanitize=fuzzer on this arm64 target.
@main struct ParserFuzz {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4, let runs = Int(args[1]), (1...1_000_000).contains(runs) else { return }
        var seeds = try [Data(contentsOf: URL(fileURLWithPath: args[2])), Data(contentsOf: URL(fileURLWithPath: args[3]))]
        let fixtureID = try VaultID(hex: "000102030405060708090a0b0c0d0e0f")
        var vault = Vault(vaultID: fixtureID, name: "Public fuzz seed", createdAt: 0)
        let fields: [EntryFields] = [
            .credential(.init(username: "public", password: "public\\\"\n🗝️", websiteURL: "https://example.invalid", notes: "public")),
            .apiToken(.init(service: "public", token: "public", environment: .production, expiresAt: 1, notes: "public")),
            .secureNote(.init(content: "Public\n第二行")),
            .customSecret(.init(customFields: [.init(id: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5)), name: "public", value: "public", isSecret: false)]))
        ]
        for (index, fields) in fields.enumerated() {
            let id = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,UInt8(index + 1)))
            vault.entries.append(.init(id: id, title: fields.type, createdAt: 0, tags: ["Work", "Personal"], isFavorite: true, fields: fields))
        }
        let currentSeed = try VaultCodec.encode(vault, expectedID: fixtureID)
        guard try VaultCodec.decode(currentSeed, expectedID: fixtureID) == vault else { throw VaultError.invalidPayload }
        seeds.append(currentSeed)
        var state: UInt64 = 0x637279707461
        func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
        for iteration in 0..<runs {
            var data = seeds[iteration % seeds.count]
            for _ in 0..<(1 + iteration % 16) {
                switch next() % 4 {
                case 0 where !data.isEmpty:
                    data[Int(next() % UInt64(data.count))] ^= UInt8(truncatingIfNeeded: next() >> 32)
                case 1 where !data.isEmpty:
                    data = Data(data.prefix(Int(next() % UInt64(data.count))))
                case 2: data.append(UInt8(truncatingIfNeeded: next() >> 32))
                default:
                    data.append(contentsOf: repeatElement(UInt8(truncatingIfNeeded: next() >> 32), count: Int(next() % 128)))
                }
            }
            _ = try? VaultFormat.parse(data)
            _ = try? JSONValidator.validate(data)
            _ = try? VaultCodec.decode(data, expectedID: fixtureID)
        }
        print("Completed \(runs) deterministic parser mutations with seed 0x637279707461.")
    }
}
