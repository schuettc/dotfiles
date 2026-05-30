# Terminal Workflow — Working Notes

Live capture of the migration off cmux onto Ghostty + tmux + yazi. Entries
are appended as each task runs. These notes get distilled into
`terminal-setup.md` (install tutorial) and the Part 2 blog draft when the
work is verified.

> Status: **in progress** — system under construction. See `terminal-setup.md`
> for the polished version once it exists.

> ⚠️ **This is a chronological journal, not a spec.** Later entries supersede
> earlier ones. Notably: the early "Claude integration" entry describes a
> macOS notification (osascript) + Dock bounce — both were **removed** later
> (see "Drop macOS notification + Dock bounce"). The shipped behavior is a
> tmux bell only, targeted at the exact pane via process-ancestry walk. For
> the current truth, read `README.md` / `terminal-usage.md`, not this log.

---

## Stack at a glance

| Layer | Choice | Why |
|---|---|---|
| Terminal | **Ghostty** | Native, no Electron, GPU-accelerated. Doesn't leak CALayers the way cmux did. |
| Multiplexer | **tmux** + plugins | Session persistence, splits, detach/reattach, cross-machine portability |
| File explorer | **yazi** | Three-column TUI in a right-side pane; closest match to cmux's file panel |
| Session model | One tmux session per project | Spawned on demand by a `proj` fzf picker |
| Persistence | `tmux-resurrect` + `tmux-continuum` | Auto-save every 15 min, auto-restore on tmux start |

## The cmux postmortem (background)

`sample` on WindowServer (PID 606) for 3s revealed it was spending 100% of
its CPU walking `CA::Render::Updater::prepare_layer0` /
`prepare_sublayer0` recursively, dozens of levels deep. WindowServer's
resident footprint was 1.2 GB (peak 3 GB) after 11 days of uptime — a
classic CALayer leak. cmux is a SwiftUI app wrapping Ghostty for rendering;
its session management layer accumulated layers over time. After a reboot
without cmux, WindowServer dropped to ~900 MB and the stack split between
real CPU layer prep and `CompositorMetal::composite` (actual GPU work) —
healthy.

## Implementation log

### Task #4 — Install yazi + TPM ✓ 2026-05-22

```bash
brew install yazi
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Versions on this machine:

- yazi 26.5.6 (homebrew bottle, ~20 MB, ARM64 macOS 26)
- TPM cloned to `~/.tmux/plugins/tpm`

Homebrew installed zsh completions to
`/opt/homebrew/share/zsh/site-functions` — already on the user's fpath via
the modular zsh config from Part 1, so no action needed.

No surprises. yazi has optional integrations (ffmpeg, 7zz, jq, fd, rg,
imagemagick) — fd/rg already installed; the rest can be added later if
preview functionality is wanted. Skipping for now to keep the install
minimal.

### Task #5 — Extend ~/.tmux.conf with plugins + file-pane toggle ✓ 2026-05-22

Added two blocks to the end of `~/.tmux.conf`:

1. **`prefix T` file-pane toggle** — opens a yazi pane on the right (30% width,
   cwd inherited) if only one pane is visible; closes the *other* pane if two
   are visible. Uses `if-shell` to branch on `#{window_panes}`.
2. **TPM plugin block** — declares tmux-sensible, tmux-resurrect, and
   tmux-continuum. Resurrect captures pane contents and is told to restore
   `claude`, `vim`, `nvim`, `ssh`, `~yazi`. Continuum auto-saves every 15 min
   and auto-restores on tmux server start. `run '~/.tmux/plugins/tpm/tpm'` is
   the final line of the file.

Bootstrap to install the plugins:

```bash
tmux kill-server 2>/dev/null   # kill any stale server with old config
tmux new-session -d -s _bootstrap
~/.tmux/plugins/tpm/bin/install_plugins
tmux kill-server
```

**Gotcha (worth automating in install.sh):** `install_plugins` reads
`TMUX_PLUGIN_MANAGER_PATH` from the running tmux server's global env. If a
tmux server is already running with an *older* config (no TPM block), the
var won't be set and install_plugins exits with
`FATAL: Tmux Plugin Manager not configured in tmux.conf`. The fix is to
kill the old server, start a fresh one (which loads the current config and
sets the env var), then install. **install.sh should explicitly
`tmux kill-server` before bootstrapping plugins.**

### Task #6 — Add `proj()` function to zsh aliases ✓ 2026-05-22

Added two functions to `~/dotfiles/config/zsh/04-aliases.zsh` (which is
already symlinked from `~/.config/zsh/`):

- **`proj`** — fzf picker. Lists active tmux sessions (prefixed `[session]`)
  plus every direct subdirectory of `~/GitHub/schuettc/` and
  `~/learning-with-court/`. Selecting a session attaches/switches; selecting
  a directory spawns a new session named after the directory, with the
  shell+yazi layout, then attaches.
- **`tat`** — quick attach-or-create. `tat foo` attaches to session `foo`,
  creating it if missing. Defaults to the current directory's basename when
  called with no args.

Both work in and out of an existing tmux session (`tmux switch-client` vs
`tmux attach` based on `$TMUX`).

Dependencies: `fzf` and `fd` — both already present from Part 1.

Validation:

```bash
zsh -n ~/dotfiles/config/zsh/04-aliases.zsh   # syntax OK
zsh -c 'source ~/.config/zsh/04-aliases.zsh; type proj tat'
# → proj/tat registered as shell functions
```

No surprises.

### Task #7 — yazi config with Catppuccin theme ✓ 2026-05-22

Files created under `~/.config/yazi/`:

```
~/.config/yazi/
├── flavors/
│   └── catppuccin-mocha.yazi/   ← official yazi-rs/flavors package, vendored
├── theme.toml                    ← points at the flavor for both dark/light
├── yazi.toml                     ← layout (column ratios), sort, preview
└── keymap.toml                   ← prepend `q` quit + `.` toggle hidden
```

Flavor source:
<https://github.com/yazi-rs/flavors/tree/main/catppuccin-mocha.yazi>.
Cloned the repo, copied just the mocha directory in. install.sh will
need to do the same on fresh machines.

Column ratio `[1, 3, 4]` gives the 3-column look (parent : current : preview)
that visually matches cmux's sidebar pattern.

**Gotcha:** yazi 26.x's `[open]` rules require `url` or `mime` fields — not
`name` as some older docs show. Removed the custom `[open]` section
entirely; yazi's built-in defaults handle text/dir/file open routing fine.
Worth noting in the published guide if anyone copies from older yazi blog
posts.

Validation: `yazi --version` parses configs cleanly (no TOML errors).
End-to-end visual verification happens in task #8.

### Claude Code integrations (added 2026-05-22)

We added three integrations between Claude Code and the Ghostty + tmux
stack. Lives at hooks-level (no patching Claude itself).

#### Discovery: cmux-notify.sh was a no-op

The pre-existing `Notification` hook pointed at
`~/.config/claude/cmux-notify.sh`, which early-exits unless
`$CMUX_SOCKET_PATH` is set. Once cmux was removed, every Claude
notification went silently to that script and was dropped on the floor.
**Notifications had not worked outside cmux for as long as the user had
been on this setup.** Replaced wholesale.

#### Component 1 — `claude-notify.sh` dispatcher

A single bash script at `~/.config/claude/claude-notify.sh` handles four
hooks (selected via stdin JSON `.hook_name`):

| Hook | Behavior |
|---|---|
| `Notification` | macOS notification (osascript) + tmux pane bell |
| `Stop`         | tmux pane bell only (quiet — no popup per turn) |
| `SessionStart` | sets the tmux pane title to `claude` (for visibility) |
| `SessionEnd`   | clears the pane title |

tmux pane bell mechanism: write `\a` (BEL) to `#{pane_tty}` of the
current `$TMUX_PANE`. tmux's `monitor-bell` setting (now on by default
in `~/.tmux.conf`) turns the bell into a visual indicator on the window
in the status bar.

macOS notifications use `osascript -e 'display notification "..." with
title "..." sound name "Funk"'` — built-in, no external deps.

`~/.claude/settings.json` was updated to wire all four hooks to the new
script. The previous file is backed up at
`~/.claude/settings.json.bak.2026-05-22`. The old script was archived as
`cmux-notify.sh.bak`.

#### Component 2 — tmux awareness

`~/.tmux.conf` was updated:

- `setw -g monitor-bell on` + `setw -g monitor-activity on` — the
  indicators that make bell/activity visible in the status bar
- `set -g visual-bell off` / `set -g visual-activity off` — no audible
  beep; the colored window indicator is enough
- `set -g bell-action other` — ring the bell from any non-focused pane
- `window-status-bell-style` (peach `#fab387`) and
  `window-status-activity-style` (teal `#94e2d5`) — distinct colors so
  you can tell "urgent" from "turn ended" at a glance
- `status-right` now includes a count of panes with title `claude`:

  ```
  󰚩 claude:#(tmux list-panes -aF '##{pane_title}' | grep -c '^claude$')
  ```

  `status-interval 5` refreshes it every 5 seconds.

The `##{}` (double-hash) escape is required because tmux's status-right
format processor would otherwise consume `#{pane_title}` before passing
the command to the shell. With `##`, the shell receives the literal
`#{pane_title}` that `list-panes -F` expects.

#### Component 3 — `proj` auto-spawns Claude

The `proj()` function in `04-aliases.zsh` now launches `claude` in the
left pane when *creating* a new session (existing sessions are
unchanged on attach). The yazi pane spawns on the right as before.

Opt-out: `proj --bare` skips Claude (empty shell). Useful for projects
where you want to poke around manually first.

Working dir is set to the project root before launching `claude`, so
the project's `CLAUDE.md` is auto-loaded by Claude Code.

#### Surprise: Claude (and yazi) self-set their pane titles via OSC 2

After wiring SessionStart to set pane title to `claude`, the status-bar
counter stubbornly stayed at 0. `tmux list-panes -aF '#{pane_title}'`
revealed why:

```
slay-the-spire:1.1  title=[✳ Claude Code]
slay-the-spire:1.2  title=[Yazi: slay-the-spire]
mlb-dk:1.1          title=[Courts-MacBook-Pro-2.local]
mlb-dk:1.2          title=[Yazi: mlb-dk]
```

Both Claude Code and yazi emit OSC 2 escapes (`\e]2;...\007`) on every
render, overwriting whatever the SessionStart hook set. We lose the
race every time.

**The right move:** stop fighting it. Both tools already self-identify
correctly. Update the status-bar regex to match what Claude actually
emits — `grep -cF 'Claude Code'` instead of `^claude$` — and drop the
SessionStart/SessionEnd hooks from `settings.json` entirely. The
claude-notify dispatcher now keeps SessionStart/SessionEnd as no-ops
just in case we ever want to add per-session logging.

Worth calling out in the blog post: when integrating with TUI apps,
*check what they already announce about themselves before designing
your own announcement mechanism.*

#### What the user needs to do to pick up the changes

1. **tmux config**: inside any tmux session, `prefix → r` to reload, OR
   `tmux kill-server` then `tmux attach` to force a fresh server.
2. **Claude hooks**: Claude Code loads hooks at session start. Quit the
   current Claude session and start a new one; from then on, all four
   hooks fire to `claude-notify.sh`. The next time Claude finishes a
   turn, your tmux window indicator should light up.
3. **`proj` change**: `exec zsh` to reload the function (or open a new
   shell). Next `proj` into a new project will auto-launch Claude.

### Workspace model (added 2026-05-22, after the cmux reveal)

The user's mental model from cmux: a **workspace** is a project (one
directory). Each workspace contains one or more **terminals**, each
typically running its own Claude conversation.

Mapped to our stack:

| cmux                           | Our stack |
|--------------------------------|---|
| Workspace                      | **Ghostty window** rooted at a project directory |
| Terminal in a workspace        | **Ghostty tab** in that window, each attached to its **own tmux session** named `<project>` / `<project>-2` / `<project>-3` |
| File explorer per workspace    | yazi pane in the main tab (toggle with `prefix → f`) |
| Sidebar of all workspaces      | `proj` fzf picker + macOS App Exposé (⌃↓) — no always-visible sidebar in Ghostty |

The `proj` function creates the **main session** (`<project>`) for a
workspace, with the shell+yazi layout. Subsequent terminals are added
by just pressing **⌘T** — a zsh auto-join hook (`06-tmux-autojoin.zsh`)
detects the project, finds the next free `<project>-N` slot, creates
the session, and attaches.

Per-tab independence is the whole point: each tmux session has its own
Claude conversation, its own scroll buffer, its own state. They share
nothing except the project directory and any files on disk.

#### Implementation: `06-tmux-autojoin.zsh`

A new modular zsh file, loaded last (alphabetically). On startup it:

1. Returns immediately if non-interactive, if `$TMUX` is set, if
   `$NO_AUTO_TMUX` is set, or if `~/.no-auto-tmux` exists.
2. Walks the configured project roots (`~/GitHub/schuettc/`,
   `~/learning-with-court/`) to see if `$PWD` is inside one and extracts
   the project name.
3. Returns if the *main* project session (no suffix) doesn't exist —
   spawning a workspace is `proj`'s job, not the hook's.
4. Tries `tmux new-session -d -s <project>-N` for N starting at 2,
   incrementing on collision (race-safe — `new-session -d` errors
   atomically if the name exists).
5. Replaces the current shell with `tmux attach -t <new-session>` via
   `exec`, so detach (`prefix d`) closes the Ghostty tab cleanly rather
   than dropping back to a stranded shell.

#### Implementation: `allow-passthrough on` in tmux.conf

Required by the auto-join workflow. When you're attached to a tmux
session inside a Ghostty tab and press ⌘T, Ghostty needs to know the
*inner* shell's cwd (the project directory). The inner shell reports
its cwd via OSC 7 (already wired in `00-terminal.zsh`); tmux receives
it but won't forward it to the outer terminal unless
`allow-passthrough on` is set. Without this, ⌘T inherits the cwd from
before `tmux attach`, the auto-join hook doesn't recognize a project,
and you get a plain shell instead of a new workspace tab.

Trade-off: `allow-passthrough on` lets DCS/OSC sequences from any
process pass through tmux, which is a small attack surface if you cat
untrusted binary files. Acceptable for a single-user dev machine.

#### Workflow

```text
# First time opening the workspace
⌘N (or ⌘T in an empty Ghostty window)
proj         → fzf picker → pick "mlb-dk"
             → spawns tmux session "mlb-dk" with shell+yazi layout
             → current shell becomes the tmux client for the main tab

# Adding a terminal to the active workspace
⌘T           → new Ghostty tab inherits project cwd
             → auto-join hook creates tmux session "mlb-dk-2"
             → current shell becomes the tmux client for that tab
             → run `claude` for an independent conversation
⌘T           → spawns "mlb-dk-3"; etc.

# Switching workspaces
⌘`           → cycle Ghostty windows
⌃↓           → macOS App Exposé (all Ghostty windows visible)
proj         → fzf to jump to any project/workspace

# Closing a tab
prefix → d   → detach; tmux session keeps running (continuum saves it)
exit         → kills the shell; Ghostty tab closes; tmux session keeps
               running (since we `exec`'d into tmux, not the other way)
tmux kill-session -t mlb-dk-3  → fully kill a tab's session
```

### Task #9 — Move configs into dotfiles + update install.sh + Brewfile ✓ 2026-05-24

When we audited what we'd been editing, three files were still floating in `$HOME`:

- `~/.tmux.conf` — never made it into the repo
- `~/.config/ghostty/config` — dotfiles copy was stale (old font, wrong theme name, no keybinds)
- `~/.config/yazi/` — new from this session, only existed live

**Migration:** copied live versions into `~/dotfiles/.tmux.conf`,
`~/dotfiles/config/ghostty/config`, and `~/dotfiles/config/yazi/`,
backed up the originals as `.bak.preimport`, and replaced the live
paths with symlinks. After migration, every config file we touched
resolves through dotfiles:

```
~/.tmux.conf            → ~/dotfiles/.tmux.conf
~/.config/ghostty/config → ~/dotfiles/config/ghostty/config
~/.config/yazi/         → ~/dotfiles/config/yazi
~/.config/claude/       → ~/dotfiles/config/claude     (already linked, dir-level)
~/.config/zsh/          → ~/dotfiles/config/zsh        (already linked, dir-level)
```

**install.sh updates** (for a fresh-machine bootstrap):

- Added symlinks for `.tmux.conf` and `config/yazi`
- Added TPM clone + headless plugin install (`tmux kill-server` →
  fresh server → `install_plugins`) — the gotcha captured in Task #5
- Removed cmux CLI symlink block (defunct)
- Removed the runtime MonoLisa font-patching block — the ghostty
  config now ships with MonoLisa baked in, since live is the source
  of truth
- Rewrote the Claude `settings.json` merge to register
  `claude-notify.sh` for both `Notification` and `Stop` hooks
- Updated the post-install "next steps" message to point at `proj`
  and `docs/terminal-usage.md`

**Brewfile updates:**

- Added `brew "tmux"`, `brew "yazi"`, and `cask "ghostty"`
- Removed `tap "manaflow-ai/cmux"` and `cask "cmux"`

After all changes, `git status` in dotfiles shows:

```
 M Brewfile
 D config/claude/cmux-notify.sh
 M config/claude/statusline.sh
 M config/ghostty/config
 M config/zsh/01-paths.zsh
 M config/zsh/04-aliases.zsh
 M install.sh
?? .tmux.conf
?? config/claude/claude-notify.sh
?? config/claude/cmux-notify.sh.bak
?? config/yazi/
?? config/zsh/06-tmux-autojoin.zsh
?? docs/
```

Ready to commit.

### Ghostty windows all titled "proj" instead of the project name (fixed 2026-05-24)

Symptom: in the macOS App Switcher / Ghostty hold-icon menu, every
Ghostty window that had been spawned via `proj` showed up as just
"proj" — indistinguishable. Because tmux's `set-titles` was off,
Ghostty fell back to the last command name run in the pane ("proj"),
which never updated once tmux took over the shell.

Fix: two lines in `.tmux.conf`:

```tmux
set -g set-titles on
set -g set-titles-string '#S'
```

This makes tmux emit OSC 0 / OSC 2 with the current session name on
every pane focus change. Ghostty consumes those escapes and uses them
for tab title, window title, and the app-switcher list. Since our
sessions are named after projects (`mlb-dk`, `mlb-dk-2`, etc.),
windows now identify themselves correctly.

### Status-right: claude counter → git branch + dirty indicator (2026-05-24)

The `claude:N` counter was marginal — most of the time the user knows
how many Claude sessions are alive from the App Switcher. Replaced
with git branch + dirty file count for the focused pane, which is
information actually consulted multiple times an hour.

Implementation: `~/dotfiles/bin/tmux-git-status.sh` — small bash
helper that runs inside `#(...)` in `status-right`. Walks the current
path, checks `git rev-parse --is-inside-work-tree`, prints the branch
(or short SHA if detached), and a `●N` count if `git status
--porcelain` returns any lines. Colors via embedded `#[fg=...]`
directives (Catppuccin: green when clean, yellow+peach when dirty).
Outputs nothing for non-git directories so the clock floats by itself.

Performance: a single `git status --porcelain` runs every 5 s
(`status-interval 5`). On the repos in `~/GitHub/schuettc` this is
sub-10ms. If a huge repo ever shows lag we can add a 30-s mtime cache.

Side benefit: the bug in the old counter (`grep -cF 'Claude Code'`
missing all live Claude conversations because Claude updates pane
titles to show the current task) became obvious during this refactor.
The `^✳ ` regex would have fixed it, but the whole feature is now
gone.

### Task #8 — End-to-end verification

_(filled in as we run it)_

### Task #9 — Move configs into ~/dotfiles + update install.sh + Brewfile

_(filled in as we run it)_

## Surprises / decisions made along the way

### tmux `split-window -p N` is unreliable in tmux 3.6

The classic form `split-window -h -p 30` is documented as "new pane is 30%
of the parent." In practice on tmux 3.6 the result was closer to ~50/50.
The fix is to use the explicit-length form: `split-window -h -l 30%`. Both
the `prefix T` keybind and the `proj` function now use `-l 30%`. Worth
calling out in the blog post since older guides still show `-p`.

### yazi ratio `[1, 3, 4]` is wrong for a project session

Default ratio shows three columns: parent, current, preview. With a
project root like `~/GitHub/schuettc/mlb-dk`, the parent column lists ~96
sibling repos that you never navigate to from inside a project. Changed
to `[0, 4, 3]` (parent hidden) so the project's own files dominate the
pane and the preview column remains useful. Yazi's `h` / `Backspace`
still works to navigate up if needed; we just don't waste pixels on the
parent by default.

### `EDITOR=code --wait` for VS Code as the system editor

Stock vim is what tools default to when `$EDITOR` is unset. yazi's
`[opener]` calls `$EDITOR`, so pressing Enter on a file in yazi opened
vim — not what we wanted. Set `EDITOR='code --wait'` and `VISUAL='code
--wait'` in `01-paths.zsh` (right after VS Code is added to PATH). The
`--wait` flag is critical: without it, git commit (and any tool that
expects a blocking editor) would return immediately and use an empty
commit message. With `--wait`, VS Code opens, the calling tool blocks
until the window closes, and the saved file is used.

Side effect: this changes the editor for *all* CLI tools that read
`$EDITOR` (git, crontab, etc.) — intentional, for consistency.

### `--wait` on yazi-launched VS Code freezes the yazi pane

With `EDITOR='code --wait'` and yazi calling `$EDITOR` via its default
`edit` opener (which has `block = true`), the yazi pane stayed frozen
while the VS Code window was open. Killed two birds:

- yazi's `edit` opener was explicitly overridden in `~/.config/yazi/yazi.toml`
  to run `code` (no `--wait`) with `orphan = true`. yazi launches the
  editor fire-and-forget and stays interactive.
- The global `EDITOR='code --wait'` was kept — git commit, crontab, etc.
  still get a properly blocking editor.

We also added `[open] prepend_rules` mapping common text/code MIME types
(text/*, JSON, JS, TS, YAML, TOML, XML) to the `edit` opener, so
pressing Enter on, say, a `.toml` file actually triggers `edit`. Without
those rules, yazi may default to "reveal in Finder" for files it doesn't
recognize as text.
