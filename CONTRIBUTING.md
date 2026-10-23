# Contributing to Crypta

Use synthetic data for development, screenshots, and bug reports. Read [SECURITY.md](SECURITY.md) before changing vault handling. Report suspected vulnerabilities privately through the process described there; never attach real vaults or credentials.

For ordinary bugs, include expected behavior, reproduction steps, and macOS/Xcode versions. Keep pull requests focused and explain the resulting behavior and checks actually run.

## Code layout

- `CryptaApp/`: app scene, SwiftUI views, presentation state, and macOS adapters.
- `Packages/CryptaCore/`: vault models, cryptography, format parsing, and encrypted persistence.
- `CryptaAppTests/` and `Packages/CryptaCore/Tests/`: presentation and engine tests, synthetic fixtures, and failure-injection tools.
- `Scripts/`: parser mutation harness and a separate test implementation of the file format.

The `VaultEngine` actor owns the encryption key and serializes vault transactions. Presentation code owns plaintext snapshots and drafts and must discard them on lock. Save returns the committed revision; reuse that returned snapshot for later edits. Treat `durabilityUncertain` as a requirement to reopen and inspect the file before further writes.

## Checks

On an Apple Silicon Mac with Xcode and Swift 6, run the checks relevant to your change:

```sh
swift test --force-resolved-versions --package-path Packages/CryptaCore
swift test --force-resolved-versions
bash Scripts/fuzz.sh 20000
xcodebuild -project Crypta.xcodeproj -scheme Crypta -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData -onlyUsePackageVersionsFromResolvedFile build
codesign --verify --deep --strict DerivedData/Build/Products/Release/Crypta.app
```

Use `--sanitize address` with `swift test` or `CRYPTA_FUZZ_ASAN=1` with the mutation harness for Address Sanitizer checks. The vendored native libsodium archive is not instrumented. The [public fixtures](Packages/CryptaCore/Tests/CryptaCoreTests/Fixtures/README.md) document compatibility and vector provenance.

Passing checks does not certify security or replace actual UI, minimum-OS, hardware, and signed-release testing. Local ad-hoc signing does not require distribution credentials.

## Releases

`bash Scripts/package-release.sh` builds the Apple Silicon Release app and creates a DMG, ZIP, and `SHA256SUMS.txt` in the ignored `dist/` directory. Both downloads include the project license and third-party notices inside the app. Builds use ad-hoc signing and are not notarized.

To release, set `CFBundleShortVersionString` in `CryptaApp/Resources/Info.plist` to the new `MAJOR.MINOR.PATCH` version, commit the intended source, and push a matching `vMAJOR.MINOR.PATCH` tag. The [release workflow](.github/workflows/release.yml) runs engine and desktop tests, packages the app, and creates a **draft GitHub release**. A tag that differs from the app version fails packaging.

Check the tagged commit's CI results, download the draft assets, verify `shasum -a 256 -c SHA256SUMS.txt`, and test installation before publishing the draft. Keep the stable asset names so README download links continue working. Publish a new version for changed binaries instead of replacing assets under an existing version.

The [Homebrew tap](https://github.com/jplonghi/homebrew-tap) checks published releases every six hours, verifies the downloaded DMG against `SHA256SUMS.txt`, and updates `Casks/crypta.rb`. Its update workflow can also be run manually after publishing. No cross-repository token is required in Crypta.

## Change requirements

Preserve exact UTF-8 passphrases, authenticated encryption, bounded validation, encrypted metadata, atomic saves, and file-plus-passphrase portability. Add regression coverage for nontrivial parsing, cryptography, persistence, or lifecycle changes. Follow the [current format contract](VAULT_FORMAT.md).

Crypta is an unshipped personal POC. Maintain one current payload structure without schema versions, migrations, or backward-compatibility adapters. Update tests and regenerate the deterministic public fixture when changing the payload contract; earlier development vaults do not need to remain readable.

Dependency updates must include pinned resolutions, provenance, and license notices. Review staged files and never force-add ignored vaults or credentials.

Contributions use the [MIT license](LICENSE). Preserve [third-party notices](THIRD_PARTY_NOTICES.md).
