---
name: releasing-a-tools-family-tool
description: Use when shipping, releasing, tagging or cutting a release candidate of a .tools family tool (kempt, muster, galley, hail, tackle's scratch/proj/creel/casebook), when a merged change needs to reach Court's machine, when a release run fails or publishes nothing, or when checking signing credentials or what /dl serves.
---

# Releasing a .tools family tool

Court's standing rules: PRs are approved in advance, so **merge once CI is green**; **anything merged that changes a shipped binary is released**, then **`kempt update`** puts it on the machine. Every release goes through tools-actions (`release-version` + `go-release`): signed and notarized on macOS, checksums, GitHub release, `<site>/dl/<tool>/<version>/`, and `latest` moves only for a non-prerelease.

## First: is there anything to ship?

Find the change: the merged PR or commit (`gh pr view N --json state,mergeCommit`), and whether the newest release already contains it (`gh api repos/schuettc/<repo>/compare/<newest tag>...<branch> --jq .ahead_by`, and for tackle only commits under that tool's directory count). If the tool already has it and `/dl/<tool>/latest` serves it, there is nothing to release: say so, and just check the machine (below).

## Which model

| Tools | Model | A release is |
|---|---|---|
| kempt, hail | **main** | a PR into `main` that raises `VERSION` and adds the `CHANGELOG.md` entry; merging it releases |
| galley, muster | **dev → main** | features merge into `dev`; then (1) a "release prep" PR into `dev` setting `VERSION` and turning `## Unreleased` into `## X.Y.Z`, (2) a PR `dev` → `main` titled `<tool> X.Y.Z`; merging (2) releases |
| tackle (scratch, proj, creel, casebook) | **tags** | no `VERSION` file: a `CHANGELOG.md` entry merged to `main` first, then an annotated tag `<tool>/vX.Y.Z` on that commit, pushed **one tag per push** (GitHub drops tag events when more than 3 arrive in one push). tackle's single `CHANGELOG.md` covers only scratch today; per-tool entries are part of tackle's move onto the standard |

The next version comes from the newest release tag, not from memory. A PR into a release branch that changes no shipped binary carries the `no-release` label; otherwise the version guard fails it until `VERSION` is raised to a newer plain `X.Y.Z`.

**`dev` → `main` shows conflicts (DIRTY)?** Something landed on `main` directly and never came back. Check what (`git log origin/dev..origin/main`); if `dev` already supersedes it, merge `origin/main` into a branch off `dev` keeping `dev`'s side, confirm the tree equals `dev` (`git diff --cached --quiet origin/dev`), PR that into `dev`. Then the promotion is clean and its checks (including the version guard) run.

## Release candidates

VERSION tools: `gh workflow run release.yml -R schuettc/<tool> --ref <release ref>` with no tag: cuts `vX.Y.Z-rc.<run>` from that ref's `VERSION` as a prerelease; `/dl/<tool>/<rc>/` exists, `latest` does not move. So set `VERSION` to the coming version first (the release-prep PR), then dispatch. tackle: push a tag `<tool>/vX.Y.Z-rc.N` (precedent `scratch/v0.5.5-rc.1`); a version with `-` is a prerelease. The `release` environment **only accepts release refs** (Court, 2026-09-29): `main` (kempt, hail), `dev` or `main` (galley, muster), `*/v*` tags (tackle). So an rc runs after merge, never from a PR branch; for main-model tools that means the rc is of what `main` already holds. Try one without touching `latest`: `<TOOL>_VERSION=<rc> curl -fsSL https://<site>/install.sh | sh` (Court runs the `curl | sh`).

## After merging: confirm, do not assume

1. The PR is `MERGED` (`gh pr view N --json state`); a conflicting PR does not merge, and a "success" you saw may be another PR's run.
2. The release run finished green: `gh run list -R schuettc/<tool> -w release -b main -L1`.
3. `gh release view <tag>`: not a prerelease, assets present.
4. `curl -fsS https://<site>/dl/<tool>/latest` equals the new version.
5. `kempt update` (it rolls every family `download` tool to `latest`; the per-tool `<tool> update` is not the machine path). Check `<tool> version`.
6. muster only: the running daemon keeps the old binary until restarted. Restart it when the release changes daemon behaviour; see muster's `CHANGELOG.md` and muster#162 (`pgrep -fl 'muster serve'` shows which process actually owns it).

`tools-ops/templates/family/check.sh` checks 3–4 and the signature for every tool at once.

## Signing

The credentials are GitHub **environment secrets on each repo's `release` environment**: `APPLE_DEVELOPER_ID_P12`, `APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID` (`4N7ZC9G3HF`), `APPLE_NOTARY_ISSUER_ID`, and `APPLE_DEVELOPER_ID_P12_PASSWORD` only where the p12 has one. List names with `gh api repos/schuettc/<tool>/environments/release/secrets`. Identity: "Developer ID Application: Court Schuett (9JA73SU683)". **The Developer ID certificate expires 2027-02-01**; after that every macOS release fails to sign. Replacing it is Court's (Apple account), then the p12 secret in every repo's `release` environment. go-release refuses to publish unsigned macOS binaries.

Proof a binary is signed: `codesign -dv <binary>` shows `TeamIdentifier=9JA73SU683` (capture the output; do not pipe it into `grep -q` under `pipefail`).
