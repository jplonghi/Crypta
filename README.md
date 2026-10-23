# Crypta

A native macOS vault for credentials, API tokens, secure notes, and custom secrets. Your encrypted `.crypta` file and master passphrase are all you need to open it on a compatible Mac. No account, server, or device-bound key.

**Personal POC:** Crypta is still in development and has not shipped to customers. It has not had an independent security audit. Downloads are ad-hoc signed and not notarized by Apple. Use synthetic data while evaluating it. Read the [security policy and limitations](SECURITY.md).

## Install

**Apple Silicon Mac · macOS 14 Sonoma or later**

[Download DMG](https://github.com/jplonghi/Crypta/releases/latest/download/Crypta-macOS-arm64.dmg) · [Download ZIP](https://github.com/jplonghi/Crypta/releases/latest/download/Crypta-macOS-arm64.zip) · [Release notes and checksums](https://github.com/jplonghi/Crypta/releases/latest)

Open the DMG, drag **Crypta.app** into **Applications**, then eject the disk image and open Crypta. For the ZIP, extract it and move **Crypta.app** into **Applications**. Developer tools are not needed to run the app.

Or install with [Homebrew](https://brew.sh):

```sh
brew install --cask jplonghi/tap/crypta
```

If Crypta is already in Applications, quit it and remove only the old `Crypta.app` before installing with Homebrew. Keep your `.crypta` vault files.

### First launch

Crypta is not notarized by Apple, so macOS may block its first launch. If you trust this download, try opening Crypta from Applications, then use **System Settings → Privacy & Security → Open Anyway**. See [Apple's instructions](https://support.apple.com/en-us/102445).

### Updates

Quit Crypta before replacing it with a newer download. For Homebrew installs:

```sh
brew update
brew upgrade --cask jplonghi/tap/crypta
```

The [Homebrew tap](https://github.com/jplonghi/homebrew-tap) checks for published releases every six hours. Crypta does not update itself. Back up your vault before updating; development changes may require recreating older test vaults.

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

Development uses one current payload structure without schema versions or migrations. Changes may require recreating synthetic vaults from earlier builds. See the [current vault format](VAULT_FORMAT.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the code layout, tests, and reporting guidance. Automated checks are defined in the [GitHub workflow](.github/workflows/ci.yml).

## License

[MIT](LICENSE). Dependencies retain their own licenses; include the [third-party notices](THIRD_PARTY_NOTICES.md) when distributing Crypta.
