# Phase 6 — internal hardening and release readiness

Date: 2026-10-09. Baseline: `aab698aa59493c55117cc1198bedcb5a4553dd60`. Changes are on `codex/phase-6-hardening`; identify the exact revision with `git rev-parse HEAD` before any external assessment.

This is a code inspection and local verification performed by the development agent. It is **not an independent security audit**, a release approval, or evidence that no vulnerabilities remain. Phase 6 remains in progress until the outstanding gates below are completed. All exercised vaults and passphrases were synthetic; no real vault was opened.

## Scope and findings addressed

Inspected the cryptographic adapter and key ownership, binary format and AAD, bounded JSON parsing, both payload schemas, persistence transactions, cancellation/generation handling, clipboard ownership, private text controls, lifecycle, entitlements, dependency pins, and production logging/disk-write paths.

| Finding | Change | Verification |
| --- | --- | --- |
| A successful engine open followed by a failed model read could leave a live engine session behind the locked UI | Failed create/unlock operations now await engine lock before allowing retry; generation checks still suppress late results | Injected read failure after successful open, engine/session cleanup, successful retry; existing delayed automatic-lock tests |
| Staging names grew with the vault filename and could exceed the filesystem limit for a name accepted by the UI | Use a fixed prefix, random UUID, and existing `.crypta-stage` suffix | Create/save/reopen a 230-byte Unicode base name; encrypted staging, failure cleanup, crash recovery and old lock-domain tests |
| Special files used as lock paths should be rejected without a blocking open | Open lock paths with `O_NONBLOCK`, retaining regular-file, no-follow, single-link checks | FIFO and symlink lock rejection preserves the original vault; cross-process lock test |
| The app did not show the engine's actual key page-locking capability | Carry the existing engine capability into presentation state and show a persistent warning when unavailable; clear it on lock | Both capability outcomes and lock reset; normal real-engine workflows |
| Release startup did not enforce the documented core-dump policy | Set and verify the process core-dump soft limit to zero before launch completes; close the app if this fails | Native resource-limit test verifies zero soft limit and unchanged hard limit; Release compilation/tests |

No encryption primitive, KDF profile, AAD composition, dependency, container format, or payload schema changed. Current and legacy vault access is preserved. Staging remains ciphertext-only with mode 0600 and atomic replacement. The writer-lock filename is unchanged, so cooperating older versions still use the same lock domain. Custom desktop `VaultService` implementations now need the asynchronous `isKeyMemoryLocked` property; the public engine already provided that capability.

The new fuzz seed exercises schema 2 with all four entry types, tags, Favorites, optional expiry, custom fields, Unicode and escaped text, alongside the existing binary fixture and legacy payload. A decode/encode self-check runs before mutations. CI now requests Address Sanitizer for both suites and parser mutations.

## Local verification

Host: MacBookPro18,4, Apple M1 Max, 64 GiB RAM; macOS 26.6.2 (25G83); Xcode 27.0 (27A266a). Tests target macOS 14 arm64 but ran on the newer host. Deployment targeting is not a macOS 14 runtime test.

| Check | Result |
| --- | --- |
| Core debug suite | 31 tests passed |
| Desktop debug suite | 22 tests passed |
| Core Address Sanitizer suite | 31 tests passed |
| Desktop Address Sanitizer suite | 22 tests passed |
| Address Sanitizer parser mutations | 100,000 deterministic iterations passed; seed `0x637279707461` |
| Desktop Release suite | 22 tests passed |
| Xcode arm64 Release build | Passed |
| Local Release signature | `codesign --verify --deep --strict` passed; ad-hoc signature, hardened runtime |
| Release entitlements | App Sandbox and user-selected read/write only; no network or debugger entitlement |
| Release dynamic library paths | System frameworks/libraries only; no Homebrew or development-checkout runtime path |
| Production source scan | No production logging, telemetry, runtime network client, or Keychain persistence found in reviewed source |
| Reference fixture and native archive hashes | Match recorded Phase 2 artifacts |

The previously reported sanitizer startup failure was toolchain/runtime-specific. It does not describe this run: the probe, both complete suites, and the mutation harness now pass under Address Sanitizer. The bundled native libsodium archive is **not instrumented**. These checks do not provide native-library sanitizer coverage, exhaustive parser coverage, leak certification, or proof of complete plaintext erasure. Deterministic mutation fuzzing is not coverage-guided fuzzing.

Xcode emitted its metadata-extraction warning because this app has no AppIntents dependency. The Release build succeeded; no Swift compiler warning or error was reported. No unused framework was added to suppress that tool message.

Reproduce the main checks from the repository root with the pinned resolutions:

```sh
swift test --force-resolved-versions --package-path Packages/CryptaCore
swift test --force-resolved-versions
swift test --force-resolved-versions --package-path Packages/CryptaCore --scratch-path /tmp/crypta-asan-core --sanitize address
swift test --force-resolved-versions --scratch-path /tmp/crypta-asan-desktop --sanitize address
CRYPTA_FUZZ_ASAN=1 bash Scripts/fuzz.sh 100000
swift test --force-resolved-versions -c release
xcodebuild -project Crypta.xcodeproj -scheme Crypta -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData -onlyUsePackageVersionsFromResolvedFile build
codesign --verify --deep --strict DerivedData/Build/Products/Release/Crypta.app
```

On this restricted development host SwiftPM additionally used `--disable-sandbox` and temporary cache paths. That changes the build process environment, not the built application's App Sandbox entitlements. CI exercises its own hosted environment; consult the exact revision's workflow results separately.

## M1-family KDF measurement

Five fresh processes using the existing optimized `CryptaTestDriver benchmark` harness, fixed public fixture credentials and default profile (Argon2id, 3 passes, 256 MiB), each creating and reopening an empty synthetic vault:

| Measurement | Minimum | Median | Maximum |
| --- | --- | --- | --- |
| Full create | 0.402 s | 0.410 s | 0.421 s |
| Full unlock | 0.392 s | 0.396 s | 0.429 s |
| Process peak RSS | 263.266 MiB | 263.297 MiB | 263.313 MiB |

RSS was measured with macOS `/usr/bin/time -l`. This includes the engine and file I/O but excludes the GUI and a large vault. It is M1 Max evidence, **not** base-M1, 8 GiB, maximum accepted KDF cost, or induced memory-pressure testing. No KDF fallback or weaker default was introduced.

## Dependency identity and provenance

All three `Package.resolved` files still pin swift-sodium 0.11.0 at `cfd195c76882aa9b997560ca7cb95d72fbf5db00`. The actual benchmark runtime reports libsodium 1.0.22.

| Artifact | SHA-256 |
| --- | --- |
| Bundled universal macOS `libsodium.a` | `9e00d236b5fc294f48825edbc1ca8971dc418363dae8cc7787004d63454ed563` |
| Public `reference-v1.crypta` | `5a5c6c4f691f27a33e866195164988c72d623b2f95bca909192063aabd2a8845` |

The retrieved [libsodium advisory page](https://github.com/jedisct1/libsodium/security/advisories) and [swift-sodium advisory page](https://github.com/jedisct1/swift-sodium/security/advisories) show no published advisories. The latter web result was cached from the preceding week; this is a limited advisory-page observation, not a comprehensive current vulnerability search or proof of safety. Repeat advisory checks against the release candidate.

The pinned Swift package vendors its XCFramework. Its manifest, headers, runtime version and hash identify the artifact; they do **not** establish that it was reproducibly built from the claimed native source. A verified source-build recipe and comparison/approval of the native artifact remain release gates. No dependency was upgraded or substituted.

## Remaining gates and limits

- **Independent reviewer:** not engaged. Use the [security review brief](SECURITY_REVIEW_BRIEF.md), freeze a revision, obtain private findings, fix them and have the reviewer retest. An additional AI review would not satisfy this gate.
- **macOS 14 runtime:** unavailable. Test a copied synthetic vault and the release candidate on the oldest supported OS, without development-machine state.
- **Distribution signing/notarization:** no Apple Developer Program membership or Developer ID identity is available. The verified build is locally ad-hoc signed; it is not a distributable, notarized release.
- **Hardware/platform matrix:** base M1/low memory, maximum KDF cost under pressure, actual sleep/fast-user-switch, fresh-user/second-Mac portability, and a full VoiceOver/keyboard walkthrough remain unverified. Injected lifecycle tests do not replace real OS-event tests.
- **Native provenance:** verify the bundled library's build provenance or produce a reviewed source build before format/release freeze.
- **Persistence:** cooperating local writers coordinate and stale changes are refused. A writer that ignores the lock can still race between the final comparison and rename. Network/cloud filesystems have no distributed conflict guarantee. An externally renamed filename too long for the unchanged lock-file suffix may open but cannot save until shortened.
- **Memory:** only owned native buffers can be explicitly wiped/page-locked. Swift, UI/framework copies, OS diagnostics and privileged capture remain outside those guarantees. Disabling process core dumps does not disable every OS diagnostic facility.
- **Backups:** valid older vaults can be replayed; passphrase changes do not revoke old backups or rotate the vault key. Clipboard clearing cannot recall copies captured by another app.

No release tag, distributable binary, independent-audit claim, or production-use approval is made by this phase's local work.
