# Install Packages + Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the monolithic `install.sh` into 8 per-package install scripts (with per-package Brewfiles and declared deps) driven co-equally by the root installer and a new Claude Code install-wizard skill.

**Architecture:** `packages/<name>/pkg.sh` each define `PKG_DESC`, `PKG_DEPS`, `pkg_install()`, `pkg_verify()`; `packages/lib.sh` holds shared helpers and the runner; `packages/run.sh` runs an explicit package list with dep safety; root `install.sh` runs all packages in fixed order; `.claude/skills/install-wizard/SKILL.md` walks strangers through selective installs. Spec: `docs/superpowers/specs/2026-07-15-install-packages-wizard-design.md`.

**Tech Stack:** bash 3.2 (macOS stock), Homebrew, jq, launchd, Claude Code skills.

## Global Constraints

- bash 3.2 compatible; NO `set -e` (resilient-by-design: warn and continue); every script passes `bash -n`.
- All `brew bundle` calls use `--no-upgrade` (install-only; never upgrade running tools).
- All package installs are idempotent — safe to re-run on an installed machine with zero state change.
- macOS guard stays in root `install.sh` (`uname == Darwin` or die).
- muster clones via HTTPS: `https://github.com/schuettc/muster.git` (repo is public).
- Settings-file hook merges are ADDITIVE and idempotent (ensure-entry-present; never wholesale-replace another package's hooks).
- The current `install.sh` (376 lines, commit `1b76a57`) is the extraction source; it is NOT modified until Task 10, so cited line ranges stay valid throughout.
- Verification on this machine: `pkg_verify` for every package must PASS both before Task 10 (machine already installed) and after the full new `install.sh` run.

**Fixed package order (dependency-safe):** `core terminal nvim markedit claude swiftbar codex muster`

---

### Task 1: packages/lib.sh + packages/run.sh

**Files:**
- Create: `packages/lib.sh`
- Create: `packages/run.sh`

**Interfaces:**
- Produces: `DOTFILES_DIR`, `CONFIG_DIR`, `WARNINGS[]`, `warn()`, `die()`, `backup_if_exists()`, `pkg_brew()`, `run_pkg(name)` — every later task's `pkg.sh` runs under these. `run.sh <name>…` is what the wizard executes.

- [ ] **Step 1: Write `packages/lib.sh`**

```bash
#!/bin/bash
# Shared helpers for package install scripts. Sourced (not executed) by
# install.sh and packages/run.sh. bash-3.2-safe; no set -e by design.

PACKAGES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$PACKAGES_DIR")"
CONFIG_DIR="$HOME/.config"

WARNINGS=()
warn() { printf '  ⚠ %s\n' "$1" >&2; WARNINGS+=("$1"); }
die()  { printf '\n✗ FATAL: %s\n' "$1" >&2; exit 1; }

backup_if_exists() {
  if [[ -e "$1" && ! -L "$1" ]]; then
    echo "Backing up $1 to $1.bak"
    mv "$1" "$1.bak"
  fi
}

# Install the current package's Brewfile, if it has one. Install-only.
pkg_brew() {
  [[ -f "$PKG_DIR/Brewfile" ]] || return 0
  brew bundle --no-upgrade --file="$PKG_DIR/Brewfile" \
    || warn "$(basename "$PKG_DIR"): some brew packages failed — re-run 'brew bundle --no-upgrade --file=$PKG_DIR/Brewfile'"
}

# Source and run one package in the current shell (keeps WARNINGS shared).
run_pkg() {
  local name="$1" dir="$PACKAGES_DIR/$1"
  [[ -f "$dir/pkg.sh" ]] || { warn "unknown package: $name"; return 1; }
  PKG_DIR="$dir"
  unset -f pkg_install pkg_verify 2>/dev/null
  PKG_DESC="" ; PKG_DEPS=()
  source "$dir/pkg.sh"
  echo ""
  echo "── $name: $PKG_DESC"
  pkg_install
  pkg_verify || warn "$name: verification reported failures"
}
```

- [ ] **Step 2: Write `packages/run.sh`**

```bash
#!/bin/bash
# Run an explicit list of packages (the wizard's entry point):
#   packages/run.sh claude terminal core
# Runs them in canonical dependency order regardless of argument order.
# Dep safety: every hard dep of a requested package must be in the request
# list OR already verify clean on this machine — otherwise we stop before
# installing anything.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[[ "$(uname)" == "Darwin" ]] || die "macOS only."
[[ $# -gt 0 ]] || die "usage: packages/run.sh <package>… (see packages/*/pkg.sh)"

ORDER=(core terminal nvim markedit claude swiftbar codex muster)

requested() { local needle="$1" p; shift; for p in "$@"; do [[ "$p" == "$needle" ]] && return 0; done; return 1; }

# Validate names + dep closure before touching anything.
for name in "$@"; do
  [[ -f "$PACKAGES_DIR/$name/pkg.sh" ]] || die "unknown package: $name"
done
for name in "$@"; do
  PKG_DIR="$PACKAGES_DIR/$name"; PKG_DEPS=()
  source "$PKG_DIR/pkg.sh"
  for dep in "${PKG_DEPS[@]}"; do
    if ! requested "$dep" "$@"; then
      PKG_DIR="$PACKAGES_DIR/$dep"
      unset -f pkg_install pkg_verify 2>/dev/null
      source "$PKG_DIR/pkg.sh"
      pkg_verify >/dev/null 2>&1 \
        || die "$name requires '$dep' — add it to the list (it is not installed on this machine)"
    fi
  done
done

# Execute in canonical order, only the requested set.
for name in "${ORDER[@]}"; do
  requested "$name" "$@" && run_pkg "$name"
done

echo ""
if (( ${#WARNINGS[@]} )); then
  echo "Finished with ${#WARNINGS[@]} warning(s):"
  for w in "${WARNINGS[@]}"; do echo "  ⚠ $w"; done
else
  echo "Finished — no warnings."
fi
```

- [ ] **Step 3: Syntax check both**

Run: `bash -n packages/lib.sh && bash -n packages/run.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Verify run.sh fails safely with no packages yet**

Run: `bash packages/run.sh core; echo "exit=$?"`
Expected: `✗ FATAL: unknown package: core` and `exit=1` (no package dirs exist yet).

- [ ] **Step 5: Commit**

```bash
git add packages/lib.sh packages/run.sh
git commit -m "feat(install): package runner scaffolding (lib.sh + run.sh)"
```

---

### Task 2: Distribute the Brewfile into per-package Brewfiles

**Files:**
- Create: `packages/{core,terminal,nvim,markedit,swiftbar,codex,muster}/Brewfile`
- (Root `Brewfile` untouched until Task 10; `claude` gets no Brewfile.)

**Interfaces:**
- Produces: per-package Brewfiles consumed by `pkg_brew()` in each Task 3–9 script.

- [ ] **Step 1: Write the seven Brewfiles.** Distribution rule: an entry lives with the package that needs it; general CLI QoL → core. Copy entries VERBATIM (with comments) from the root `Brewfile` per this assignment:

  - `packages/core/Brewfile`: `tap "1password/tap"`, formulas `starship atuin zsh-completions eza bat zoxide fzf fd ripgrep git-delta lazygit tlrc htop tree jq yq gh git git-lfs pipx uv awscli`, casks `1password-cli visual-studio-code docker-desktop`
  - `packages/terminal/Brewfile`: formulas `tmux yazi`, casks `ghostty font-fira-code-nerd-font font-meslo-lg-nerd-font font-jetbrains-mono-nerd-font font-monaspice-nerd-font`
  - `packages/nvim/Brewfile`: formula `neovim`
  - `packages/markedit/Brewfile`: cask `markedit`
  - `packages/swiftbar/Brewfile`: cask `swiftbar`
  - `packages/codex/Brewfile`: cask `codex`
  - `packages/muster/Brewfile`: `brew "go"                # Build toolchain for the muster binary` — NEW entry (latent gap: go was never in the root Brewfile).

- [ ] **Step 2: Set-equality check against the root Brewfile**

Run:
```bash
diff <(grep -hE '^(tap|brew|cask) ' Brewfile | awk '{print $1, $2}' | sort) \
     <(grep -hE '^(tap|brew|cask) ' packages/*/Brewfile | awk '{print $1, $2}' | sort | grep -v '"go"')
```
Expected: no output (identical sets, modulo the deliberately-added `go`).

- [ ] **Step 3: Commit**

```bash
git add packages/*/Brewfile
git commit -m "feat(install): distribute Brewfile into per-package Brewfiles (+go for muster)"
```

---

### Task 3: packages/core/pkg.sh

**Files:**
- Create: `packages/core/pkg.sh`
- Extraction source: `install.sh` lines 45–75 (symlinks: zsh/starship/atuin + history import)

**Interfaces:**
- Consumes: `lib.sh` helpers, `packages/core/Brewfile`.
- Produces: the `pkg.sh` contract shape every later package copies.

- [ ] **Step 1: Write `packages/core/pkg.sh`**

```bash
#!/bin/bash
# core — shell foundation. Sourced by packages/lib.sh's run_pkg.

PKG_DESC="Shell foundation: Homebrew CLI tools, zsh config, Starship prompt, Atuin history"
PKG_DEPS=()

pkg_install() {
  pkg_brew
  mkdir -p "$CONFIG_DIR"

  backup_if_exists "$HOME/.zshrc"
  ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
  backup_if_exists "$CONFIG_DIR/zsh"
  ln -sfn "$DOTFILES_DIR/config/zsh" "$CONFIG_DIR/zsh"

  backup_if_exists "$CONFIG_DIR/starship.toml"
  ln -sf "$DOTFILES_DIR/config/starship.toml" "$CONFIG_DIR/starship.toml"

  backup_if_exists "$CONFIG_DIR/atuin"
  ln -sfn "$DOTFILES_DIR/config/atuin" "$CONFIG_DIR/atuin"
  if command -v atuin &> /dev/null; then
    echo "Importing shell history into Atuin..."
    atuin import auto 2>/dev/null || true
  fi

  mkdir -p "$HOME/.local/bin"
}

pkg_verify() {
  local ok=0
  [[ "$(readlink "$HOME/.zshrc")" == "$DOTFILES_DIR/.zshrc" ]] \
    && echo "  PASS ~/.zshrc -> repo" || { echo "  FAIL ~/.zshrc symlink"; ok=1; }
  command -v starship &> /dev/null && echo "  PASS starship" || { echo "  FAIL starship missing"; ok=1; }
  command -v atuin &> /dev/null && echo "  PASS atuin" || { echo "  FAIL atuin missing"; ok=1; }
  return $ok
}
```

- [ ] **Step 2: Syntax + verify against the already-installed machine**

Run: `bash -n packages/core/pkg.sh && bash -c 'source packages/lib.sh; PKG_DIR=packages/core; source packages/core/pkg.sh; pkg_verify'`
Expected: three `PASS` lines, exit 0.

- [ ] **Step 3: Idempotency — run install, re-verify, confirm no symlink churn**

Run: `bash packages/run.sh core && readlink ~/.zshrc`
Expected: finishes "no warnings" (brew may print already-installed noise), `readlink` still `$HOME/dotfiles/.zshrc`.

- [ ] **Step 4: Commit**

```bash
git add packages/core/pkg.sh
git commit -m "feat(install): core package (brew CLI, zsh, starship, atuin)"
```

---

### Task 4: packages/terminal/pkg.sh

**Files:**
- Create: `packages/terminal/pkg.sh`
- Extraction source: `install.sh` lines 77–96 (Ghostty/tmux/yazi links) and 111–135 (TPM bootstrap — the `env -u TMUX -L _bootstrap_tpm` block, copy VERBATIM including its comment)

**Interfaces:**
- Consumes: lib helpers; `PKG_DEPS=(core)`.

- [ ] **Step 1: Write `packages/terminal/pkg.sh`** — contract shape exactly as Task 3; `PKG_DESC="Terminal workspace: Ghostty, tmux (+plugins), yazi file explorer, nerd fonts"`, `PKG_DEPS=(core)`. `pkg_install()` = `pkg_brew` + the Ghostty/tmux/yazi symlink lines (77–96) + the TPM block (111–135) verbatim. `pkg_verify()`:

```bash
pkg_verify() {
  local ok=0
  command -v tmux &> /dev/null && echo "  PASS tmux" || { echo "  FAIL tmux"; ok=1; }
  [[ "$(readlink "$HOME/.tmux.conf")" == "$DOTFILES_DIR/.tmux.conf" ]] \
    && echo "  PASS ~/.tmux.conf -> repo" || { echo "  FAIL ~/.tmux.conf"; ok=1; }
  [[ -d "$HOME/.tmux/plugins/tpm" ]] && echo "  PASS TPM" || { echo "  FAIL TPM missing"; ok=1; }
  [[ "$(readlink "$CONFIG_DIR/yazi")" == "$DOTFILES_DIR/config/yazi" ]] \
    && echo "  PASS yazi config" || { echo "  FAIL yazi config"; ok=1; }
  return $ok
}
```

- [ ] **Step 2: Syntax + verify (expect all PASS on this machine)** — same command pattern as Task 3 Step 2.
- [ ] **Step 3: Commit** — `git commit -m "feat(install): terminal package (ghostty, tmux+TPM, yazi, fonts)"`

---

### Task 5: packages/nvim/pkg.sh + packages/markedit/pkg.sh

**Files:**
- Create: `packages/nvim/pkg.sh` (source: install.sh lines 93–97)
- Create: `packages/markedit/pkg.sh` (source: install.sh lines 98–109, keep the container-gated skip)

- [ ] **Step 1: Write both.** nvim: `PKG_DESC="Neovim ($EDITOR) with LazyVim config"`, `PKG_DEPS=(core)`, install = `pkg_brew` + nvim config symlink; verify = `nvim` on PATH + symlink target. markedit: `PKG_DESC="MarkEdit markdown-editor styles (skips if app not installed)"`, `PKG_DEPS=(core)`, install = `pkg_brew` + lines 98–109 verbatim; verify = if container dir absent print `  PASS markedit (not installed — skipped)` return 0, else check editor.css symlink.
- [ ] **Step 2: Syntax + verify both** — same pattern; expect PASS.
- [ ] **Step 3: Commit** — `git commit -m "feat(install): nvim + markedit packages"`

---

### Task 6: packages/claude/pkg.sh — settings merge WITHOUT muster hooks

**Files:**
- Create: `packages/claude/pkg.sh`
- Extraction source: install.sh lines 137–144 (dirs + config link), 331–333 (claude-attn symlink). The settings merge (145–204) is REWRITTEN — additive, muster-free.

**Interfaces:**
- Produces: additive-hooks jq pattern (`ensure_hook`) that Task 9 reuses for muster's hooks.

- [ ] **Step 1: Write `packages/claude/pkg.sh`**

```bash
#!/bin/bash
PKG_DESC="Claude Code integration: tmux-aware statusline, attention-bell hooks, claude-attn CLI"
PKG_DEPS=(core)   # terminal recommended (bells/status need tmux) but not required

pkg_install() {
  pkg_brew
  echo "Setting up Claude Code..."
  mkdir -p "$HOME/.claude/sessions"
  backup_if_exists "$CONFIG_DIR/claude"
  ln -sfn "$DOTFILES_DIR/config/claude" "$CONFIG_DIR/claude"
  ln -sf "$DOTFILES_DIR/bin/claude-attn" "$HOME/.local/bin/claude-attn"

  local settings="$HOME/.claude/settings.json"
  [[ -f "$settings" ]] || echo '{}' > "$settings"
  if command -v jq &> /dev/null; then
    local tmp; tmp=$(mktemp)
    # Additive merge: set statusline/permissions; ensure our hook entries
    # exist WITHOUT touching entries owned by other packages (muster).
    if jq '
      def ensure_hook(ev; cmd):
        .hooks[ev] = ((.hooks[ev] // [])
          | if ([.[].hooks[]?.command] | index(cmd)) then .
            else . + [{"hooks":[{"type":"command","command":cmd}]}] end);
      .statusLine = {"type":"command","command":"~/.config/claude/statusline.sh"}
      | .permissions = ((.permissions // {}) + {"allow": (((.permissions.allow // []) + ["Bash(*/.claude/sessions/*)"]) | unique)})
      | ensure_hook("Notification"; "~/.config/claude/claude-notify.sh")
      | ensure_hook("Stop"; "~/.config/claude/claude-notify.sh")
    ' "$settings" > "$tmp"; then
      mv "$tmp" "$settings"
    else
      rm -f "$tmp"; warn "Couldn't merge Claude settings (jq error) — ~/.claude/settings.json untouched."
    fi
  else
    warn "jq missing — merge Claude statusline/hooks into ~/.claude/settings.json by hand."
  fi
}

pkg_verify() {
  local ok=0 s="$HOME/.claude/settings.json"
  [[ "$(readlink "$CONFIG_DIR/claude")" == "$DOTFILES_DIR/config/claude" ]] \
    && echo "  PASS ~/.config/claude -> repo" || { echo "  FAIL config link"; ok=1; }
  command -v claude-attn &> /dev/null && echo "  PASS claude-attn" || { echo "  FAIL claude-attn"; ok=1; }
  jq -e '.statusLine.command == "~/.config/claude/statusline.sh"' "$s" >/dev/null 2>&1 \
    && echo "  PASS statusline wired" || { echo "  FAIL statusline"; ok=1; }
  jq -e '[.hooks.Stop[].hooks[]?.command] | index("~/.config/claude/claude-notify.sh")' "$s" >/dev/null 2>&1 \
    && echo "  PASS notify hooks" || { echo "  FAIL notify hooks"; ok=1; }
  return $ok
}
```

- [ ] **Step 2: Syntax + verify (PASS expected)**; then the critical merge test — run `pkg_install` and confirm the existing muster hooks in settings.json SURVIVED:

Run: `bash packages/run.sh claude && jq -r '[.hooks.Stop[].hooks[].command] | join("\n")' ~/.claude/settings.json`
Expected: BOTH `~/.config/claude/claude-notify.sh` AND `~/dotfiles/bin/muster-session-hook.sh Stop claude` present (additive merge preserved muster's entry).

- [ ] **Step 3: Commit** — `git commit -m "feat(install): claude package with additive settings merge (muster hooks decoupled)"`

---

### Task 7: packages/swiftbar/pkg.sh

**Files:**
- Create: `packages/swiftbar/pkg.sh`
- Extraction source: install.sh lines 334–351 (defaults write, login item, open, A11y note) — copy verbatim into `pkg_install` after `pkg_brew`. The A11y reminder prints directly (no epilogue variable): `echo "  ⚠ MANUAL: grant SwiftBar Accessibility (System Settings → Privacy & Security → Accessibility), then restart SwiftBar."`

- [ ] **Step 1: Write it.** `PKG_DESC="SwiftBar menu-bar attention indicator (🔔 per waiting Claude session, click to focus)"`, `PKG_DEPS=(claude)`. `pkg_verify()`: `[[ -d /Applications/SwiftBar.app ]]` PASS/FAIL + `defaults read com.ameba.SwiftBar PluginDirectory` equals `$DOTFILES_DIR/config/swiftbar/plugins`.
- [ ] **Step 2: Syntax + verify (PASS expected).**
- [ ] **Step 3: Commit** — `git commit -m "feat(install): swiftbar package"`

---

### Task 8: packages/codex/pkg.sh

**Files:**
- Create: `packages/codex/pkg.sh`
- Extraction source: install.sh lines 222–236 (MCP bridge) — becomes the conditional step.

- [ ] **Step 1: Write it.**

```bash
#!/bin/bash
PKG_DESC="OpenAI Codex CLI (GPT agent, ChatGPT-subscription billed) + MCP bridge into Claude Code"
PKG_DEPS=(core)

pkg_install() {
  pkg_brew
  # Bridge is an integration, not a dep: register in Claude iff claude exists.
  if command -v codex &> /dev/null && command -v claude &> /dev/null; then
    if claude mcp get codex &> /dev/null; then
      echo "Codex MCP bridge already registered — skipping."
    else
      echo "Registering Codex as an MCP server in Claude Code..."
      claude mcp add codex -s user -- codex mcp-server \
        || warn "Couldn't register Codex MCP server — run 'claude mcp add codex -s user -- codex mcp-server' by hand."
    fi
  else
    echo "Skipped Claude bridge (claude CLI not present)."
  fi
  echo "  ⚠ MANUAL: sign in with 'codex login' (ChatGPT subscription); verify: codex login status"
}

pkg_verify() {
  local ok=0
  command -v codex &> /dev/null && echo "  PASS codex CLI" || { echo "  FAIL codex CLI"; ok=1; }
  if command -v claude &> /dev/null; then
    claude mcp get codex &> /dev/null && echo "  PASS claude bridge" || { echo "  FAIL claude bridge"; ok=1; }
  fi
  return $ok
}
```

- [ ] **Step 2: Syntax + verify (PASS expected).**
- [ ] **Step 3: Commit** — `git commit -m "feat(install): codex package (bridge conditional on claude)"`

---

### Task 9: packages/muster/pkg.sh — owns ALL muster wiring

**Files:**
- Create: `packages/muster/pkg.sh`
- Extraction sources: install.sh 242–326 (clone/build/LaunchAgent/MCP — change clone URL to `https://github.com/schuettc/muster.git`), 205–221 (Codex hooks.json — moves here), plus NEW additive Claude-hooks merge (jq pattern from Task 6).

**Interfaces:**
- Consumes: `ensure_hook` jq pattern shape from Task 6 (inline copy — jq has no imports).

- [ ] **Step 1: Write it.** `PKG_DESC="muster: cross-terminal agent coordination bus (daemon via LaunchAgent, MCP in Claude/Codex, session hooks)"`, `PKG_DEPS=(terminal)`. `pkg_install()` in order: `pkg_brew` (installs go) → clone-if-missing (HTTPS) → build → LaunchAgent block (verbatim from 258–292) → MCP registrations (conditional per binary, verbatim from 293–298) → NEW: additive Claude session-hooks merge:

```bash
  local settings="$HOME/.claude/settings.json"
  if command -v claude &> /dev/null && command -v jq &> /dev/null; then
    [[ -f "$settings" ]] || echo '{}' > "$settings"
    local tmp; tmp=$(mktemp)
    if jq '
      def ensure_hook(ev; cmd; entry):
        .hooks[ev] = ((.hooks[ev] // [])
          | if ([.[].hooks[]?.command] | index(cmd)) then . else . + [entry] end);
      ensure_hook("Stop"; "~/dotfiles/bin/muster-session-hook.sh Stop claude";
        {"hooks":[{"type":"command","command":"~/dotfiles/bin/muster-session-hook.sh Stop claude"}]})
      | ensure_hook("SessionStart"; "~/dotfiles/bin/muster-session-hook.sh SessionStart claude";
        {"matcher":"startup|resume","hooks":[{"type":"command","command":"~/dotfiles/bin/muster-session-hook.sh SessionStart claude"}]})
    ' "$settings" > "$tmp"; then mv "$tmp" "$settings"
    else rm -f "$tmp"; warn "muster: Claude hooks merge failed — settings.json untouched."; fi
  fi
```

then the Codex hooks.json write (lines 205–221 verbatim, still guarded on codex presence). `pkg_verify()`: muster binary on PATH; `launchctl print gui/$(id -u)/tools.muster.serve` contains `state = running`; socket exists at `~/.local/share/muster/sock`; `claude mcp get muster` (when claude present); Stop hook present in settings.json via jq index check.

- [ ] **Step 2: Syntax + verify (all PASS expected — daemon already running).**
- [ ] **Step 3: Re-run `pkg_install` (idempotency: bootout+bootstrap cycles cleanly, hooks not duplicated)**

Run: `bash packages/run.sh muster && jq '[.hooks.Stop[].hooks[].command]' ~/.claude/settings.json`
Expected: finishes; muster Stop hook appears EXACTLY once; `launchctl` state running again.

- [ ] **Step 4: Commit** — `git commit -m "feat(install): muster package owns clone/daemon/MCP/session hooks (HTTPS clone)"`

---

### Task 10: Rewrite root install.sh; retire root Brewfile; README

**Files:**
- Modify: `install.sh` (full rewrite, ~40 lines)
- Delete: `Brewfile` (`git rm Brewfile`)
- Modify: `README.md` (Structure section; Brewfile references → per-package; muster HTTPS; new "Selective install" subsection pointing at the wizard skill)

- [ ] **Step 1: Rewrite `install.sh`**

```bash
#!/bin/bash
# One-command full install: runs every package in packages/ in dependency
# order. For selective installs, open Claude Code in this repo and run the
# install-wizard skill (or: packages/run.sh <package>…).
# Resilient by design: no set -e; failures warn and continue; summary at end.

source "$(dirname "${BASH_SOURCE[0]}")/packages/lib.sh"
[[ "$(uname)" == "Darwin" ]] || die "This install is macOS-only (found $(uname)). No Linux/Windows support yet."

echo "Installing dotfiles (all packages)..."

if ! command -v brew &> /dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || die "Homebrew install failed (network?). Fix and re-run."
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
fi
command -v brew &> /dev/null || die "brew not on PATH after install — open a new shell and re-run."

for pkg in core terminal nvim markedit claude swiftbar codex muster; do
  run_pkg "$pkg"
done

echo ""
if (( ${#WARNINGS[@]} )); then
  echo "Installation finished with ${#WARNINGS[@]} warning(s):"
  for w in "${WARNINGS[@]}"; do echo "  ⚠ $w"; done
  echo "(Everything else installed — address the above and re-run; install.sh is safe to repeat.)"
else
  echo "Installation complete — no warnings."
fi
echo ""
echo "Next steps:"
echo "  1. Open Ghostty (cmd+space → \"Ghostty\") and run: source ~/.zshrc"
echo "  2. Run \`proj\` and pick a project to spin up your first workspace."
echo "  3. Inside a project, cmd+T spawns more terminals (auto-joins tmux)."
echo "  4. Optional sign-ins: atuin register/login; codex login (ChatGPT plan)."
echo "  5. ⚠ MANUAL: grant SwiftBar Accessibility for click-to-focus (see package output above)."
echo "  6. Read docs/terminal-usage.md for the day-to-day cheat sheet."
```

- [ ] **Step 2: `git rm Brewfile`; update README** (four spots: Structure tree gains `packages/`; "Modern CLI Tools (via Brewfile)" table header → "(via packages/*/Brewfile)"; muster section clone URL → HTTPS + "or pick packages with the install-wizard skill"; new short "Selective install" subsection under Quick Start: *clone → `claude` → "run the install wizard"*).
- [ ] **Step 3: Syntax + full run** — `bash -n install.sh && ./install.sh` on this machine. Expected: completes, ideally "no warnings", every package's verify lines all PASS, zero behavioral diff (machine already installed).
- [ ] **Step 4: Commit** — `git commit -m "feat(install): root installer runs packages/; retire monolithic Brewfile"`

---

### Task 11: .claude/skills/install-wizard/SKILL.md

**Files:**
- Create: `.claude/skills/install-wizard/SKILL.md`

- [ ] **Step 1: Write the skill** (frontmatter + body):

```markdown
---
name: install-wizard
description: Use when someone wants to selectively install components of this dotfiles repo — walks through each package (what it does, what it touches), resolves dependencies, runs chosen package installs, verifies. Triggers on "install wizard", "selective install", "set up these dotfiles", "what would this install".
---

# Dotfiles Install Wizard

Guide the user through a selective install of this repo's packages. The
packages — not this file — are the source of truth: read every
`packages/*/pkg.sh` for `PKG_DESC` and `PKG_DEPS` before saying anything.

## Flow (one question per message, always)

1. **Prereq scan.** Verify macOS (`uname`). Report what's already present:
   brew, go, claude, codex, SwiftBar, an existing ~/.claude/settings.json
   (say clearly: merges are additive — their settings are preserved).
2. **Inventory.** Present the package list with one-line descriptions and
   the dependency graph, then walk packages ONE AT A TIME in canonical
   order (core terminal nvim markedit claude swiftbar codex muster). For
   each: what it is, how it works, and EXACTLY what it touches — casks
   installed, files symlinked into $HOME, settings files merged, and any
   persistence (login items, LaunchAgents) called out explicitly. Codex
   needs a paid ChatGPT subscription — say so. Then ask: install? yes/no.
3. **Dependency closure.** Expand picks with hard deps (PKG_DEPS,
   transitively). Tell the user exactly what was added and why. Show the
   final list and get explicit confirmation before installing anything.
4. **Execute.** Run `bash packages/run.sh <pkg>` one package at a time, in
   canonical order, streaming output. On a failure: report it, ask
   continue-or-stop. Never install anything outside the confirmed set;
   never edit package scripts.
5. **Report.** Per-package verify results (run.sh prints them), then an
   honest summary: installed / skipped / failed / remaining manual steps
   (SwiftBar Accessibility grant, `codex login`, `atuin login`).

## Rules

- One question per message. No compound questions.
- Explain before asking — the user should understand a package before
  deciding. Answer side-questions from the pkg.sh/README content.
- Never run root ./install.sh from this skill (that is the install-all
  path); the wizard only runs packages/run.sh with the confirmed set.
- If a package's verify FAILs, say so plainly — no "mostly worked".
```

- [ ] **Step 2: Validate the skill loads** — in a Claude Code session in this repo, confirm `install-wizard` appears in available skills and its trigger description reads correctly.
- [ ] **Step 3: Commit** — `git commit -m "feat(skills): install-wizard — guided selective dotfiles install"`

---

### Task 12: End-to-end verification

**Files:** none (verification only; fixes loop back into the owning task's files)

- [ ] **Step 1: State snapshot + full-install diff.** Capture before/after around a fresh `./install.sh` run:

```bash
snap() {
  { for l in ~/.zshrc ~/.tmux.conf ~/.config/{zsh,claude,yazi,nvim,atuin,starship.toml}; do printf '%s -> %s\n' "$l" "$(readlink "$l")"; done
    claude mcp list 2>/dev/null | sort
    launchctl print "gui/$(id -u)/tools.muster.serve" 2>/dev/null | grep -E "state ="
    jq -S '.hooks, .statusLine' ~/.claude/settings.json
    brew list --formula | sort; brew list --cask | sort; } > "$1" 2>&1
}
snap /tmp/state-before && ./install.sh && snap /tmp/state-after && diff /tmp/state-before /tmp/state-after
```
Expected: `diff` empty (idempotent, no drift).

- [ ] **Step 2: All-package verify sweep**

```bash
bash -c 'source packages/lib.sh
for p in core terminal nvim markedit claude swiftbar codex muster; do
  PKG_DIR="packages/$p"; unset -f pkg_install pkg_verify; source "packages/$p/pkg.sh"
  echo "== $p"; pkg_verify || echo "== $p FAILED"
done'
```
Expected: every line PASS, no FAILED.

- [ ] **Step 3: Wizard dep-safety spot check** — `bash packages/run.sh swiftbar; echo exit=$?` on a machine where claude verifies clean: expected exit 0 (dep satisfied by installed state). Then confirm the error path: `bash packages/run.sh nonexistent; echo exit=$?` → FATAL + exit 1.
- [ ] **Step 4: Push** — `git push origin main`.
