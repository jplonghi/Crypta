# Phase 3: typed models and schema validation

Phase 3 adds the domain layer inside `CryptaCore`. The binary container, cryptographic algorithms, dependency pins, and independent reference fixture are unchanged. No SwiftUI app is implemented yet.

## Models

| Model | Stored values |
| --- | --- |
| Vault | Bound vault ID, name, creation/modification times, revision, categories, entries |
| VaultEntry | UUID, type/version discriminator, title, timestamps, ordered tags, optional category, typed fields |
| Credential | Username, password, website URL, notes |
| APIToken | Service, token, development/testing/production environment, optional expiration, notes |
| SecureNote | Content |
| CustomSecret / CustomField | Ordered fields with stable UUID, name, value and secret-display flag |
| VaultCategory | Stable UUID and name |

Models are Swift value types conforming to Sendable and Equatable; persisted types support Codable. The `EntryFields` enum associates each supported entry kind with its fields. Custom field display preferences never affect encryption. URLs remain inert strings; the core does not open them.

Unicode text, whitespace, tag order, duplicate tags, and custom-field order are preserved. Validation checks titles for a non-whitespace character without trimming the stored title. Secret values may be empty; passphrase creation rules remain separate. All date fields are UTC Unix milliseconds; expiration dates may legitimately refer to the past.

## Public API

- `create(at:passphrase:name:createdAt:parameters:)` creates and returns a schema-1 vault with a random ID, no entries/categories, and revision zero.
- `open(at:passphrase:)` verifies both AEAD tags, validates the JSON and schema, and checks that the payload ID matches the authenticated header. An unsupported or invalid payload leaves the engine locked and file unchanged.
- `readVault()` returns a caller-owned plaintext model snapshot. The engine continues to retain only ciphertext and its guarded key, not a plaintext model cache.
- `save(vault:modifiedAt:)` validates the edited snapshot, checks identity/creation time/revision, checks existing entry creation and modification times, and commits the encrypted result. It returns the next revision only after a successful write. Keep this returned snapshot for subsequent edits.
- Passphrase changes and locking retain their previous API. Rewrapping preserves the payload and its revision.

The previous raw `payload: Data` create/save API and `readPayload()` were removed; there is no public schema-validation bypass. Direct use of a model's Codable conformance does not replace engine validation. Files made with experimental Phase 2 arbitrary JSON are rejected; there is no silent migration. The original independently generated schema-1 fixture still opens and reserializes identically.

A caller edits `entries`, `categories`, `tags`, and typed field values in a snapshot before saving. To remove a category, reassign/uncategorize its entries or delete them in the same transaction. IDs and creation dates remain stable across ordinary edits. Set an edited entry's `modifiedAt`; the engine rejects a value older than its persisted modification time. The engine manages vault modification time and revision, and clamps vault time to its previous value when the system clock goes backward.

## Validation boundary

Before typed decoding, the bounded JSON scanner rejects duplicate keys, malformed UTF-8/JSON, excessive nesting, oversized strings/collections, and non-integer numeric literals. It applies the 1,000-category, 100-tag and 100-custom-field limits while scanning, not after constructing their model arrays. Other limits remain 10,000 entries, 4 KiB metadata strings, 1 MiB secret/note/custom values, and a 16 MiB encoded payload.

Strict dynamic coding keys detect unknown fields at every model level. Missing required keys, including required nullable fields, are invalid. Unknown schema/entry versions, entry types, token environments and fields are unsupported. Models are checked for canonical lowercase UUIDs, unique IDs, valid category references, timestamp bounds/order and revision bounds. Custom-field IDs must be unique within their entry; category and entry IDs each have their own namespace.

Before encoding, collection, field, and aggregate unescaped-string limits are checked. Encoded size is checked again after JSONEncoder accounts for escaping and structural overhead. Encoding can temporarily allocate more than the final payload cap when escaping expands text; no resulting oversized payload reaches encryption or disk. All decoded/encoded Swift values remain subject to the previously documented memory-erasure limits.

Typed decoding errors are translated into value-free `VaultError` cases so decoder diagnostics containing user input are not returned by the engine. Invalid data never updates the session revision or committed file. Revision exhaustion is an error, never an integer wraparound. Revisions prevent stale edits within a known session; they do not prevent offline rollback attacks.

## Verification

Verified on the existing Swift 6.2.3 / macOS 26.6.2 arm64 development host:

| Check | Result |
| --- | --- |
| Full debug suite | 26 tests in six suites passed |
| Optimized release suite | 25 tests in six suites passed; debug-only forced-process-death test excluded |
| Parser/schema mutation harness | 20,000 deterministic mutations completed without a reported failure |
| Existing independent fixture | Opens and reserializes under the strict schema layer; ciphertext fixture unchanged |
| Swift-to-Python interoperability | Independent Argon2/XChaCha implementation decrypted a newly created typed Swift vault |
| Documentation/source checks | Local links, code fences and whitespace passed; no core logging or UI imports found |

No AddressSanitizer pass is claimed; its previously observed startup failure and the macOS 14/M1/independent-review gaps remain open.

The Phase 2 security and persistence tests were migrated to valid typed vaults without weakening their tampering, conflict, interruption, or passphrase checks. Added domain tests cover:

- All four entry types and all supported fields through encode/decode and encrypted save/lock/reopen.
- All token environments, present/null expiration, categories, tag order/Unicode, and both custom display flags.
- Typed add/edit/delete transactions, stable IDs/timestamps, dangling-reference rejection and stale-snapshot refusal.
- Unknown versions/types/fields, including category and custom-field objects, required nulls, and mismatched authenticated identity.
- Rejection of unsupported but correctly authenticated files before a session becomes available.
- Duplicate IDs, invalid references, blank titles, chronology, timestamp/revision integer bounds, and resource limits.
- Failed commits and revision exhaustion preserving both the committed file and session state.

The parser mutation harness now exercises typed schema decoding as well as the binary and structural JSON parsers. These results are implementation evidence, not an independent security audit.

## Remaining work

Phase 4: native SwiftUI welcome/create/unlock/browser/editor/save/lock flows. Phase 5 adds inactivity/sleep locking, clipboard handling, shortcuts and further usability. macOS 14/M1 testing, a functioning sanitizer run and independent security review remain outstanding as recorded in Phase 2. Callers will need to clear all returned model copies and editor state when locking; a core lock cannot erase values retained by a future UI.
