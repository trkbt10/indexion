---
name: deploy-process
description: Release process for indexion. Use when the user asks to release, deploy, bump version, create a tag, or push a release. Ensures submodule→parent push ordering, version sync, and tag consistency.
---

# indexion Release Process

## Prerequisites

- `.gitmodules` has `pushRecurseSubmodules = on-demand` for all submodules
- `scripts/sync-version.sh` exists and syncs `moon.mod` → `version.mbt` + `marketplace.json` + `plugin.json`

## Version Convention

- SoT: `moon.mod` → `version` field (TOML)
- Semver: `MAJOR.MINOR.PATCH`
- Tags: `v{VERSION}` (e.g. `v0.8.0`)
- Propagation targets:
  - `src/update/version.mbt` → `current_version` constant
  - `skills/.claude-plugin/marketplace.json` → `"version"` field
  - `skills/.claude-plugin/plugin.json` → `"version"` field

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

### 2. Update RELEASE_NOTES.md

Prepend release notes for the new version at the top of `RELEASE_NOTES.md`:

```markdown
# vX.Y.Z

## Highlights

- **Feature A** — Brief description
- **Feature B** — Brief description

## New Features

### Feature A

Detailed description...

## Improvements

- Item 1
- Item 2

## Bug Fixes

- Fix 1
- Fix 2

---

# vX.Y-1.Z (previous version header follows)
```

Use `git log vPREV..HEAD --oneline` to review commits since last release.

### 3. Run local verification

Before bumping version, verify all checks pass locally:

```bash
# MoonBit tests
moon test --target native

# TypeScript tests
bun run test

# Lint
bun run lint
```

### 4. Bump version in moon.mod

Edit `moon.mod` and change the `version` field (TOML: `version = "x.y.z"`):
- `+0.0.1` for patches (bug fixes)
- `+0.1.0` for minor (new features, backward compatible)
- `+1.0.0` for major (breaking changes)

### 5. Run sync-version.sh

```bash
bash scripts/sync-version.sh
```

This propagates the version to `version.mbt` and `marketplace.json`.

### 6. Commit version in skills submodule

`marketplace.json` lives inside the `skills` submodule, so it needs its own commit:

```bash
cd skills && git add .claude-plugin/marketplace.json .claude-plugin/plugin.json && git commit -m "release: vX.Y.Z" && cd ..
```

### 7. Create release commit (WITHOUT tag)

```bash
git add moon.mod src/update/version.mbt skills RELEASE_NOTES.md
git commit -m "release: vX.Y.Z"
```

**DO NOT create the tag yet.**

### 8. Push and wait for CI

```bash
git push
```

`push.recurseSubmodules = on-demand` ensures:
1. `kgfs` submodule is pushed first
2. `skills` submodule is pushed second
3. Parent is pushed last

Then verify that every submodule commit actually reached its remote — `on-demand`
has been observed to push only one of the two submodules, and CI then fails at
checkout with "Fetched in submodule path 'kgfs', but it did not contain ...":

```bash
git -C kgfs fetch -q origin && git -C kgfs log origin/main..HEAD --oneline   # must be empty
git -C skills fetch -q origin && git -C skills log origin/main..HEAD --oneline # must be empty
# if not empty: git -C kgfs push origin main   (resp. skills)
```

A failed run cannot be re-run without admin rights on the repository, so a
missed submodule push costs an extra commit on main to retrigger CI. Check
before pushing the parent, not after.

**Wait for CI to pass on GitHub Actions.** Check the workflow status before proceeding.

### 9. Create and push tag (after CI passes)

Only after CI passes:

```bash
git tag -a vX.Y.Z -m "release: vX.Y.Z"
git push origin vX.Y.Z
```

Use `git tag -a` (annotated tag) for proper release semantics.

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
grep '^version' moon.mod
grep 'current_version' src/update/version.mbt
grep '"version"' skills/.claude-plugin/marketplace.json
grep '"version"' skills/.claude-plugin/plugin.json
```

## Rollback

If CI fails after pushing the release commit:

```bash
# Fix the issue locally
# Commit the fix
git add ... && git commit -m "fix: ..."

# Push the fix
git push

# Wait for CI to pass, then proceed to step 9
```

If the tag was already pushed and needs to be removed:

```bash
# Remove tag from remote
git push origin :refs/tags/vX.Y.Z

# Remove tag locally
git tag -d vX.Y.Z

# After fixing issues, recreate the tag on the correct commit
git tag -a vX.Y.Z -m "release: vX.Y.Z"
git push origin vX.Y.Z
```

## DO NOT

- Do NOT create the tag before CI passes
- Do NOT amend the release commit after pushing
- Do NOT force-push to main
- Do NOT skip `sync-version.sh` — manual version editing causes drift
- Do NOT push parent before submodules — on-demand handles this, don't override
