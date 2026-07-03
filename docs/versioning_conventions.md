# Versioning conventions

**Source of truth for every version bump.** Read this file *every time* you increment
the version. Historically every release bumped only PATCH+BUILD (`2.0.x+n`) even when it
shipped genuinely new features — that is wrong. Follow the procedure below instead.

## Version anatomy

`pubspec.yaml` carries a single line:

```
version: X.Y.Z+B
```

- `X.Y.Z` — the **semantic version**, surfaced to users as the Play Store `versionName`.
- `B` — the **build number**, used as the Android `versionCode`.

`B` is **not** part of semver. It **must strictly increase by 1 on every release** —
Play Store rejects an upload that reuses a `versionCode`. It increments regardless of
which semver field (if any) changes.

## The decision procedure

Run this every time you bump. Never default to PATCH out of habit.

### 1. Establish the range

The changes under evaluation are everything since the **last released tag**:

```bash
LAST=$(git describe --tags --abbrev=0)   # e.g. v2.0.22+31
git log --pretty='%s' "$LAST..HEAD"      # commit subjects in range
git diff --stat "$LAST..HEAD"            # files touched in range
```

Read **both** the commit subjects and the actual diff. Commit prefixes are the primary
signal; the diff is the corroborating signal (see step 3).

### 2. Classify each change

The project uses Conventional-Commit prefixes, which map directly onto semver:

| Level | Bump          | Triggers                                                                                                                                                                                                                                                    |
|-------|---------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **MAJOR** `X` | `X+1.0.0` | Incompatible / breaking change. This app has no public API, so "breaking" means **user- or backend-contract breaking**: requires a newer ERPNext/backend version, removes or reworks a workflow users depend on, or changes data/session/format in a way that forces re-login or migration. Signals: `feat!:` / `fix!:`, a `BREAKING CHANGE:` footer, or a deliberately declared milestone. |
| **MINOR** `Y` | `X.Y+1.0` | New **backward-compatible capability**: a new module, screen, report, button, or flow that adds function without breaking existing use. Signal: any `feat:` in the range. **This is the level that was previously mis-shipped as PATCH.**                    |
| **PATCH** `Z` | `X.Y.Z+1` | Backward-compatible **fix or polish only**: bug fixes, performance, contrast/UI tweaks, refactors, docs, chores, tests. Signals: `fix:`, `perf:`, `refactor:`, `style:`, `docs:`, `chore:`, `test:` — and nothing higher.                                    |

### 3. Resolve to a single bump

- **Highest level wins.** Scan the whole range: if *any* change is breaking → MAJOR;
  else if *any* change is a `feat` → MINOR; else → PATCH. A range containing both a
  `feat` and several `fix`es is a **MINOR** release.
- **Reset the lower fields.** A MINOR bump resets PATCH to `0` (`2.0.22 → 2.1.0`).
  A MAJOR bump resets both MINOR and PATCH to `0` (`2.0.22 → 3.0.0`). PATCH increments
  in place (`2.0.22 → 2.0.23`).
- **The diff overrides a mislabeled commit.** A commit's prefix can be wrong. If a
  commit tagged `fix:` adds new files under `lib/app/modules/**`, it is really a feature —
  treat it as MINOR. If the whole range only touches `*.md` and `test/`, it is docs/chore.
  When the commit type and the diff disagree, take the **higher** level and note why.
- **Chore/docs-only release.** If nothing in the range warrants even a PATCH (e.g. a
  release cut purely to rebuild), keep `X.Y.Z` unchanged and increment only `B`. The
  build still ships; the semantic version honestly reflects "no functional change."

### 4. Apply

Edit the single `version:` line in `pubspec.yaml`, then release per the CI flow
(tag `v<new-version>` on `release/play-store`; see `.github/workflows/release.yml` and
the CI/CD pipeline notes).

## Helper script

`tool/bump_version.dart` automates steps 1–3 and prints its reasoning:

```bash
dart run tool/bump_version.dart            # dry-run: classify range, propose next version
dart run tool/bump_version.dart --write    # apply the auto-classified bump to pubspec.yaml
dart run tool/bump_version.dart --minor --write   # override the classification, then apply
```

The script is an aid, not an authority. When the diff carries nuance the classifier
can't see (a breaking backend requirement, a milestone), override it with
`--major` / `--minor` / `--patch` and record the reason in the release notes.

## Worked examples

| Range contents                                                      | Correct bump          |
|---------------------------------------------------------------------|-----------------------|
| `feat(global-search): …`, `fix(...): …`, `chore(release): …`        | MINOR → `2.1.0+B`     |
| `fix(...): …`, `fix(...): …`, `docs(...): …`                        | PATCH → `2.0.23+B`    |
| `docs(...): …` only                                                 | none → `2.0.22+B` (B+1) |
| `feat!: drop legacy DN sync; requires ERPNext v15.x`                | MAJOR → `3.0.0+B`     |
| `fix: …` that adds a whole new `lib/app/modules/foo/` module        | MINOR (diff overrides label) → `2.1.0+B` |
