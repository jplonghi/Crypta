# Contributing to Crypta

Crypta is experimental. Use synthetic data when developing, testing, taking screenshots, and reporting issues. Read [SECURITY.md](SECURITY.md) and [THREAT_MODEL.md](THREAT_MODEL.md) before changing vault handling.

For ordinary bugs, describe the expected behavior, reproduction steps, macOS/Xcode versions, and any synthetic example needed to reproduce the problem. Follow the private-reporting guidance in SECURITY.md for suspected vulnerabilities. Never attach a real vault, passphrase, token, or private log.

Keep pull requests focused. Explain the resulting behavior, relevant compatibility changes, and checks actually run. Reuse existing components and avoid dependencies or abstractions unrelated to the change. Add regression coverage for nontrivial logic, especially parsing, migration, cryptography, persistence, and lock behavior.

On an Apple Silicon Mac with Xcode and Swift 6, run the checks relevant to your change:

```sh
swift test --force-resolved-versions --package-path Packages/CryptaCore
swift test --force-resolved-versions
bash Scripts/fuzz.sh 20000
xcodebuild -project Crypta.xcodeproj -scheme Crypta -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData -onlyUsePackageVersionsFromResolvedFile build
codesign --verify --deep --strict DerivedData/Build/Products/Release/Crypta.app
```

The GitHub workflow runs these checks on macOS 15 with Xcode 16.4. It does not certify security, exercise the full UI, or replace macOS 14 and physical-hardware release checks. Local ad-hoc signing does not require distribution credentials.

Preserve exact UTF-8 passphrases, authenticated encryption, strict bounded validation, encrypted metadata, atomic saves, and file-plus-passphrase portability. Format changes require explicit versioning, fixtures, and compatibility tests. Keep the deterministic public fixture immutable unless deliberately updating its documented compatibility contract.

Review the files being committed. Keep personal notes in `.local/` and real vaults outside the checkout. Do not force-add ignored private files. Dependency changes must include updated lockfiles, provenance, and third-party notices.

Contributions are made under the project's [MIT license](LICENSE). Preserve the separate [third-party notices](Documentation/THIRD_PARTY_NOTICES.md).
