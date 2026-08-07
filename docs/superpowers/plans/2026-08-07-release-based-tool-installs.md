# Release-Based Tool Installs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every tool the dotfiles install converges to its latest tagged release on `dotup`, and `pkg_verify` FAILs on version drift instead of passing on existence.

**Architecture:** Three shared helpers in `packages/lib.sh` encapsulate the whole release policy (resolve latest tag via the `/releases/latest` HEAD redirect, download + sha256-verify release assets, drift-check in verify). muster's pkg.sh swaps its clone+build block for those helpers; scratch's verify gains the drift check; `pkg_brew` drops `--no-upgrade`; the TPM bootstrap also updates plugins. Separately, the muster repo gets a CI guard so main-targeting PRs can't forget the VERSION bump.

**Tech Stack:** bash 3.2 (lib.sh/pkg.sh), zsh test harness (`tests/*.test.zsh`, curl stubbed via PATH shim), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-07-release-based-tool-installs-design.md`

## Global Constraints

- lib.sh and pkg.sh are **bash-3.2-safe, no `set -e`** (see lib.sh header). No associative arrays, no `${var,,}`.
- Failures during install must **warn and keep the existing binary**, never abort the whole install (offline dotup must work).
- Version checks in `pkg_verify` **FAIL on drift when online, skip silently offline**.
- No `gh`, no GitHub API calls in dotfiles code — plain `curl` to `github.com` only.
- Tests follow the existing convention: self-contained `tests/<name>.test.zsh`, `ok` PASS/FAIL counters, fake `$HOME`, exit non-zero on any FAIL. Run directly with `zsh tests/<name>.test.zsh`.
- Repos: dotfiles work happens in `/Users/courtschuett/dotfiles` (commit to `main`); Task 6 happens in `/Users/courtschuett/GitHub/schuettc/muster` (branch + PR, do NOT push to main directly).

---

### Task 1: lib.sh release helpers (TDD)

**Files:**
- Modify: `packages/lib.sh` (append after `pkg_brew`, line ~85)
- Test: `tests/release-helpers.test.zsh` (new)

**Interfaces:**
- Produces: `latest_release_tag <owner/repo>` → prints `vX.Y.Z` to stdout, rc 0; prints nothing, rc 1 on any failure (offline, no releases, unexpected redirect).
- Produces: `install_release_binary <owner/repo> <asset.tar.gz> <bin-name>` → installs to `$HOME/.local/bin/<bin-name>`, rc 0; on any failure warns and rc 1 with the existing binary untouched.
- Produces: `verify_release_current <owner/repo> <installed-version> <label>` → prints `  PASS <label> …` rc 0 when current, `  FAIL <label> …` rc 1 on drift, prints nothing rc 0 when the tag can't be resolved (offline). Accepts versions with or without a leading `v`.

- [ ] **Step 1: Write the failing test**

Create `tests/release-helpers.test.zsh`:

```zsh
#!/usr/bin/env zsh
# Tests for latest_release_tag / install_release_binary /
# verify_release_current in packages/lib.sh.
#
# Run directly:  zsh tests/release-helpers.test.zsh
#
# curl is stubbed via a PATH shim so no test touches the network. The stub
# serves a redirect URL for HEAD-style calls (-I/--head or -w url_effective)
# and copies fixture files for downloads (-o <file> <url>), driven by:
#   STUB_TAG      tag the fake /releases/latest redirect resolves to
#   STUB_ASSETS   dir holding fixture files served by basename of the URL
#   STUB_FAIL     non-empty → every curl invocation fails (offline)

set -u

REPO="${0:A:h:h}"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT

# ── curl stub ────────────────────────────────────────────────────────────
mkdir -p "$FAKE/bin"
cat > "$FAKE/bin/curl" <<'STUB'
#!/bin/bash
[[ -n "${STUB_FAIL:-}" ]] && exit 6
out="" url="" head=0
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i+1))]}"; ((i++)) ;;
    -I|--head) head=1 ;;
    -w) ((i++)) ;;                       # url_effective handled below
    -*) ;;                               # swallow other flags
    http*) url="${args[$i]}" ;;
  esac
done
if [[ "$url" == */releases/latest ]]; then
  # HEAD probe: emulate -w '%{url_effective}' by printing the final URL
  repo_path="${url%/releases/latest}"
  printf '%s/releases/tag/%s' "$repo_path" "${STUB_TAG:?}"
  exit 0
fi
# download: serve the fixture matching the URL's basename
src="${STUB_ASSETS:?}/$(basename "$url")"
[[ -f "$src" ]] || exit 22
cp "$src" "${out:?}"
STUB
chmod +x "$FAKE/bin/curl"

lib() {  # lib <bash snippet…> — fake HOME, stubbed curl first in PATH
  HOME="$FAKE" PATH="$FAKE/bin:$PATH" \
  STUB_TAG="${STUB_TAG:-}" STUB_ASSETS="${STUB_ASSETS:-}" STUB_FAIL="${STUB_FAIL:-}" \
    bash -c "source '$REPO/packages/lib.sh' >/dev/null 2>&1; $*" 2>/dev/null
}

# ── latest_release_tag ───────────────────────────────────────────────────
echo "── latest_release_tag ──"

STUB_TAG="v0.9.9"
ok "resolves the redirect tag" "v0.9.9" "$(lib 'latest_release_tag schuettc/muster')"
ok "rc 0 on success" "0" "$(lib 'latest_release_tag schuettc/muster >/dev/null; echo $?')"

STUB_FAIL=1
ok "offline prints nothing" "" "$(lib 'latest_release_tag schuettc/muster')"
ok "offline rc 1" "1" "$(lib 'latest_release_tag schuettc/muster >/dev/null; echo $?')"
unset STUB_FAIL

# ── install_release_binary ───────────────────────────────────────────────
echo "── install_release_binary ──"

# Build a fixture release: a tarball holding one executable + checksums.txt
ASSETS=$(mktemp -d)
mkdir -p "$ASSETS/stage"
printf '#!/bin/sh\necho fake-tool 9.9.9\n' > "$ASSETS/stage/faketool"
chmod +x "$ASSETS/stage/faketool"
tar -C "$ASSETS/stage" -czf "$ASSETS/faketool_test.tar.gz" faketool
( cd "$ASSETS" && shasum -a 256 faketool_test.tar.gz > checksums.txt )
STUB_ASSETS="$ASSETS"

ok "installs the binary" "0" \
   "$(lib 'install_release_binary schuettc/faketool faketool_test.tar.gz faketool; echo $?')"
ok "binary is on disk and executable" "1" \
   "$([[ -x "$FAKE/.local/bin/faketool" ]] && echo 1 || echo 0)"
ok "binary runs" "fake-tool 9.9.9" "$("$FAKE/.local/bin/faketool")"

# Corrupt checksum → refuse to install, keep the old binary
printf 'old\n' > "$FAKE/.local/bin/faketool"
( cd "$ASSETS" && printf '%064d  faketool_test.tar.gz\n' 0 > checksums.txt )
ok "checksum mismatch rc 1" "1" \
   "$(lib 'install_release_binary schuettc/faketool faketool_test.tar.gz faketool; echo $?')"
ok "old binary kept on mismatch" "old" "$(cat "$FAKE/.local/bin/faketool")"
( cd "$ASSETS" && shasum -a 256 faketool_test.tar.gz > checksums.txt )

# Offline → rc 1, binary untouched
STUB_FAIL=1
ok "offline rc 1, binary kept" "old" \
   "$(lib 'install_release_binary schuettc/faketool faketool_test.tar.gz faketool'; cat "$FAKE/.local/bin/faketool")"
unset STUB_FAIL

# ── verify_release_current ───────────────────────────────────────────────
echo "── verify_release_current ──"

STUB_TAG="v0.9.9"
ok "current → PASS rc 0" "0" "$(lib 'verify_release_current schuettc/muster 0.9.9 muster >/dev/null; echo $?')"
ok "PASS line names the label" "1" \
   "$(lib 'verify_release_current schuettc/muster 0.9.9 muster' | grep -c 'PASS muster')"
ok "leading v tolerated" "0" "$(lib 'verify_release_current schuettc/muster v0.9.9 muster >/dev/null; echo $?')"
ok "drift → FAIL rc 1" "1" "$(lib 'verify_release_current schuettc/muster 0.9.8 muster >/dev/null; echo $?')"
ok "FAIL line shows both versions" "1" \
   "$(lib 'verify_release_current schuettc/muster 0.9.8 muster' | grep -c '0.9.8.*v0.9.9')"
STUB_FAIL=1
ok "offline → silent rc 0" "0" "$(lib 'verify_release_current schuettc/muster 0.9.8 muster >/dev/null; echo $?')"
unset STUB_FAIL

rm -rf "$ASSETS"
echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zsh tests/release-helpers.test.zsh`
Expected: FAILs (the three functions don't exist yet, so `lib` calls print nothing / wrong rc).

- [ ] **Step 3: Implement the helpers in packages/lib.sh**

Append after the `pkg_brew` function (keep the section-comment style of the file):

```bash
# ─── release-based tool installs ────────────────────────────────────────────
# The version policy for self-built tools (muster, scratch, …): releases and
# tags are the source of truth. No gh, no GitHub API — one unauthenticated
# HEAD request resolves the latest tag (the /releases/latest redirect ends in
# /tag/vX.Y.Z), and assets come from the stable releases/latest/download URL.
# See docs/superpowers/specs/2026-08-07-release-based-tool-installs-design.md.

# latest_release_tag <owner/repo> — print the latest release tag (vX.Y.Z).
# Prints nothing and returns 1 on any failure (offline, no releases yet);
# callers treat that as "can't know" and keep what they have.
latest_release_tag() {
  local url
  url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' --max-time 10 \
    "https://github.com/$1/releases/latest" 2>/dev/null) || return 1
  case "$url" in
    */releases/tag/*) printf '%s\n' "${url##*/}" ;;
    *) return 1 ;;
  esac
}

# install_release_binary <owner/repo> <asset.tar.gz> <bin-name>
# Download the latest release's asset plus checksums.txt, verify the sha256,
# and install the tarball's <bin-name> into ~/.local/bin. Every failure path
# warns and returns 1 with the previously installed binary untouched.
install_release_binary() {
  local repo="$1" asset="$2" bin="$3"
  local base="https://github.com/$repo/releases/latest/download"
  local tmp; tmp=$(mktemp -d) || return 1
  if ! curl -fsSL --max-time 300 -o "$tmp/$asset" "$base/$asset" 2>/dev/null \
     || ! curl -fsSL --max-time 30 -o "$tmp/checksums.txt" "$base/checksums.txt" 2>/dev/null; then
    rm -rf "$tmp"
    warn "$bin: release download failed (offline?) — kept the existing binary."
    return 1
  fi
  local want got
  want=$(awk -v a="$asset" '$2 == a {print $1}' "$tmp/checksums.txt")
  got=$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')
  if [[ -z "$want" || "$want" != "$got" ]]; then
    rm -rf "$tmp"
    warn "$bin: sha256 mismatch on $asset — kept the existing binary."
    return 1
  fi
  if ! tar -xzf "$tmp/$asset" -C "$tmp" "$bin" 2>/dev/null; then
    rm -rf "$tmp"
    warn "$bin: $asset does not contain '$bin' — kept the existing binary."
    return 1
  fi
  mkdir -p "$HOME/.local/bin"
  chmod +x "$tmp/$bin"
  # mv, not cp: atomic swap; a running daemon keeps its old inode.
  mv -f "$tmp/$bin" "$HOME/.local/bin/$bin"
  rm -rf "$tmp"
}

# verify_release_current <owner/repo> <installed-version> <label>
# pkg_verify's drift check: FAIL (rc 1) when the installed version doesn't
# match the latest release tag; silent success when the tag can't be
# resolved (offline verify still stands on the capability checks).
verify_release_current() {
  local repo="$1" installed="$2" label="$3" latest
  latest=$(latest_release_tag "$repo") || return 0
  if [[ "${latest#v}" == "${installed#v}" && -n "$installed" ]]; then
    echo "  PASS $label at latest release ($latest)"
  else
    echo "  FAIL $label version ${installed:-unknown} != latest release $latest (run dotup)"
    return 1
  fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zsh tests/release-helpers.test.zsh`
Expected: all ok, `… passed, 0 failed`, rc 0.

- [ ] **Step 5: Run the existing lib.sh test to catch regressions**

Run: `zsh tests/harness-hook-merge.test.zsh`
Expected: unchanged, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add packages/lib.sh tests/release-helpers.test.zsh
git commit -m "feat(lib): release-install helpers — latest tag, checksummed asset install, drift verify"
```

---

### Task 2: muster package installs the released binary

**Files:**
- Modify: `packages/muster/pkg.sh:5-110` (pkg_install: replace the clone/build/LaunchAgent block), `packages/muster/pkg.sh:198-228` (pkg_verify: add drift check)

**Interfaces:**
- Consumes: `latest_release_tag`, `install_release_binary`, `verify_release_current` from Task 1 (lib.sh is already sourced before pkg.sh runs — see `run_pkg`).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Replace the build block in pkg_install**

In `packages/muster/pkg.sh`, delete everything from the `MUSTER_REPO="$HOME/GitHub/schuettc/muster"` line down to the end of the build `if/else` (the `else … echo "Skipping muster …"` block, currently lines ~13–110), **keeping** the LaunchAgent/MCP-registration section, and replace with:

```bash
  # muster: the local multi-agent coordination bus (github.com/schuettc/muster,
  # public). Installed from the latest GitHub RELEASE binary — never built
  # from a clone. Tags are the source of truth (see
  # docs/superpowers/specs/2026-08-07-release-based-tool-installs-design.md);
  # ~/GitHub/schuettc/muster, if present, is a dev checkout the installer
  # never touches. No Go toolchain required.
  local os arch asset latest installed replaced=0
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"      # darwin | linux (WSL=linux)
  arch="$(uname -m)"
  case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
  case "$os/$arch" in
    darwin/arm64|darwin/amd64|linux/amd64|linux/arm64)
      asset="muster_${os}_${arch}.tar.gz"
      latest="$(latest_release_tag schuettc/muster)" || latest=""
      installed="$("$HOME/.local/bin/muster" version 2>/dev/null | awk 'NR==1{print $2}')"
      if [[ -z "$latest" ]]; then
        warn "muster: can't reach github.com to resolve the latest release — kept ${installed:-nothing}."
      elif [[ "${latest#v}" == "$installed" ]]; then
        echo "muster $installed is current."
      else
        echo "Installing muster $latest (was ${installed:-not installed})..."
        install_release_binary schuettc/muster "$asset" muster && replaced=1
      fi
      ;;
    *)
      warn "muster: no published release asset for $os/$arch — skipping."
      ;;
  esac
```

Then wrap the LaunchAgent block (plist heredoc + launchctl bootout/bootstrap) in a darwin guard, and only restart the daemon when the binary changed or it isn't running:

```bash
  if [[ -x "$HOME/.local/bin/muster" && "$os" == "darwin" ]]; then
    # ── Daemon via LaunchAgent ─────────────────────────────────────────
    # (existing comment block and plist heredoc stay exactly as they are)
    MUSTER_PLIST="$HOME/Library/LaunchAgents/tools.muster.serve.plist"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/share/muster"
    cat > "$MUSTER_PLIST" << EOF
    ... (unchanged plist content) ...
EOF
    if [[ "$replaced" == 1 ]] \
       || ! launchctl print "gui/$(id -u)/tools.muster.serve" 2>/dev/null | grep -q "state = running"; then
      echo "Starting muster daemon (LaunchAgent)..."
      launchctl bootout "gui/$(id -u)/tools.muster.serve" 2>/dev/null || true
      pkill -f "$HOME/.local/bin/muster serve" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$MUSTER_PLIST" 2>/dev/null \
        || warn "Couldn't bootstrap muster LaunchAgent — run: launchctl bootstrap gui/\$(id -u) $MUSTER_PLIST"
    fi
  fi
```

The MCP-registration section and the hooks/permissions merges below it stay
byte-for-byte unchanged, but move OUT of the old build-success `if` so they
run whenever `~/.local/bin/muster` exists (guard them with
`if [[ -x "$HOME/.local/bin/muster" ]]; then … fi` if they aren't already
reached — check the surviving control flow after the edit; `local` declarations
must remain inside functions).

- [ ] **Step 2: Add the drift check to pkg_verify**

In `pkg_verify`, after the `hook subcommand` probe, add:

```bash
  verify_release_current schuettc/muster \
    "$("$HOME/.local/bin/muster" version 2>/dev/null | awk 'NR==1{print $2}')" muster || ok=1
```

- [ ] **Step 3: Syntax-check and live-run the package**

Run: `bash -n packages/muster/pkg.sh && packages/run.sh muster`
Expected: "Installing muster v0.10.1 (was 0.10.0)...", daemon restart, then verify shows every PASS including `PASS muster at latest release (v0.10.1)`. (If upstream has released past 0.10.1, the newer tag appears instead.)

- [ ] **Step 4: Re-run to confirm skip-if-current**

Run: `packages/run.sh muster`
Expected: "muster 0.10.1 is current.", NO "Starting muster daemon" line (already running), verify all PASS.

- [ ] **Step 5: Confirm the daemon and bus survived**

Run: `launchctl print "gui/$(id -u)/tools.muster.serve" | grep state; ~/.local/bin/muster version`
Expected: `state = running`, version line matching the latest tag.

- [ ] **Step 6: Commit**

```bash
git add packages/muster/pkg.sh
git commit -m "feat(muster): install from latest GitHub release, verify drift; drop clone+build"
```

---

### Task 3: scratch verify reports and enforces its version

**Files:**
- Modify: `packages/terminal/pkg.sh:85-86` (the scratch line in pkg_verify)

**Interfaces:**
- Consumes: `verify_release_current` from Task 1.

- [ ] **Step 1: Replace the existence check**

In `packages/terminal/pkg.sh` `pkg_verify`, replace:

```bash
  { [[ -x "$HOME/.local/bin/scratch" ]] || command -v scratch &> /dev/null; } \
    && echo "  PASS scratch" || { echo "  FAIL scratch"; ok=1; }
```

with:

```bash
  if [[ -x "$HOME/.local/bin/scratch" ]] || command -v scratch &> /dev/null; then
    # Version = the Go module stamp (go install embeds it; a local-clone
    # fallback build reports (devel) and will FAIL the drift check online,
    # which is correct — it isn't a released binary).
    local sver=""
    command -v go &> /dev/null \
      && sver="$(go version -m "$HOME/.local/bin/scratch" 2>/dev/null | awk '$1=="mod"{print $3}')"
    echo "  PASS scratch (${sver:-unknown})"
    verify_release_current schuettc/scratch "$sver" scratch || ok=1
  else
    echo "  FAIL scratch"; ok=1
  fi
```

- [ ] **Step 2: Live-run the package**

Run: `bash -n packages/terminal/pkg.sh && packages/run.sh terminal`
Expected: verify shows `PASS scratch (v0.2.0)` and `PASS scratch at latest release (v0.2.0)` (or newer if scratch has auto-released since).

- [ ] **Step 3: Commit**

```bash
git add packages/terminal/pkg.sh
git commit -m "feat(terminal): scratch verify reports module version and fails on release drift"
```

---

### Task 4: pkg_brew upgrades formulae

**Files:**
- Modify: `packages/lib.sh:80-85` (pkg_brew)

**Interfaces:**
- Consumes/Produces: nothing new; every pkg.sh already calls `pkg_brew`.

- [ ] **Step 1: Drop --no-upgrade**

Replace the `pkg_brew` body in `packages/lib.sh`:

```bash
# Install AND upgrade the current package's Brewfile, if it has one.
# --no-upgrade was the old policy (install-if-missing, drift forever);
# dotup is the convergence mechanism now, so listed formulae/casks track
# brew's latest on every run.
pkg_brew() {
  [[ -f "$PKG_DIR/Brewfile" ]] || return 0
  brew bundle --file="$PKG_DIR/Brewfile" \
    || warn "$(basename "$PKG_DIR"): some brew packages failed — re-run 'brew bundle --file=$PKG_DIR/Brewfile'"
}
```

- [ ] **Step 2: Live-check with one package**

Run: `packages/run.sh core 2>&1 | head -30`
Expected: `brew bundle` output showing `Using …` for current formulae and `Upgrading …` for any outdated ones; no failures.

- [ ] **Step 3: Commit**

```bash
git add packages/lib.sh
git commit -m "feat(lib): pkg_brew upgrades Brewfile formulae on every run"
```

---

### Task 5: TPM updates tmux plugins on every run

**Files:**
- Modify: `packages/terminal/pkg.sh:38-54` (the TPM bootstrap block)

**Interfaces:**
- Consumes/Produces: nothing new.

- [ ] **Step 1: Add update_plugins to the bootstrap sequence**

In `packages/terminal/pkg.sh`, inside the `if command -v tmux` block, after the `run-shell … install_plugins` line and before the final `kill-server`, add:

```bash
    echo "Updating tmux plugins..."
    env -u TMUX tmux -L _bootstrap_tpm run-shell "$HOME/.tmux/plugins/tpm/bin/update_plugins all" 2>/dev/null || true
```

(Same throwaway `-L _bootstrap_tpm` socket and `$TMUX`-scrubbing rationale as the surrounding lines — see the comment block above them; do not touch it.)

- [ ] **Step 2: Live-run and spot-check a plugin moved/stayed at upstream head**

Run: `packages/run.sh terminal && git -C ~/.tmux/plugins/tmux-resurrect log --oneline -1 && git -C ~/.tmux/plugins/tmux-resurrect status -sb | head -1`
Expected: package run succeeds; the plugin's checkout is at its upstream default-branch head (status shows no `[behind N]`).

- [ ] **Step 3: Commit**

```bash
git add packages/terminal/pkg.sh
git commit -m "feat(terminal): tmux plugins update on every install/update"
```

---

### Task 6: muster repo — version-guard CI job

**Files:**
- Create: `/Users/courtschuett/GitHub/schuettc/muster/.github/workflows/version-guard.yml`

**Interfaces:**
- Consumes/Produces: nothing in dotfiles; standalone repo change.

- [ ] **Step 1: Sync the muster clone**

```bash
cd ~/GitHub/schuettc/muster && git fetch origin && git switch -c ci/version-guard origin/main
```

- [ ] **Step 2: Write the workflow**

Create `.github/workflows/version-guard.yml`:

```yaml
name: version-guard

# Merging to main with an unbumped VERSION silently releases nothing —
# that's how scratch shipped a rewrite on main that @latest never saw.
# This guard makes the knob impossible to forget: PRs targeting main must
# change VERSION, or carry the `no-release` label (docs/CI-only changes).
# labeled/unlabeled triggers re-run the check when the label is toggled,
# no new push needed. dev-targeting PRs are exempt: VERSION is bumped at
# promotion time.
on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, labeled, unlabeled]

permissions:
  contents: read

jobs:
  version-guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # need the base branch for the diff
      - name: VERSION bumped or no-release label
        env:
          LABELS: ${{ join(github.event.pull_request.labels.*.name, ' ') }}
          BASE: ${{ github.event.pull_request.base.sha }}
        run: |
          set -euo pipefail
          case " $LABELS " in
            *" no-release "*)
              echo "no-release label present — skipping VERSION check."
              exit 0 ;;
          esac
          if git diff --quiet "$BASE" HEAD -- VERSION; then
            echo "::error file=VERSION::VERSION is unchanged. Bump it (this PR releases on merge) or add the 'no-release' label."
            exit 1
          fi
          echo "VERSION bumped: $(git show "$BASE":VERSION | tr -d ' \n') -> $(tr -d ' \n' < VERSION)"
```

- [ ] **Step 3: Push the branch and open a PR to main — the PR tests its own guard**

```bash
git add .github/workflows/version-guard.yml
git commit -m "ci: guard main-targeting PRs — VERSION must bump or PR is labeled no-release"
git push -u origin ci/version-guard
gh pr create --repo schuettc/muster --base main \
  --title "ci: version-guard — main PRs must bump VERSION or carry no-release" \
  --body "PRs to main fail unless VERSION changed or the PR has the no-release label. Part of the releases-and-tags-for-everything policy (dotfiles spec 2026-08-07). This PR itself doesn't bump VERSION, so the new check should appear and FAIL until the label is added — that's the live test."
```

- [ ] **Step 4: Verify the guard fails, then label and verify it passes**

```bash
gh pr checks --repo schuettc/muster ci/version-guard --watch   # expect version-guard FAIL
gh label create no-release --repo schuettc/muster --description "PR intentionally releases nothing" 2>/dev/null || true
gh pr edit --repo schuettc/muster ci/version-guard --add-label no-release
gh pr checks --repo schuettc/muster ci/version-guard --watch   # expect version-guard PASS
```

Expected: FAIL before the label, PASS after — the guard's both branches proven live.

- [ ] **Step 5: Merge the PR**

```bash
gh pr merge --repo schuettc/muster ci/version-guard --merge --delete-branch
```

Expected: merge succeeds; release.yml runs on main and skips (VERSION unchanged and already released).

---

### Task 7: End-to-end dotup + docs touch-up

**Files:**
- Modify: `README.md` (only if it describes the old muster clone+build install — check first)

**Interfaces:** none.

- [ ] **Step 1: Full converge run**

Run: `./update.sh 2>&1 | tail -25`
Expected: pull (already current), all packages apply, warnings section empty of new version-related warnings, final `✓ dotfiles updated.` line.

- [ ] **Step 2: Whole-suite regression**

Run: `for t in tests/*.test.zsh; do echo "== $t"; zsh "$t" >/dev/null || echo "SUITE FAIL: $t"; done`
Expected: no `SUITE FAIL` lines.

- [ ] **Step 3: README accuracy check**

Run: `grep -n -i "muster\|scratch" README.md | head -20`
If the README describes building muster from a clone or scratch pinned behavior, update those sentences to "installed from the latest GitHub release" / "installed via go install @latest (auto-released on every push to main)". If it doesn't mention install mechanics, skip.

- [ ] **Step 4: Commit (if README changed) and push dotfiles**

```bash
git add README.md 2>/dev/null; git diff --cached --quiet || git commit -m "docs: README reflects release-based installs"
git push origin main
```

---

## Self-Review Notes

- Spec §1 → Task 6; §2 → Task 1; §3 → Task 2; §4 → Task 3; §5 → Task 4; §6 → Task 5; §7 (update.sh unchanged) → verified live in Task 7.
- Type/name consistency: helper names and argument orders in Tasks 2–3 match Task 1's definitions (`<owner/repo> <asset|version> <bin|label>`).
- muster pkg.sh restructure (Task 2 Step 1) is the riskiest edit: the old code nests MCP/hook wiring inside the build-success branch; the step calls out moving it out and re-checking control flow, and Steps 3–5 exercise install, idempotence, and daemon health live.
