# Neovim Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make neovim (LazyVim) the canonical `$EDITOR` for the terminal stack, replacing VS Code in that role while keeping VS Code installed.

**Architecture:** Vendor the LazyVim starter layout into `config/nvim/` (tracked, symlinked to `~/.config/nvim` by `install.sh`, same pattern as yazi/zsh). LazyVim is pulled in as a plugin by lazy.nvim; language extras (TypeScript, Python, Go) are imported in the lazy.nvim spec; `lazy-lock.json` is committed so a fresh machine reproduces the exact plugin set. Cutover is two lines of zsh (`EDITOR`/`VISUAL`) plus swapping yazi's custom `edit` opener from fire-and-forget `code` to blocking `nvim`.

**Tech Stack:** Homebrew, neovim ≥ 0.10, lazy.nvim + LazyVim, Mason (auto-installs vtsls, pyright, ruff, gopls), zsh, yazi, tmux.

**Spec:** `docs/superpowers/specs/2026-07-08-neovim-adoption-design.md`

## Global Constraints

- macOS / Homebrew (`/opt/homebrew`); repo is `~/dotfiles`, symlinked into `~/.config` by `install.sh`.
- VS Code cask **stays** in the Brewfile (user decision) — only its `$EDITOR` role is removed.
- Colorscheme: Catppuccin **Mocha** (matches Ghostty/tmux/yazi).
- Language extras: exactly `lang.typescript`, `lang.python`, `lang.go`. No other custom plugins/keymaps (YAGNI — stock LazyVim opinions).
- Markdown files keep opening in MarkEdit from yazi (existing prepend rule) — do not change that rule's ordering.
- Commit style: conventional prefix matching repo history (`feat(nvim):`, `docs(readme):`, …). End every commit message with the trailer line `Claude-Session: https://claude.ai/code/session_01S9EmkTdnLam9b9aDbq6qXu`.
- This is a config repo — there is no test suite. Every task's "test" is a concrete verification command with expected output; run it and confirm before committing.
- Do not run the full `./install.sh` (it re-runs brew bundle, atuin import, etc.); run only the specific new commands each task introduces.

---

### Task 1: Brewfile — add neovim, demote VS Code comment

**Files:**
- Modify: `Brewfile:29` (after `brew "yazi"`), `Brewfile:71` (VS Code cask comment)

**Interfaces:**
- Produces: `nvim` binary on PATH at `/opt/homebrew/bin/nvim` (all later tasks assume it exists).

- [ ] **Step 1: Add neovim to the Modern CLI Tools section**

In `Brewfile`, after the line `brew "yazi"               # TUI file manager (right-pane explorer)` add:

```ruby
brew "neovim"             # Editor — $EDITOR, LazyVim config in config/nvim
```

- [ ] **Step 2: Update the VS Code cask comment**

Change line 71 from:

```ruby
cask "visual-studio-code" # Editor ($EDITOR for yazi + git commit)
```

to:

```ruby
cask "visual-studio-code" # GUI editor (kept installed; $EDITOR is nvim)
```

- [ ] **Step 3: Install and verify**

Run: `brew install neovim && nvim --version | head -1`
Expected: a version line like `NVIM v0.11.x` (must be ≥ 0.10). If brew reports "already installed", that's fine.

- [ ] **Step 4: Commit**

```bash
git add Brewfile
git commit -m "feat(brew): add neovim; VS Code no longer \$EDITOR"
```

---

### Task 2: Vendor the LazyVim starter into `config/nvim/` + symlink in install.sh

**Files:**
- Create: `config/nvim/init.lua`
- Create: `config/nvim/lua/config/lazy.lua`
- Create: `config/nvim/lua/config/options.lua`
- Create: `config/nvim/lua/config/keymaps.lua`
- Create: `config/nvim/lua/config/autocmds.lua`
- Create: `config/nvim/lua/plugins/theme.lua`
- Modify: `install.sh:79-82` (add nvim symlink block after the yazi block)

**Interfaces:**
- Consumes: `nvim` binary from Task 1.
- Produces: `~/.config/nvim` symlink → `~/dotfiles/config/nvim`; lazy.nvim spec that Task 3 bootstraps. Extras are imported in `lua/config/lazy.lua` (LazyVim also maintains a `lazyvim.json` it may generate at first run — Task 3 handles committing generated files).

- [ ] **Step 1: Create `config/nvim/init.lua`**

```lua
-- Bootstrap lazy.nvim, LazyVim and plugins (see lua/config/lazy.lua)
require("config.lazy")
```

- [ ] **Step 2: Create `config/nvim/lua/config/lazy.lua`**

```lua
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- LazyVim core and its default plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- Language extras (must come before the plugins import)
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.python" },
    { import = "lazyvim.plugins.extras.lang.go" },
    -- Our overrides in lua/plugins/
    { import = "plugins" },
  },
  defaults = { lazy = false, version = false },
  install = { colorscheme = { "catppuccin", "habamax" } },
  checker = { enabled = true, notify = false }, -- background plugin-update checks, no popup
  performance = {
    rtp = {
      disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" },
    },
  },
})
```

- [ ] **Step 3: Create the three config stubs**

`config/nvim/lua/config/options.lua`:

```lua
-- Options are automatically loaded before lazy.nvim startup.
-- LazyVim defaults: https://www.lazyvim.org/configuration/general
-- Add overrides here only after real usage demands them.
```

`config/nvim/lua/config/keymaps.lua`:

```lua
-- Keymaps are automatically loaded on the VeryLazy event.
-- LazyVim defaults: https://www.lazyvim.org/keymaps
-- Add custom keymaps here only after real usage demands them.
```

`config/nvim/lua/config/autocmds.lua`:

```lua
-- Autocmds are automatically loaded on the VeryLazy event.
-- LazyVim defaults: https://www.lazyvim.org/configuration/general#auto-commands
-- Add custom autocmds here only after real usage demands them.
```

- [ ] **Step 4: Create `config/nvim/lua/plugins/theme.lua`**

```lua
-- Catppuccin Mocha — matches Ghostty, tmux, and yazi.
return {
  { "catppuccin/nvim", name = "catppuccin", opts = { flavour = "mocha" } },
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
}
```

- [ ] **Step 5: Add the symlink block to `install.sh`**

After the yazi block (ends line 82: `ln -sfn "$DOTFILES_DIR/config/yazi" "$CONFIG_DIR/yazi"`), add:

```sh

# neovim config (LazyVim)
echo "Linking neovim config..."
backup_if_exists "$CONFIG_DIR/nvim"
ln -sfn "$DOTFILES_DIR/config/nvim" "$CONFIG_DIR/nvim"
```

- [ ] **Step 6: Create the symlink now (without re-running the whole installer)**

Run: `[[ -e ~/.config/nvim && ! -L ~/.config/nvim ]] && mv ~/.config/nvim ~/.config/nvim.bak; ln -sfn ~/dotfiles/config/nvim ~/.config/nvim && ls -l ~/.config/nvim`
Expected: `~/.config/nvim -> /Users/courtschuett/dotfiles/config/nvim`

- [ ] **Step 7: Sanity-check the config parses (plugins not yet installed)**

Run: `nvim --headless "+lua print('config ok')" +qa 2>&1 | tail -2`
Expected: output contains `config ok` (lazy.nvim will clone itself first — network output before it is fine; no Lua error traceback).

- [ ] **Step 8: Commit**

```bash
git add config/nvim install.sh
git commit -m "feat(nvim): LazyVim starter config (Catppuccin Mocha, TS/Python/Go extras)"
```

---

### Task 3: Bootstrap plugins headlessly, commit the lockfile

**Files:**
- Create (generated): `config/nvim/lazy-lock.json`
- Create (generated, maybe): `config/nvim/lazyvim.json`

**Interfaces:**
- Consumes: config + symlink from Task 2.
- Produces: fully installed plugin set under `~/.local/share/nvim/lazy/`; committed `lazy-lock.json` pinning it.

- [ ] **Step 1: Sync all plugins headlessly**

Run: `nvim --headless "+Lazy! sync" +qa`
Expected: a stream of clone/checkout lines, exit code 0. Takes a minute or two on first run.

- [ ] **Step 2: Verify the lockfile and health**

Run: `ls -l ~/dotfiles/config/nvim/lazy-lock.json && nvim --headless "+checkhealth lazy" "+silent w! /private/tmp/claude-501/-Users-courtschuett-dotfiles/025c449e-1cba-491c-835c-6bf7becc233e/scratchpad/checkhealth.txt" +qa; grep -c "ERROR" /private/tmp/claude-501/-Users-courtschuett-dotfiles/025c449e-1cba-491c-835c-6bf7becc233e/scratchpad/checkhealth.txt || true`
Expected: `lazy-lock.json` exists (non-empty); ERROR count `0` (WARNINGs are acceptable — e.g. optional tools).

- [ ] **Step 3: Trigger Mason tool installs**

LazyVim installs language servers on demand. Force it once, headlessly:

Run: `nvim --headless "+MasonInstall vtsls pyright ruff gopls" +qa 2>&1 | tail -5; ls ~/.local/share/nvim/mason/bin/`
Expected: `mason/bin` listing includes `vtsls`, `pyright-langserver` (or `pyright`), `ruff`, `gopls`. (`MasonInstall` may take a couple of minutes; if a package name is rejected, run `nvim --headless "+Mason" +qa` is NOT useful — instead check the exact registry name with `ls ~/.local/share/nvim/mason/packages/` after opening a TS file in Task 5's verification, and re-run the install with the corrected name.)

- [ ] **Step 4: Commit generated state**

`lazy-lock.json` is intentionally committed (lockfile philosophy). If LazyVim generated `lazyvim.json`, commit that too — it's LazyVim's own extras/news state file.

```bash
git add config/nvim/lazy-lock.json
git add config/nvim/lazyvim.json 2>/dev/null || true
git commit -m "feat(nvim): commit lazy-lock.json (pinned plugin versions)"
```

---

### Task 4: Cutover — `$EDITOR` to nvim, yazi opener to blocking nvim

**Files:**
- Modify: `config/zsh/01-paths.zsh:25-31`
- Modify: `config/yazi/yazi.toml:24-32` (opener comment + `edit` opener), `config/yazi/yazi.toml:45` (rule comment)

**Interfaces:**
- Consumes: working nvim from Task 3.
- Produces: `EDITOR=nvim`, `VISUAL=nvim` in every new shell; yazi `Enter` opens nvim in-pane, blocking.

- [ ] **Step 1: Replace the EDITOR block in `config/zsh/01-paths.zsh`**

Replace lines 25–31:

```sh
# Default editor (used by yazi, git commit, crontab, etc.).
# `--wait` is required so commands that block on the editor (git commit) only
# return after the VS Code window is closed.
if command -v code &> /dev/null; then
  export EDITOR='code --wait'
  export VISUAL='code --wait'
fi
```

with:

```sh
# Default editor (used by yazi, git commit, crontab, etc.).
# nvim runs in the terminal and blocks until you quit, so tools that wait
# on the editor (git commit) need no --wait flag.
export EDITOR='nvim'
export VISUAL='nvim'
```

(Keep the VS Code PATH block above it — the `code` CLI stays available.)

- [ ] **Step 2: Swap yazi's `edit` opener**

In `config/yazi/yazi.toml`, replace the opener comment and `edit` entry (lines 24–32):

```toml
# ─── Openers ─────────────────────────────────────────────────────────
# Override the default `edit` opener so yazi launches VS Code without
# waiting for the window to close. EDITOR='code --wait' remains the
# system default (for git commit, crontab, etc.), but for yazi we want
# fire-and-forget so the pane never freezes.
[opener]
edit = [
  { run = 'code "$@"', desc = "VS Code (no wait)", orphan = true, for = "unix" },
]
```

with:

```toml
# ─── Openers ─────────────────────────────────────────────────────────
# `edit` runs nvim inside the yazi pane and blocks until you quit —
# :q / ZZ drops you straight back into yazi.
[opener]
edit = [
  { run = 'nvim "$@"', desc = "nvim", block = true, for = "unix" },
]
```

- [ ] **Step 3: Update the stale comment in the `[open]` rules**

Change line 45's comment from:

```toml
  # Markdown → MarkEdit by default (Enter); VS Code still available via `O`.
```

to:

```toml
  # Markdown → MarkEdit by default (Enter); nvim still available via `O`.
```

(Do NOT reorder the rules — the `*.md`/`*.markdown` rules must stay ahead of the `text/*` rule.)

- [ ] **Step 4: Verify the new shell environment**

Run: `zsh -ic 'echo "EDITOR=$EDITOR VISUAL=$VISUAL"'`
Expected: `EDITOR=nvim VISUAL=nvim`

- [ ] **Step 5: Verify yazi still parses its config**

Run: `yazi --debug 2>&1 | head -20`
Expected: debug/version info, no TOML parse error mentioning `yazi.toml`.

- [ ] **Step 6: Commit**

```bash
git add config/zsh/01-paths.zsh config/yazi/yazi.toml
git commit -m "feat(editor): cut \$EDITOR and yazi opener over to nvim"
```

---

### Task 5: Documentation updates

**Files:**
- Modify: `README.md` (stack bullets ~line 30, structure diagram lines 124–128)
- Modify: `docs/terminal-usage.md:260,269-282`

**Interfaces:**
- Consumes: final behavior from Task 4 (docs must describe blocking-nvim reality).

- [ ] **Step 1: README — add neovim to the terminal-stack bullets**

In the `### Terminal stack: Ghostty + tmux + yazi` section, after the yazi bullet, add:

```markdown
- **neovim** ([LazyVim](https://lazyvim.org)) — terminal editor and system-wide
  `$EDITOR`. Config in `config/nvim/` (Catppuccin Mocha; TypeScript, Python,
  and Go language servers via Mason).
```

- [ ] **Step 2: README — update the structure diagram**

After the line `│   ├── yazi/              # File-explorer config (Catppuccin Mocha)` add:

```
│   ├── nvim/              # neovim config (LazyVim, Catppuccin Mocha)
```

and change:

```
│   │   ├── 01-paths.zsh        # PATH + EDITOR (code --wait)
```

to:

```
│   │   ├── 01-paths.zsh        # PATH + EDITOR (nvim)
```

- [ ] **Step 3: terminal-usage.md — fix the yazi open-file rows**

Change line 260 from:

```markdown
| Open the selected file | `Enter` (opens in `$EDITOR`, usually vim) |
```

to:

```markdown
| Open the selected file | `Enter` (opens in nvim, in this pane) |
```

Replace the whole `### After opening a file from yazi` section (lines 269–282) with:

```markdown
### After opening a file from yazi

When you press `Enter` on a text file, nvim opens **in the yazi pane** and
takes over until you quit — `:q` (or `ZZ` to save-and-quit) drops you
straight back into yazi.

| What happens | What to do |
|---|---|
| nvim opens with the file | Edit; `Space` shows every LazyVim keybinding. Quit to return to yazi. |
| Markdown file | Opens in MarkEdit (GUI) instead; `O` on the file offers nvim. |
| Image / PDF / non-text file | macOS opens it in Preview (or the default app). yazi is unaffected. |

> Under the hood: yazi's `edit` opener runs `nvim` with `block = true`, and
> the global `$EDITOR` is `nvim` too — one editor everywhere (git commit,
> crontab, `proj --edit`).
```

- [ ] **Step 4: Verify no stale references remain**

Run: `grep -rn "code --wait" README.md docs/terminal-usage.md docs/terminal-setup.md config/ --include="*.md" --include="*.zsh" --include="*.toml"`
Expected: no matches (or only matches inside `docs/setup-notes.md` / spec/plan history docs, which are logs and stay as-is).

- [ ] **Step 5: Commit**

```bash
git add README.md docs/terminal-usage.md
git commit -m "docs: neovim as \$EDITOR — stack, structure, yazi flow"
```

---

### Task 6: End-to-end verification (tmux-driven)

**Files:** none (verification only; scratch files in the session scratchpad)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: LSP attaches to a TypeScript file**

```bash
SCRATCH=/private/tmp/claude-501/-Users-courtschuett-dotfiles/025c449e-1cba-491c-835c-6bf7becc233e/scratchpad
printf 'const n: number = "oops";\n' > "$SCRATCH/sample.ts"
tmux new-session -d -s nvimtest -x 200 -y 50 "nvim $SCRATCH/sample.ts"
sleep 25   # first open compiles treesitter parsers + starts vtsls
tmux capture-pane -t nvimtest -p | grep -i "not assignable"
```

Expected: a diagnostic like `Type 'string' is not assignable to type 'number'` visible in the pane (proves vtsls attached). If not yet visible, wait another 15s and re-capture before concluding failure.

- [ ] **Step 2: Same check for Python**

```bash
tmux send-keys -t nvimtest ":e $SCRATCH/sample.py" Enter
printf 'x: int = "oops"\n' > "$SCRATCH/sample.py"
tmux send-keys -t nvimtest ":e!" Enter
sleep 15
tmux capture-pane -t nvimtest -p | grep -iE "str.*int|incompatible"
```

Expected: a pyright/ruff diagnostic mentioning the str→int mismatch.

- [ ] **Step 3: Quit cleanly**

```bash
tmux send-keys -t nvimtest Escape ":qa!" Enter
sleep 2
tmux kill-session -t nvimtest 2>/dev/null || true
```

- [ ] **Step 4: git commit opens nvim and completes**

Drive it through tmux — git must block on the editor, so a plain backgrounded command can't test this:

```bash
git init -q "$SCRATCH/committest"
tmux new-session -d -s committest -x 200 -y 50 "cd $SCRATCH/committest && zsh -ic 'git commit --allow-empty'"
sleep 8
tmux capture-pane -t committest -p | head -5    # expect the commit-message buffer in nvim
tmux send-keys -t committest "ccnvim editor works" Escape ":wq" Enter
sleep 3
cd "$SCRATCH/committest" && git log --oneline -1
tmux kill-session -t committest 2>/dev/null || true
```

Expected: `git log` shows `nvim editor works` — proving `$EDITOR` blocking behavior end-to-end.

- [ ] **Step 5: Human pass (report to user, don't automate)**

Tell the user to try, in a real workspace: `proj` → yazi → `Enter` on a code file (nvim in-pane, `:q` back to yazi), `Enter` on a `.md` (MarkEdit), and `nvim` then `:Tutor` for the learning ramp. Nothing to commit.

---

## Deviations from spec

- Spec listed `lazyvim.json` as the extras mechanism; the plan imports extras directly in `lua/config/lazy.lua` (deterministic, no generated-file format guessing). If LazyVim generates a `lazyvim.json` at runtime, it gets committed as generated state (Task 3).
- Spec didn't mention `config/yazi/yazi.toml`'s custom `edit` opener (fire-and-forget `code`); Task 4 converts it to blocking `nvim` — required for the cutover to actually reach yazi.
