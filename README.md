# dotfiles

Terminal configuration with fast shell startup (~98ms), modular zsh config,
modern CLI tools, and a project-workspace workflow built on **Ghostty + tmux +
yazi** with Claude Code integration.

## Quick Start

This machine is set up declaratively with **[kempt](https://github.com/schuettc/kempt)** —
the config lives in [`kempt.toml`](kempt.toml), and kempt installs, verifies, and
updates everything from it. You read the whole plan before anything runs.

**1. Install kempt (0.13.0 or later), then set up this machine:**
```bash
curl -fsSL https://kempt.tools/install.sh | sh      # install the kempt binary
kempt init https://github.com/schuettc/dotfiles.git  # clone → pick packages → plan → apply
```
`kempt init` walks a picker to choose a profile (`developer` = everything,
`minimal` = just the shell) and package set, shows the full plan, and applies
it on your confirmation. It clones this repo to `~/.config/kempt/repo` unless
you say otherwise; nothing here depends on where the checkout lives.

Family tools (muster, galley, proj, sift, imprint, muda, diazo, hail, and the
home layer's casebook and cull) bring their own hooks, plugins, agent
channels, services and skills: kempt fetches each tool's matching setup with
its binary and shows both in the plan before anything is applied. That needs
the network; `kempt plan` on its own works from what the last apply prepared,
and says so when a tool has not been prepared yet. diazo and hail are gated:
sign the machine in first with `kempt login`, to an account entitled to them.

Personal machines can add the home layer from the checkout:
`kempt layer add home <checkout>/layers/home`.

Already have a selection from an earlier version? It never grows by itself.
Compare it with the `developer` profile and adopt what you want deliberately,
e.g. `kempt adopt diazo`; the install-wizard skill walks through it.

No git? kempt can also `init` straight from a tarball of this repo — the tree is
fetched and extracted, and `kempt update` re-fetches it:
```bash
kempt init https://github.com/schuettc/dotfiles/archive/refs/heads/main.tar.gz
```

**2. Open Ghostty, then:**
```bash
proj               # pick a project → spawns a workspace (shell + yazi)
```

See [`docs/terminal-usage.md`](docs/terminal-usage.md) for the day-to-day
cheat sheet, and [`docs/setup-notes.md`](docs/setup-notes.md) for the full
design rationale behind the migration off cmux.

### Day-to-day

| What you want | Command |
|---|---|
| See what would change (nothing runs) | `kempt plan` |
| Apply the manifest / converge this machine | `kempt apply` |
| Pull latest + self-update + converge | `kempt update` (aliased `dotup`) |
| Prompt-safe status line (used by `proj`) | `kempt status` |
| Add / drop a package from this machine's selection | `kempt adopt <pkg>` / `kempt drop <pkg>` |

Every kempt run is idempotent and shows its plan first. `developer` selects
`core`, `terminal`, `nvim`, `markedit`, `claude`, `swiftbar`, `codex`,
`muster`, `galley`, `sift`, `imprint`, `muda`, `diazo`, `hail`, `pi` (Pi on
the `claude-bridge` provider + published extensions) and `pi-channels`;
`minimal` selects `core`. Two packages are opt-in only: `session-themes`, and
the local llama.cpp inference rig `pi-llama` (it needs GGUF weights this repo
doesn't ship) — add it on a machine that has them with `kempt adopt pi-llama`.

**Follow-ups** only you can do, for what you selected (kempt prints package
notes after `apply`): `kempt login` for diazo and hail; pair your phone with
hail; `codex login`; sign in to Claude Code on first run; `sift init --root
DIR`; SwiftBar's plugin folder, login item and Accessibility grant; with the
home layer, `casebook init` (and, if you want it, `casebook hooks install`)
and `cull init` per project; with `pi-llama`, the model weights. Restart any
running pi session so it picks up new extensions.

## What's Included

### Terminal stack: Ghostty + tmux + yazi

- **[Ghostty](https://ghostty.org)** — native, GPU-accelerated terminal
  emulator. Config in `config/ghostty/config` (MonoLisaCode font, Catppuccin
  Mocha, keybinds, image-paste workaround, Ctrl+Enter newline).
- **tmux**: multiplexer providing splits and detach/reattach (reboot
  recovery is `proj`'s saved tab). Config in `.tmux.conf`.
- **[yazi](https://yazi-rs.github.io)** — TUI file explorer that lives in a
  right-side pane. Config in `config/yazi/`.
- **neovim** ([LazyVim](https://lazyvim.org)) — terminal editor and system-wide
  `$EDITOR`. Config in `config/nvim/` (Catppuccin Mocha; TypeScript, Python,
  and Go language servers via Mason).

### The workspace workflow

One **project workspace = one Ghostty window**. `proj` is a two-screen
picker: Screen 1 picks a project (or jumps to a live session); Screen 2
picks a session — or names new work. **The session name is the identity**:
sessions are born `<project>/<work>` (home base: bare `<project>`), every
surface aligns to that name — Claude included, which is launched with
`--name <session>` — and renames go through one gesture (`prefix T`,
where you type only the work half) so no surface is left behind.
Isolation is the agent's job —
proj opens everything in the primary clone and coding agents make their
own worktrees when they need them.

Shell helpers (in `config/zsh/04-aliases.zsh`; flags come before the
positional project — `proj --claude dotfiles` works, `proj dotfiles
--claude` silently drops the flag):

| Command | What it does |
|---------|--------------|
| `proj` | two-screen picker → jump to a session, open the home base, or name new work |
| `proj <project>` | skip Screen 1 |
| `proj --claude` | same, but auto-launch `claude` in the left pane |
| `proj --cursor` | same, but auto-launch Cursor Agent in the left pane |
| `proj --add` / `--remove` | add or delete an entry in `~/.config/proj/roots` |
| `pt <work>` / `pt <project> <work>` | create-or-attach `<project>/<work>` without the picker |
| `tat <name>` | attach-or-create a named session |
| `proj-clean` | reap idle sessions (shell/yazi only — no Claude/editor/server) |
| `bell-clear` | dismiss the attention banner (`-k` to kill flagged sessions) |

⌘T in a project window auto-joins a new tmux session for that project (via
proj's shell wrapper, fired by `config/zsh/06-proj.zsh`); ⌘N opens a fresh window at `$HOME`, outside
any project. Project roots are configured per-machine in `~/.config/proj/roots`
(not tracked; first `proj` run sets it up). See
[`docs/terminal-usage.md`](docs/terminal-usage.md) for the day-to-day walkthrough.

### Shell Configuration
- **Modular zsh** — configs split into numbered files in `config/zsh/`
- **Lazy-loaded NVM** — Node available immediately, NVM loads on demand
- **Starship prompt** — two-line prompt with git status, language versions, AWS profile

### Pi

The macOS-only `pi` package (part of the `developer` profile) installs Pi on
the `claude-bridge` provider with its published extensions; it needs no local
models. To add it to an existing selection: `kempt adopt pi && kempt apply`.

Local models are the separate, opt-in `pi-llama` package: a launchd-managed
llama.cpp router on the loopback-only port 42137, for a machine that has the
GGUF weights. See [`docs/pi-local-models.md`](docs/pi-local-models.md).

### Modern CLI Tools (the core package)
| Tool | Replaces | Purpose |
|------|----------|---------|
| eza | ls | File listing with icons and git status |
| bat | cat | Syntax-highlighted file viewing |
| ripgrep | grep | Fast search |
| fd | find | Fast file finding |
| zoxide | cd | Smart directory jumping |
| fzf | — | Fuzzy finder |
| delta | diff | Syntax-highlighted git diffs |
| lazygit | — | Git TUI |
| atuin | history | Shell history with sync |

### tmux status bar

The status bar surfaces, for the focused pane:

- **left** — an attention banner (`⚠ N: session1, session2`) listing any
  session whose Claude finished a turn / is waiting for input and that you
  haven't visited yet. Clears when you switch to the session.
- **right** — current git branch + dirty count, the Claude context-window %
  (`⌬ 49%`, green/yellow/red) when the focused pane is running Claude, and
  the date/time.

The branch/context indicators come from the helpers in `bin/`.

### Claude Code Integration

The `claude` package installs [Claude Code](https://claude.ai/code) (the `claude-code` cask) and configures:

- **Status line** (`config/claude/statusline.sh`) — model + working directory.
  (Context % and git status are shown in the **tmux** status bar instead, to
  avoid duplication.)
- **Attention bell** (`config/claude/claude-notify.sh`) — the `Notification`
  and `Stop` hooks ring the tmux bell for the exact Claude pane, which drives
  the status-left attention banner and a 🔔 on the Ghostty tab. Purely
  in-terminal — no macOS notification, no Dock bounce.

### Codex (GPT) bridge

Claude Code stays the primary harness, with [OpenAI Codex](https://github.com/openai/codex)
(`cask "codex"`) wired in two complementary ways so you get GPT for a second
opinion without leaving Claude Code:

- **MCP bridge** — the `codex` package registers Codex as a user-scope MCP server
  (`claude mcp add codex -s user -- codex mcp-server`), so Claude Code can
  delegate a discrete coding task or ask GPT for a second opinion mid-session
  via the `codex` MCP tool. Verify with `claude mcp list` (look for
  `codex … ✔ Connected`).
- **Standalone** — `codex` in its own tab for an independent pass; run both
  agents on the same tricky task and let agreement/divergence guide you.

Both run on a **ChatGPT subscription** (`codex login` — browser OAuth), not a
metered OpenAI API key. Check auth with `codex login status`. See
[`docs/codex-bridge.md`](docs/codex-bridge.md) for the day-to-day workflow.

### Cursor Agent

This repo does not select Cursor. If you use the
[Cursor Agent CLI](https://cursor.com/cli) yourself, `muster setup --force
--agent cursor` wires it onto the muster bus and `proj --cursor` launches it. See
[`docs/cursor-bridge.md`](docs/cursor-bridge.md).

### muster — cross-terminal agent bus

Where the Codex bridge is *vertical* (one terminal), **[muster](https://github.com/schuettc/muster)**
is *horizontal*: a local coordination bus that lets standing agent sessions in
separate terminals (Claude Code, Codex and pi) message and hand tasks to each
other — no copy/paste, subscription-only. The `muster` package installs the
checksummed binary from muster.tools to `~/.local/bin/muster`, and its release
setup adds a **LaunchAgent** (`tools.muster.serve` — `muster serve` runs at
login, restarts on crash, logs to `~/.local/share/muster/serve.log`), the
Claude Code plugin and session hooks, and the Codex hooks and MCP server. This
repo adds the pi side: the MCP server in `~/.config/mcp/mcp.json` and, with
`pi-channels`, the mail channel. Don't want muster? Leave it out of your
selection (the install-wizard skill walks through each package).

- **In an agent session:** the agent calls `register_agent` once, then
  `send_message` / `task_create` / `task_claim` / `get_inbox` / … to coordinate
  with peers. A tmux "wake" knocks the recipient's pane so idle agents notice.
- **From any shell:** `muster agents`, `muster inbox <alias>`, `muster tasks <alias>`,
  `muster send <alias> "…" --from me` to observe and drive the bus.
- **From tmux:** `prefix @` copies the session's bus alias to the clipboard;
  `prefix m` nudges the session's agent to drain its inbox now (idle agents
  otherwise only check mail at turn boundaries).

Verify with `claude mcp list` (`muster … ✔ Connected`). Full docs live in the
muster repo's README.

### The naming contract (tmux ↔ muster)

The tmux session name (`#S`) is the identity (spec:
`docs/superpowers/specs/2026-08-08-proj-session-identity-design.md`). A
session is born named for its work (`<project>/<work>`, via the proj
picker or `pt`), and every surface aligns to that one name: tab titles,
the picker, Claude's own conversation name, and — when muster is
installed — the bus alias, which its SessionStart hook seeds from the
session name.

Claude gets that name at launch, via `claude --name <session>`. Both
launch paths carry it: `proj --claude` / `pt --claude` type it into the
pane (`__claude_launch_cmd`), and a hand-typed bare `claude` picks up
`#S` through the wrapper in `04-aliases.zsh`. Nothing is injected and
nothing waits for the agent to boot. `--name` writes a transcript
custom-title record, which is what `config/claude/statusline.sh` reads to
decide a name is user-set — so the first status tick already sees Claude
and `#S` aligned.

Renames go through one gesture so no surface is left behind. **You type
the work, never the project.** `prefix T` runs
`bin/tmux-session-rename.sh --prompt`, which pre-fills the prompt with
the work segment alone (a home-base session, whose `#S` is a bare
`<project>`, starts empty); the rename half re-attaches the project
prefix to whatever comes back. A typed name that already contains a `/`
is taken verbatim — the escape hatch for re-homing a session under
another project. From there it validates the name (letters, digits, `-`,
`_`, `/`), refuses names any live session holds, renames the tmux
session, and — with muster — calls `muster become`, which claims the
alias on the bus (mail follows via lineage) and types `/rename` into the
registered Claude pane.

`/rename` inside Claude flows the other way: the statusline proves the
name is user-set via the transcript custom-title record, then renames the
tmux session (plus `muster become --no-inject` when available — the name
already came from `/rename`). Note the asymmetry: that path takes the
name literally and does **not** re-attach a project prefix, so
`/rename foo` on `dotfiles/nfl-4` leaves a bare `foo`. Use `prefix T`.
Without muster, both gestures still work, just tmux-only.

`@claude_task` survives as a display-only subtitle — whatever Claude
currently calls the conversation (usually its auto topic), rendered in
the title's middle segment and deduped against the session name. It
never renames anything. `@claude_task_promoted` records the last title
the statusline acted on, so a stale transcript title (a swallowed
`/rename`) can't revert an operator's rename. `@claude_task_manual` is
retired.

## Structure

```
<checkout>/
├── .zshrc                 # Minimal loader, sources config/zsh/*
├── .tmux.conf             # tmux config (prefix C-a, plugins, status bar)
├── kempt.toml             # declarative machine manifest (kempt reads this)
├── bin/
│   ├── tmux-git-status.sh      # branch + dirty count for status-right
│   ├── tmux-claude-context.sh  # Claude context % for status-right
│   ├── tmux-attention.sh       # attention banner for status-left
│   ├── tmux-session-color.sh   # stable name-hashed session color
│   └── claude-attn             # raise/clear the Claude attention flag
├── config/
│   ├── ghostty/config     # Terminal config (fonts, theme, keybinds)
│   ├── yazi/              # File-explorer config (Catppuccin Mocha)
│   ├── nvim/              # neovim config (LazyVim, Catppuccin Mocha)
│   ├── zsh/
│   │   ├── 00-terminal.zsh      # OSC 7 cwd reporting (Ghostty new-tab dir)
│   │   ├── 01-paths.zsh        # PATH + EDITOR (nvim)
│   │   ├── 02-nvm-lazy.zsh     # Lazy NVM loading
│   │   ├── 03-tools.zsh        # Atuin, zoxide, fzf init
│   │   ├── 03-proj-roots.zsh   # project-roots loader (proj/pt)
│   │   ├── 04-aliases.zsh      # aliases + proj/pt/tat/proj-clean/bell-clear
│   │   ├── 05-completions.zsh  # Shell completions
│   │   └── 06-proj.zsh         # ⌘T → fires proj's auto-join once PATH is set
│   ├── starship.toml      # Prompt configuration
│   ├── atuin/config.toml  # History sync settings
│   └── claude/
│       ├── statusline.sh      # Claude Code status line (model + dir)
│       └── claude-notify.sh   # Notification/Stop hooks → tmux bell
└── docs/
    ├── pi-local-models.md # Pi + local llama.cpp models
    ├── terminal-usage.md  # day-to-day cheat sheet
    ├── terminal-setup.md  # install tutorial
    ├── codex-bridge.md    # Claude Code + Codex (GPT) workflow
    ├── cursor-bridge.md   # Cursor Agent + muster workflow
    └── setup-notes.md     # design rationale / running log
```

## Customization

| To change… | Edit |
|------------|------|
| Aliases / workspace commands | `config/zsh/04-aliases.zsh` |
| Project root directories | `proj --add` / `--remove` / `--edit` (writes `~/.config/proj/roots`) |
| The prompt | `config/starship.toml` ([starship.rs/config](https://starship.rs/config/)) |
| Terminal settings / keybinds | `config/ghostty/config` |
| tmux behavior / status bar | `.tmux.conf` |
| Homebrew packages | the package's `install` step in `kempt.toml`, then `kempt apply` |

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- MonoLisa font (paid; not installed by any package) — without it Ghostty falls back to a
  default monospace. Install your `.ttf`s into `~/Library/Fonts/` first. The
  config expects MonoLisa **3.000+**, whose family is `MonoLisaCode` (v2.x
  shipped as `MonoLisa`); on 3.000 the variable `MonoLisaCodeUpright.ttf` covers
  every weight.
