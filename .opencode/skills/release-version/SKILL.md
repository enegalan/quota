---
name: release-version
description: Bump Quota's version, update the changelog and README, verify, commit, tag, push, and trigger the GitHub release workflow.
metadata:
  audience: maintainer
---

# Release Version

Use this when cutting a new Quota release. The release is tag-driven: pushing `vX.Y.Z`
runs `.github/workflows/release.yml`, which checks that the tag matches
`App/Info.plist`'s `CFBundleShortVersionString`, builds both architectures, and
attaches the bundles and checksums to the GitHub Release.

## Before you start

- Make sure the working tree is clean: `git status --porcelain` must be empty.
- Make sure you are on the main branch and up to date:
  `git checkout main && git pull --ff-only`.
- Confirm the latest tag: `git describe --tags --abbrev=0`.
- Review the changes going out: `git log $(git describe --tags --abbrev=0)..HEAD --oneline`.
- Choose the next semantic version (`X.Y.Z`) and confirm it with the user before editing.

## 1. Update the changelog

Edit `CHANGELOG.md`:

- Add a new section immediately above the latest released version.
- Use the existing heading shape: `## [X.Y.Z] - YYYY-MM-DD`.
- If items are still under `## [Unreleased]`, move them into the new section and
  leave `## [Unreleased]` empty.
- Group changes under `### Added`, `### Changed`, `### Fixed`, or `### Removed`,
  matching the style of earlier entries. Keep lines wrapped to the project's
  width, as Prettier checks Markdown.

## 2. Update the version

Set the bundle's own version so the release workflow can verify it:

```sh
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString X.Y.Z' App/Info.plist
```

(Or run `./.opencode/skills/release-version/scripts/bump-version.sh X.Y.Z`.)

Optionally bump `CFBundleVersion` if you want the internal build number to move; the
workflow only compares `CFBundleShortVersionString` with the tag.

If you want the README to stay accurate, also replace the current version string
in `README.md` (the `Version 1.0.x` line and the install links if you keep them).

## 3. Verify

Run everything CI runs before touching git:

```sh
make verify
```

Do not continue if lint, tests, plugins, or the bundle step fail.

## 4. Commit

```sh
git add App/Info.plist CHANGELOG.md README.md
git commit -m "chore(release): X.Y.Z"
```

Only stage the files you actually changed.

## 5. Tag

Create an annotated tag matching the version exactly:

```sh
git tag -a vX.Y.Z -m "vX.Y.Z"
```

## 6. Push

Push the commit and the tag:

```sh
git push origin main
git push origin vX.Y.Z
```

Pushing the `v*` tag is what starts `.github/workflows/release.yml`.

## 7. Watch the release

```sh
gh run list --workflow release.yml --limit 5
gh run watch
```

When the run finishes successfully, confirm the assets:

```sh
gh release view vX.Y.Z
```

If a job fails, fix it on `main` only if the problem is a code issue; re-running the
workflow for the existing tag is preferred over cutting a new tag when the tag itself
is correct.

## Guards

- Never force-push `main` or move a tag after it has been pushed.
- Never tag a commit where `make verify` did not pass.
- The workflow refuses a tag that disagrees with `CFBundleShortVersionString`; keep
  the two in lockstep.
- One release at a time: the release workflow serialises itself, so a second tag
  simply waits.
