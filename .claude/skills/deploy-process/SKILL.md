---
name: deploy-process
description: Release process for indexion. Use when the user asks to release, deploy, bump version, create a tag, or push a release. Ensures submodule→parent push ordering, version sync, and tag consistency.
---

# indexion Release Process

## Prerequisites

- `.gitmodules` has `pushRecurseSubmodules = on-demand` for all submodules
- `scripts/sync-version.sh` exists and syncs `moon.mod.json` → `version.mbt` + `marketplace.json`
- All tests pass: `moon test --target native`

## Version Convention

- SoT: `moon.mod.json` → `"version"` field
- Semver: `MAJOR.MINOR.PATCH`
- Tags: `v{VERSION}` (e.g. `v0.8.0`)
- Propagation targets:
  - `src/update/version.mbt` → `current_version` constant
  - `skills/.claude-plugin/marketplace.json` → `"version"` field

## Release Steps

### 1. Commit feature changes

Commit all feature/fix changes BEFORE the version bump. The release commit should contain ONLY version changes.

If submodules have changes:

```bash
# kgfs submodule
cd kgfs && git add -A && git commit -m "feat: ..." && cd ..

# skills submodule
cd skills && git add -A && git commit -m "feat: ..." && cd ..

# Parent: stage submodule refs + changed files
git add kgfs skills src/ cmd/ ... && git commit -m "feat: ..."
```

### 2. Bump version in moon.mod.json

Edit `moon.mod.json` and change the `"version"` field:
- `+0.0.1` for patches (bug fixes)
- `+0.1.0` for minor (new features, backward compatible)
- `+1.0.0` for major (breaking changes)

### 3. Run sync-version.sh

```bash
bash scripts/sync-version.sh
```

This propagates the version to `version.mbt` and `marketplace.json`.

### 4. Commit version in skills submodule

`marketplace.json` lives inside the `skills` submodule, so it needs its own commit:

```bash
cd skills && git add .claude-plugin/marketplace.json && git commit -m "release: vX.Y.Z" && cd ..
```

### 5. Create release commit and tag

```bash
git add moon.mod.json src/update/version.mbt skills
git commit -m "release: vX.Y.Z"
git tag vX.Y.Z
```

### 6. Push

```bash
git push --follow-tags
```

`push.recurseSubmodules = on-demand` ensures:
1. `kgfs` submodule is pushed first
2. `skills` submodule is pushed second
3. Parent is pushed last
4. If any submodule push fails, the parent push is aborted

**NEVER** push the parent without `--follow-tags` — tags must travel with the release commit.

**NEVER** push submodules manually then the parent separately — use the on-demand mechanism to guarantee ordering.

## Push Safety

The `.gitmodules` file enforces `pushRecurseSubmodules = on-demand` for all submodules. This is a repository-level setting that applies to every clone.

Additionally, `.git/config` has the same setting as a local override. Both are needed:
- `.gitmodules`: shared across clones (checked into git)
- `.git/config`: applies immediately to the current working copy

## Verification

After push, verify:

```bash
# Tags are consistent
git tag --sort=-v:refname | head -1  # should be vX.Y.Z

# Submodules point to pushed commits
git submodule status  # no + prefix = clean

# Version is consistent across all targets
grep '"version"' moon.mod.json
grep 'current_version' src/update/version.mbt
grep '"version"' skills/.claude-plugin/marketplace.json
```

## Rollback

If the push fails partway:

```bash
# Remove tag locally
git tag -d vX.Y.Z

# Reset to pre-release commit
git reset --soft HEAD~1  # Undo release commit, keep changes staged

# Fix the issue, then redo steps 5-6
```

## DO NOT

- Do NOT amend the release commit after pushing
- Do NOT force-push to main
- Do NOT skip `sync-version.sh` — manual version editing causes drift
- Do NOT push parent before submodules — on-demand handles this, don't override
- Do NOT create the tag before the release commit
