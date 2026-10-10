# Tags, Favorites, and schema migration

Implemented October 9, 2026.

## Organization

- Categories and type-based navigation are removed. All four item types remain available from New Item and the toolbar.
- Sidebar: CRYPTA, All Items and Favorites with counts, a collapsible Tags section containing only used tags with counts, and New Item.
- Click tags to toggle filters; multiple tags use AND logic. Filters also combine with Favorites and search. All Items clears tag filters; Clear removes tag filters without changing the primary view.
- Tags are flat strings on items. Unicode case folding and canonical equivalence define identity; surrounding whitespace is trimmed and empty tags are omitted when editing/migrating. The first spelling is retained when deduplicating.
- New and existing items are edited in the detail pane with explicit Save and Cancel. Tag chips stay adjacent and wrap as the pane narrows. The editor suggests existing tags as you type, plus Work and Personal. Suggestions are never automatically assigned. A tag still typed in the input is committed when Save is clicked.
- Right-click a sidebar tag to rename it across all items or remove it from all items. Renaming to an existing tag merges assignments. Removal keeps the items and asks for confirmation.
- Stars toggle the encrypted `isFavorite` item property. Editing an existing item preserves it. A tag named Favorites has no special meaning.

## Compatibility and persistence

The encrypted JSON payload advances to schema 2. The outer binary format, Argon2id parameters, XChaCha20-Poly1305 envelope, key handling, file conflict checks, staging, and atomic replacement remain unchanged. No tag index, metadata sidecar, or persistent tag catalog is introduced.

Schema-1 files remain readable. Strict read-only adapters validate categories and references, append assigned category names to item tags, merge duplicate names, and default Favorites to false. Unused categories and empty labels disappear. Item IDs, creation/modification times, revision, and typed secret fields are preserved.

Opening a legacy vault migrates only the in-memory snapshot. The next successful item/organization save writes schema 2. Failed pre-rename writes preserve the original file; a passphrase-only change preserves the original payload schema. Older Crypta builds cannot read schema 2. Keep an encrypted copy before upgrading if an older build must remain usable; there is no automatic downgrade.

The tag limit is 101 so a legacy item with 100 tags and one distinct category loses no assignment. Other resource limits remain unchanged. Very large category names repeated across thousands of items can expand the migrated payload beyond the existing 16 MiB save limit. Such legacy vaults remain readable; shorten/remove those tags or reduce content before saving. The original encrypted file is retained when the limit rejects a save.

## Verification

- 29 core tests pass: legacy fixture access, schema validation, category migration, case/Unicode collisions, all four item types, maximum tag count, large-category expansion, encrypted round trips, interrupted migration saves, stale writers, crash recovery, tampering, and cryptography.
- 17 desktop tests pass: tag suggestions, AND filtering, Favorites, bulk rename/merge/removal, encrypted reopening, save-error retention, lock clearing, and existing session/clipboard checks.
- Native UI checked with a synthetic legacy vault: used-tag sidebar/counts, star toggle, Favorites with tags, suggestions, encrypted editor save, bulk rename, AND filtering, and section collapse.
- Debug and Release Xcode builds succeed. Xcode's AppIntents metadata extraction notice remains because the app does not implement App Intents.

Minimum-version macOS 14 runtime testing and a full VoiceOver audit are not included in this change.
