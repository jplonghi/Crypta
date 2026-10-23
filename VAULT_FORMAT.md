# .crypta file format v1

Status: unshipped personal POC; not frozen for release. Readers and writers use one current encrypted payload structure without schema versions or migrations. Earlier development vaults need not remain readable. The binary format identifier describes the cryptographic envelope and is separate from the payload structure. Offsets are decimal bytes. Integers are unsigned little-endian. Serialize fields explicitly; never dump Swift/C structures or rely on native alignment. All random values are independent CSPRNG outputs. There is one key slot and one payload.

## Physical layout

| Offset | Bytes | Field | Required value/meaning |
| ---: | ---: | --- | --- |
| 0 | 8 | Magic | Hex `43 52 59 50 54 41 0D 0A` (`CRYPTA\r\n`) |
| 8 | 2 | Format version | 1 |
| 10 | 2 | Core-header length | 48 |
| 12 | 4 | Flags | 0 |
| 16 | 16 | Vault ID | Random opaque bytes, not a device ID |
| 32 | 2 | Payload AEAD ID | 1 = XChaCha20-Poly1305-IETF |
| 34 | 2 | Payload encoding ID | 1 = UTF-8 JSON |
| 36 | 12 | Core reserved | All zero |
| 48 | 2 | KDF ID | 1 = Argon2id v1.3 (0x13), no secret/AD input |
| 50 | 2 | Wrap AEAD ID | 1 = XChaCha20-Poly1305-IETF |
| 52 | 4 | Argon2 passes | Default 3 |
| 56 | 4 | Argon2 memory, KiB | Default 262144 (256 MiB) |
| 60 | 4 | Argon2 lanes | Exactly 1 |
| 64 | 16 | Salt | Random per creation/passphrase change |
| 80 | 24 | Wrap nonce | Fresh random per key wrapping |
| 104 | 8 | Slot reserved | All zero |
| 112 | 48 | Wrapped vault key | 32-byte encrypted key followed by 16-byte tag |
| 160 | 24 | Payload nonce | Fresh random per payload encryption |
| 184 | 8 | Payload ciphertext length L | Includes 16-byte tag |
| 192 | L | Encrypted payload | JSON ciphertext followed by 16-byte tag |

The immutable core is `[0,48)`, key-slot descriptor `[48,112)`, wrapped key `[112,160)`, and payload descriptor `[160,192)`. EOF must be exactly `192 + L`. No trailing records, padding, alternate slots, or compression are accepted in v1.

Crypta IDs are application constants, not the numeric value of a libsodium enum. Map ID 1 to the explicit library algorithm. Key and tag sizes are fixed by v1.

## Authentication and encryption

Let `||` mean byte concatenation. Domain labels below are ASCII followed by exactly one zero byte, with no length prefix. AAD uses original validated file bytes, not reserialized values.

```text
KEK = Argon2id13(passphraseUTF8, salt,
                outputBytes=32, passes=t, memoryKiB=m, lanes=1)

wrapAAD = ASCII("Crypta/v1/key-wrap") || 0x00
          || file[0..<48] || file[48..<112]
wrappedKey = XChaCha20Poly1305.seal(vaultKey, KEK, wrapNonce, wrapAAD)

payloadAAD = ASCII("Crypta/v1/payload") || 0x00
             || file[0..<48] || file[160..<192]
payloadCiphertext = XChaCha20Poly1305.seal(JSON, vaultKey, payloadNonce, payloadAAD)
```

These names describe libsodium AEAD calls; they are not new cryptographic algorithms. The wrapper authenticates KDF parameters and salt; the payload authenticates its own nonce/length. Both bind to the same immutable core, including vault ID and format identifiers. Every header field belongs to at least one authenticated domain. Reserved fields must both validate structurally and participate in AAD.

Do not put the mutable key slot into payload AAD: that would require payload re-encryption on a passphrase change. Do not put the mutable payload descriptor into wrap AAD: that would require retaining/rederiving the KEK on each save. The split is deliberate. Both tags must verify before any content is exposed. A mixed envelope/payload from different vault keys fails; older valid components under the same unchanged vault key can still be replayed. This format provides integrity, not freshness, key revocation, or rollback protection.

Normal save preserves the core, slot descriptor, and wrapped key, then creates a new payload nonce and ciphertext. Passphrase change preserves the core, payload descriptor, and payload ciphertext, then creates a fresh salt, KEK, wrap nonce, and wrapped key. Replacing the vault key requires re-encryption and a new vault ID. Atomic storage rewrites the complete file in all cases; avoiding cryptographic re-encryption does not avoid file I/O.

## Parser and resource policy

1. Open a regular file without following a final symlink. Bound file size before reading; also bound the read itself because file size can change. Reject files below 208 bytes or above 16,777,424 bytes.
2. Read the fixed 192-byte prefix using bounds-checked offsets. Reject unknown version/IDs, nonzero flags/reserved bytes, or a core-header length other than 48.
3. Require `16 <= L <= 16,777,232` (16 MiB of plaintext plus tag), checked addition for `192 + L`, and an exact file length match. Empty plaintext passes the structural minimum but cannot be a valid payload schema.
4. Before allocating Argon2 memory, require `3 <= t <= 6`, `65536 <= m <= 524288` KiB, `m` a multiple of 1024 KiB, and `lanes == 1`. The writer uses the default profile; alternative accepted parameters exist for future tuning and compatibility. Convert KiB to bytes using checked arithmetic. No runtime fallback or parameter clamping.
5. Derive only after those checks. Limit KDF concurrency to one. Reject allocation failure with a resource error; do not retry with less memory. An attacker can still consume the bounded maximum per attempt.
6. Authenticate and unwrap into an owned temporary buffer. Authenticate the entire payload into private memory before decoding. On either authentication failure return the same user-facing incorrect-passphrase-or-damaged-file error and dispose of all sensitive buffers.
7. Decode strict UTF-8 JSON with the limits below. No duplicate object keys, non-finite numbers, trailing tokens, or excessive nesting. A bounded prevalidation/tokenization pass may be needed because `JSONDecoder` alone does not enforce every limit. Do not implement JSON parsing by regular expression.

Files exceeding resource policy are unsupported, not silently repaired. Structural/resource errors may be distinct from authentication errors because public-header information is already observable.

## Encrypted payload

Root fields: `vaultID` (32 lowercase hex digits matching the core), `name`, `createdAt`, `modifiedAt`, `revision`, and `entries`. There are no category or independent tag entities. All organization metadata remains inside the authenticated ciphertext.

Each entry has `id`, `type`, `title`, `createdAt`, `modifiedAt`, `tags` (flat string array), `isFavorite` (required Boolean), and `fields`:

| Type | Fields |
| --- | --- |
| `credential` | `username`, `password`, `websiteURL`, `notes` |
| `apiToken` | `service`, `token`, `environment` (`development`, `testing`, `production`), `expiresAt` (date or explicit null), `notes` |
| `secureNote` | `content` |
| `customSecret` | `customFields`: array of `{id, name, value, isSecret}` |

Tags are nonempty trimmed strings, unique within an entry under locale-independent Unicode case folding (`en_US_POSIX`) and canonical composition. Display spelling and order are retained. Slashes and punctuation have no hierarchical meaning. The same tag may appear on multiple entries. `Work` and `Personal` are UI suggestions only; they are never implicitly written to an entry. Favorites is independent of tag names.

Dates are integer UTC Unix milliseconds, 0 through 253402300799999, with creation no later than modification. UUIDs use canonical lowercase hyphenated text. Entry IDs are unique across the vault; custom field IDs are unique per entry. Titles must contain non-whitespace text. Numeric fields require integer JSON literals. Revisions are bounded to 2^53−1 and increment only on successful payload saves; stale snapshots and exhausted counters fail. Passphrase-only rewrapping preserves payload bytes and revision. Entry creation dates are immutable; modification dates cannot move backward.

Limits: 16 MiB encoded payload; nesting depth 16; 10,000 entries; 100 tags per entry; 100 custom fields per entry; 1 MiB UTF-8 per secret/note/custom value; 4 KiB for other strings. Bounds are checked before typed decoding and before encoding. Unknown types, fields, and token environments are rejected rather than dropped. URLs remain inert strings.

## Persistence and conflict contract

All staging, recovery, and conflict-copy files contain only complete encrypted containers. File names and filesystem metadata remain visible. Never use document autosave, JSON sidecars, or decrypted file previews.

For local supported filesystems, coordinate cooperating Crypta writers using a stable sidecar lock with advisory locking; hold it across reading the current fingerprint, comparison, and commit. The lock contains no secrets and is not needed for decryption. Do not unlink/recreate an active lock file, which can split the lock domain. Compare a cryptographic digest of the entire current ciphertext file with the session's saved baseline; timestamps alone are insufficient. Resolve canonical file identity/aliases, and do not allow writes through hard-linked aliases in v1. A mismatch, replacement, or deletion is a conflict; never silently recreate or overwrite.

Create a unique sibling staging file exclusively with mode 0600. Write the fully encrypted container, handle short writes, flush and close it, then atomically rename/replace on the same volume; initial creation must use a no-clobber primitive. Request appropriate file and directory durability on macOS and verify the actual filesystem behavior. Preserve the original on pre-commit error. Report post-rename durability failure as an uncertain commit and re-read under the lock before retrying. Update the session fingerprint only after confirmed success. Failure injection must cover each boundary.

After an interrupted write, the primary should be either the old or new complete file, not a mixture. Orphan staging files are encrypted; offer explicit authenticated recovery and never promote them based on timestamps alone. Atomic rename is not a power-loss guarantee by itself, and remote/cloud filesystems may not honor equivalent locking or durability.

Advisory locks protect only cooperating writers within the same filesystem coordination domain. Noncooperating writers can race after a comparison. Cross-Mac cloud synchronization and SMB semantics cannot provide a global compare-and-swap guarantee here. The supported MVP workflow is one writer on a local file, close it, then copy it. External modification detection is a loss-prevention measure, not an adversarial freshness guarantee.
