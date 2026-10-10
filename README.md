# Crypta

A native macOS vault for credentials, API tokens, secure notes, and custom secrets. Your encrypted `.crypta` file and master passphrase are all you need to open it on a compatible Mac. No account, server, or device-bound key.

**Experimental:** Crypta has not had an independent security audit or a signed, notarized release. Use synthetic data while evaluating it. Read the [security policy and limitations](SECURITY.md).

## Features

- Encrypted entries and metadata using Argon2id and XChaCha20-Poly1305 through libsodium.
- Flat tags, Favorites, search, and filtering by multiple tags.
- Editing in the detail pane with explicit Save and Cancel.
- Automatic locking, managed clipboard expiration, and master-passphrase changes.
- Portable vault files with atomic encrypted saves and local writer conflict checks.

## Build and run

Requires an Apple Silicon Mac, macOS 14 or later, and Xcode with Swift 6. Open `Crypta.xcodeproj`, select the **Crypta** scheme and **My Mac**, then Run.

Or build from the repository root:

```sh
xcodebuild -project Crypta.xcodeproj -scheme Crypta -configuration Debug -derivedDataPath DerivedData build
open DerivedData/Build/Products/Debug/Crypta.app
```

The project uses local ad-hoc signing; no Apple Developer membership is needed to build locally. Initial dependency resolution requires internet access. Dependencies are pinned, and the built app operates offline.

## Using a vault

Create a vault in a folder you choose, or open an existing `.crypta` file. Opening also requests access to its containing folder so encrypted saves can create temporary sibling files. Crypta does not remember folder grants between sessions.

Save commits edits; Cancel discards them. Automatic lock discards unsaved drafts. The default inactivity timeout is five minutes, and managed copies expire after 30 seconds; change these in Security Settings (⌘,). Sleep and switching away from the macOS session also lock the vault.

Use ⌘F to search, ⌘E to edit, ⌘S to save, and ⇧⌘L to lock. **Vault → Change Master Passphrase** changes the current file's passphrase. Older backups retain their old passphrase. There is no passphrase reset or recovery service.

Legacy schema-1 vaults are read with categories converted into tags. The next successful content save writes schema 2, which older builds cannot read. Keep an encrypted backup before upgrading. See the [vault format and compatibility contract](VAULT_FORMAT.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the code layout, tests, and reporting guidance. Automated checks are defined in the [GitHub workflow](.github/workflows/ci.yml).

## License

[MIT](LICENSE). Dependencies retain their own licenses; include the [third-party notices](THIRD_PARTY_NOTICES.md) when distributing Crypta.
