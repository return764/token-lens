---
name: maintain-changelog
description: Maintain CHANGELOG.md in Keep a Changelog format. Add entries to Unreleased, bump versions on release, verify section exists for a tag. Use when user wants to update the changelog, add a changelog entry, prepare a release, bump version, or mentions CHANGELOG / release notes.
---

# Maintain Changelog

## Format

```md
## [Unreleased]

### Added
- xxx

### Fixed
- yyy

## [0.1.0] - 2026-06-13

### Added
- ...
```

- Version headers: `## [X.Y.Z] - YYYY-MM-DD` （**no `v` prefix**）
- Section categories: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`
- Version must match git tag: tag `v0.2.0` ↔ changelog `[0.2.0]`
- The `[Unreleased]` section holds all unreleased changes

## Workflows

### Add an entry

1. Read `CHANGELOG.md` to see current sections
2. If `[Unreleased]` doesn't exist, create it at the top
3. Add the entry under the correct category (`### Added` / `### Fixed` / etc.)
4. If the category header doesn't exist, create it under `[Unreleased]`
5. Each entry is a single `- ` bullet, lowercase, no period

Example:

```bash
# Read first
cat CHANGELOG.md
# Then edit with the new entry
```

### Bump version (release)

1. Read `CHANGELOG.md`
2. Verify `[Unreleased]` has entries — if empty, warn user
3. Create a new version section: `## [X.Y.Z] - YYYY-MM-DD` using today's date
4. Move all `### Category` blocks from `[Unreleased]` into the new section
5. Leave `## [Unreleased]` empty (no categories, no bullets)

### Verify section exists for tag

Used by the release workflow. Confirm a `## [X.Y.Z]` header exists:

```bash
grep -q '^## \['"$VERSION"'\]' CHANGELOG.md
```

## Edge cases

- **No CHANGELOG.md**: offer to create one with the template
- **Empty Unreleased on bump**: warn that release notes will be empty
- **No matching section for tag**: workflow falls back to `generate_release_notes: true`
- **Section order**: keep `[Unreleased]` first, then versions descending
