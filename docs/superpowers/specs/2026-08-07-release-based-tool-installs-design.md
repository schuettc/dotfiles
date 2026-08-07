# Release-based tool installs: releases and tags for everything

**Date:** 2026-08-07
**Status:** Approved

## Problem

The dotfiles install self-built tools (muster, scratch) with no notion of
"the right version," so machines drift:

- **scratch** installed `@latest`, which resolves the highest semver tag. The
  per-user pad-store rewrite shipped on `main` but no tag was ever cut, so
  every machine ran v0.1.2 and wrote `.scratch.md` into working trees.
- **muster** ignores tags entirely: pkg.sh builds `origin/main` from a local
  clone at whatever moment `dotup` last ran. Upstream's latest release is
  v0.10.1; this machine's binary reports 0.10.0. Releases exist but nothing
  consumes them.
- `pkg_verify` checks existence (plus one capability probe), never version —
  a years-stale binary passes.

Policy decision: **releases and tags are the single source of truth for
every tool, produced automatically or guarded in CI, and consumed by the
dotfiles installer.** `dotup` (update.sh → install.sh → every pkg_install)
is the convergence mechanism: after it runs, the machine is on the latest
release of everything, and verify proves it.

## Already shipped (this session)

scratch now auto-releases: every push to main runs the tests, computes the
next version from the latest `v*` tag (patch by default; `#minor`/`#major`
in the commit *subject* override — the body is ignored, learned the hard way
when body prose released v1.0.0), and publishes a GitHub release, which cuts
the tag. v0.2.0 is live and `go install @latest` resolves it.

## Remaining work

### 1. muster repo: CI guard on the VERSION knob

muster keeps its deliberate VERSION-file release flow (it supports rc
pre-releases like v0.11.0-rc.1 and notarized cross-compiled assets;
auto-release-per-push would fight both). The guard kills the only failure
mode — forgetting the bump:

- New `version-guard` job in ci.yml, on
  `pull_request: [opened, synchronize, reopened, labeled, unlabeled]`.
- FAIL unless `VERSION` differs from the merge base on main, OR the PR
  carries a `no-release` label (docs/CI-only changes).
- `labeled`/`unlabeled` triggers mean adding the label re-runs the check
  without a new push.
- release.yml is untouched.

### 2. dotfiles lib.sh: shared release helpers

The policy lives in one place — three functions in `packages/lib.sh`, so
every current and future self-built tool gets identical behavior instead of
re-implementing it per package:

- `latest_release_tag <owner/repo>` — resolve the latest release tag via
  one unauthenticated HEAD request (the `/releases/latest` redirect's URL
  ends in `/tag/vX.Y.Z`). Empty output on network failure; never fatal.
- `install_release_binary <owner/repo> <asset> <bin-name>` — download the
  asset from `releases/latest/download/`, verify its sha256 against the
  release's `checksums.txt`, extract/install to `~/.local/bin/<bin-name>`.
  Any failure keeps the existing binary and warns.
- `verify_release_current <owner/repo> <installed-version>` — the drift
  check for pkg_verify: FAIL if a latest tag resolves and the installed
  version doesn't match it; silently skip when offline.

No `gh`, no GitHub API, no rate limits — plain HTTPS requests:

```bash
# Latest tag: one HEAD request; the /releases/latest redirect ends in /tag/vX.Y.Z
latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
  https://github.com/schuettc/muster/releases/latest)
latest="${latest##*/}"

# Asset name derived from the machine — never hardcoded
os="$(uname -s | tr '[:upper:]' '[:lower:]')"    # darwin | linux (WSL = linux)
arch="$(uname -m)"
case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac   # linux says aarch64
asset="muster_${os}_${arch}.tar.gz"
# stable URL, no tag interpolation needed:
# https://github.com/schuettc/muster/releases/latest/download/$asset
```

### 3. dotfiles muster package: install the released binary

Replace pkg.sh's clone+fetch+worktree+build block with the lib.sh helpers.
Install flow:

1. Resolve `latest` via the HEAD redirect. Network failure → keep the
   existing binary, warn, continue (offline dotup must not break).
2. **Skip-if-current:** if `muster version` already reports `${latest#v}`,
   do nothing (idempotent, quiet dotup, no re-download).
3. Download the asset from `releases/latest/download/`, plus
   `checksums.txt`; verify the tarball's sha256 against it. Mismatch →
   abort install, keep the old binary, warn.
4. Extract to `~/.local/bin/muster`, then restart the daemon (existing
   bootout/bootstrap sequence).
5. Unrecognized `$os`/`$arch` (no published asset) → warn and skip; never
   download garbage.

Unchanged: LaunchAgent plist, MCP registrations (Claude/Codex/Cursor), and
session-hook merges — but the LaunchAgent/launchctl block gains a
`[[ "$os" == "darwin" ]]` guard so a linux install doesn't spray launchctl
errors (systemd supervision is explicitly out of scope).

Removed: the `~/GitHub/schuettc/muster` clone dependency. The clone stays
on disk as a dev checkout; installs never touch it. Go is no longer needed
to install muster.

`pkg_verify` changes:

- Keep: binary exists, `hook` subcommand probe, daemon running, socket,
  MCP/hook wiring checks.
- Add: `muster version` output parses to a version (not "dev").
- Add: when the network answers the HEAD request, FAIL if the installed
  version ≠ latest release tag. Offline → skip this check silently (the
  capability probes still stand). FAIL (not warn) is the point: verify is
  the "are we all on the right version" enforcement.

### 4. dotfiles scratch package: version visibility

`go install @latest` is now correct (auto-release keeps tags fresh); the
install line stays, as does the offline local-clone fallback.

`pkg_verify` upgrades from "binary exists":

- Report the installed module version via
  `go version -m ~/.local/bin/scratch` (the `mod` line).
- When online, FAIL if it lags the latest upstream tag (via
  `verify_release_current schuettc/scratch <version>`). Offline →
  existence check only.

### 5. Brew formulae: upgrade on every install/update

`pkg_brew` currently runs `brew bundle --no-upgrade` — install-if-missing,
never upgrade, so formulae drift indefinitely (a machine that installed
tmux two years ago still runs it). Drop `--no-upgrade`: every dotup
converges each package's Brewfile formulae to brew's latest. When
everything is already current this adds seconds; when it isn't, that was
the point. (Casks and fonts in Brewfiles get the same treatment.)

### 6. tmux plugins: update on every install/update

The TPM bootstrap in terminal/pkg.sh clones plugins once and never touches
them again. In the same throwaway-socket sequence that runs
`install_plugins`, also run `tpm/bin/update_plugins all` so plugins track
their upstreams on every dotup.

### 7. update.sh: no changes

It already re-runs every pkg_install. With installs tag-pinned-to-latest
and idempotent, `dotup` is the convergence mechanism on every machine.

### Already standardized, no changes

- **nvim plugins** — `lazy-lock.json` is committed; lazy.nvim bootstraps
  from it. Pinned and converged already; the model the rest now follows.
- **Claude Code** — self-updating.

## Testing

- **muster CI guard:** exercised by its first real PRs (a VERSION-bumping
  PR passes; a docs PR fails until labeled `no-release`). No local harness.
- **dotfiles pkg.sh:** run `packages/run.sh muster` on this machine —
  expect: resolves v0.10.1+, replaces the 0.10.0 binary, daemon restarts,
  verify all-PASS including the new version check. Run again — expect the
  skip-if-current path (no download). `packages/run.sh terminal` — expect
  scratch verify to report v0.2.0 and PASS.
- **Failure paths:** spot-check by faking `latest` resolution failure
  (temporarily bad URL) — install must warn and keep the binary.
- **Brew upgrade:** `packages/run.sh core` — expect outdated formulae to
  upgrade; a second run is quiet.
- **tmux plugins:** terminal package run leaves plugins at their upstream
  heads (spot-check one plugin's git log under ~/.tmux/plugins/).

## Out of scope

- systemd supervision for muster on linux.
- Native Windows (muster publishes no windows assets; the dotfiles are
  bash/Homebrew/LaunchAgent-shaped).
- Changing scratch's install to release-asset downloads (its workflow
  publishes no binaries; `go install` is fine for a TUI with a Go
  toolchain already present via the terminal package's Brewfile).
- Any change to muster's release.yml or rc flow.
