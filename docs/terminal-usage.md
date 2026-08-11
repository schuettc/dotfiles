# Terminal Usage — Day-to-Day Guide

How to use the Ghostty + tmux + yazi setup. This is the cheat sheet you reach
for in week 2 when the muscle memory hasn't fully landed.

## The mental model

```
Ghostty window  =  workspace  =  a project
                                  ├── Tab 1  (main terminal: shell + yazi)
                                  ├── Tab 2  (another terminal, own claude conversation)
                                  └── Tab 3  (another terminal)
```

Sessions are named for their work and live in the primary clone. Coding
agents create their own worktrees when they need isolation — those are
the agent's to manage, and the picker never touches them.

* **One Ghostty window per project.** Each tab attaches to a tmux session
  named for the work it's doing.
* **Multiple independent terminals per workspace.** Each tab in the window
  is its own tmux session with its own state — typically running its own
  Claude conversation.
* **Shared file explorer.** yazi lives in the main tab's right pane,
  toggleable with `prefix → f`.

The vocabulary, in case you read these elsewhere:

| Term | Meaning |
|---|---|
| Ghostty window | Top-level macOS window. One per workspace. |
| Ghostty tab | A tab in the tab bar at the top of the window. One per terminal. |
| tmux session | What each Ghostty tab is attached to. Sessions are named `<project>` (home base) or `<project>/<work>` (named work). |
| tmux pane | A split inside a session — like the shell + yazi side-by-side in the main tab. |
| primary clone | The project's original clone — every session lives here; agents make their own worktrees when they need isolation. |

---

## How to read keypress notation

This doc uses two styles of shortcut:

- **Plain combo** like `Ctrl-A` — press them at the same time. `Ctrl-A` means
  hold the Control key and tap the `A` key.
- **`prefix → KEY`** like `prefix → f` — this is a **two-step** tmux
  shortcut. Press the prefix combo first, **release it**, then press the
  second key. Your prefix is **`Ctrl-A`** (configured in `~/.tmux.conf`).

So `prefix → f` means: press `Ctrl-A`, release both keys, then press `f`.

> tmux docs and most blog posts write this as `prefix f` (no arrow). They
> mean the same thing.

---

## Starting the day

1. Open **Ghostty** (`⌘ Space` → "Ghostty", or pin it to the Dock).
2. If `tmux-continuum` saved sessions from your previous boot, attach:
   ```
   tmux attach
   ```
3. To open a workspace for a project:
   ```
   proj
   ```
   `proj` is a **two-screen picker**:

   **Screen 1 — pick a project (or jump to a live session).** The fzf list
   shows every live tmux session (prefixed `[session]`) plus every project
   directory under your configured roots (`~/.config/proj/roots`; e.g.
   `~/GitHub/schuettc/`, `~/learning-with-court/`), and a
   `[+ add new project root…]` entry. Pick a `[session]` row to jump straight
   back to a running session; pick a project directory to continue to Screen 2.
   `proj <project>` skips straight to Screen 2 (flags come first: `proj
   --claude dotfiles`, not `proj dotfiles --claude`).

   **Screen 2 — pick a session, or name new work.**

   | Row | What it does |
   |---|---|
   | `● <project>/<work>  — <topic>` | Jump to a live session. The suffix is Claude's current subtitle (`@claude_task`). |
   | `🏠 <project> — home base` | Open the home-base session — reading & coordinating. |
   | `+ new work…` | Prompts for a work name (letters digits `-` `_`; spaces become `-`), then creates `<project>/<work>` in the primary clone. |

## Knowing when Claude needs you

When Claude Code is **blocked waiting for your input** (a permission prompt or a
question — its `Notification` hook), the session is flagged for attention and
surfaced three ways at once, **no sound**:

- **🔔 in the title** — the session's Ghostty tab, the ⌘-Tab switcher, and the
  Dock-icon window list all show `🔔 <project>`, so you can see *which* terminal
  is waiting.
- **Menu-bar badge** — a SwiftBar item (top-right) shows a red bell + a count;
  its dropdown lists the waiting sessions.
- **Click to jump** — clicking a session in that dropdown un-minimizes and
  brings its Ghostty window to the front. (One-time setup: SwiftBar must be
  granted Accessibility — see `terminal-setup.md`. Activating Ghostty also raises
  its *other* windows above other apps; that's macOS, not a bug — the target
  lands on top and focused.)

The flag **clears automatically** the moment you switch to / focus that session
(the `pane-focus-in` hook). Turn-end (`Stop`) is intentionally quieter — just the
in-terminal bell, *not* a menu-bar flag — so a dozen parallel sessions don't keep
half the bar lit.

**Trigger it yourself:** `claude-attn raise` flags the current session from any
script, hook, or skill (e.g. ping yourself when a long job finishes). The rest of
the CLI: `claude-attn clear [session]`, `claude-attn list`, `claude-attn focus
<session>` (bring its window forward).

> **Caveats.** Click-to-focus works for sessions that are Ghostty **windows**
> (including minimized). A session living as an **inactive tab** may not raise
> (the window title only reflects its active tab), and a **detached** session has
> no window to bring forward at all — but Claude won't be "waiting" in one you've
> detached.

## Adding terminals to a workspace

First, the window-vs-tab distinction — they behave differently on purpose
(set in `config/ghostty/config`):

* **⌘N (new *window*)** opens fresh at `$HOME`, *outside* any project
  (`window-inherit-working-directory = false`, `working-directory = home`).
  A plain shell at `~`. Run `proj` to enter or create a workspace from there.
* **⌘T (new *tab*) inside a project window** inherits the project's cwd
  (`tab-inherit-working-directory = true`). The zsh auto-join hook
  (`06-tmux-autojoin.zsh`) sees you're in a project and opens `proj
  <project>` — Screen 2 (live sessions · home base · new work) — so naming
  the tab is always an explicit gesture, never an anonymous slot.

The manual fallback:

* **`pt <work>`** → when ⌘T auto-join didn't fire (e.g., the tab landed at
  `$HOME` instead of the project dir, because tmux didn't forward the cwd via
  OSC 7), or when you just want to skip the picker. From inside the project
  dir, `pt <work>` auto-detects the project; from elsewhere,
  `pt <project> <work>` names both. Either creates or attaches
  `<project>/<work>` directly.

Each tab persists across reboots via `tmux-continuum`.

### Opt-ins / opt-outs

```bash
# Auto-launch claude in the left pane instead of leaving it empty:
pt --claude now-playing       # one-shot, for a pt tab
proj --claude                 # one-shot, for the workspace proj creates
AUTO_CLAUDE=1 zsh             # makes ⌘T auto-join also launch claude

# Skip the auto-join entirely for one shell (get a plain prompt):
NO_AUTO_TMUX=1 zsh

# Skip the auto-join globally:
touch ~/.no-auto-tmux
```

Those auto-launch paths run `claude --`, not `claude`. A bare `claude` — no
arguments at all — opens **agent view**, the fleet launcher listing background
agents, whose prompt dispatches a *new* background agent instead of starting a
session for you. Any argument takes the session path; `--` is the smallest one.

That is deliberate, not a workaround to remove: typing `claude` yourself still
gets you the fleet, which is where `--bg` and `/background` sessions live. Only
the auto-launch paths force a session, because "put a working pane here" is
what you asked for. If you type it by hand and want a session, type `claude --`
(or press `←` from inside any session to reach the fleet).

---

## During a session

### What you should see

```
┌──────────────────────────┬──────────────┐
│  shell / claude          │   yazi       │
│  (left, ~70%)            │  (right ~30%)│
└──────────────────────────┴──────────────┘
```

Top of the window: tmux status bar showing the session name and time.

### Common tmux shortcuts — what to actually press

| What you want | Notation | Keys to press |
|---|---|---|
| Toggle the yazi file pane | `prefix → f` | `Ctrl-A`, then `f` |
| Zoom current pane fullscreen | `prefix → z` | `Ctrl-A`, then `z` (zero-style: it toggles) |
| Move focus to the left pane | `prefix → h` | `Ctrl-A`, then `h` |
| Move focus to the right pane | `prefix → l` | `Ctrl-A`, then `l` |
| New window (tab) | `prefix → c` | `Ctrl-A`, then `c` |
| Switch to window 1 | `prefix → 1` | `Ctrl-A`, then `1` |
| Switch to window 2 | `prefix → 2` | `Ctrl-A`, then `2` |
| Rename current window | `prefix → ,` | `Ctrl-A`, then `,` |
| Detach (leave session running) | `prefix → d` | `Ctrl-A`, then `d` |
| Pick another session | `prefix → s` | `Ctrl-A`, then `s` |
| Resize the right pane smaller | `prefix → H` | `Ctrl-A`, then `Shift-H` (repeat) |
| Resize the right pane larger | `prefix → L` | `Ctrl-A`, then `Shift-L` (repeat) |
| Reload tmux config | `prefix → r` | `Ctrl-A`, then `r` |
| Enter copy/scroll mode | `prefix → [` | `Ctrl-A`, then `[`; exit with `q` |

> The bottom row is one literal key after a `Ctrl-A`. You don't hold
> `Ctrl-A` while you press the second key. Press, release, then press.

### Claude Code — multi-line prompts

| What you want | Keys |
|---|---|
| Submit the prompt | `Enter` |
| **Insert a newline without submitting** | `Ctrl+Enter` or `Shift+Enter` |

These are Ghostty keybinds (`config/ghostty/config`) — Ghostty sends a
literal newline instead of the carriage return Claude treats as submit.

### yazi — keys (no prefix needed)

You're *inside* yazi when the right pane shows the file listing. These
keys work directly:

| What you want | Keys |
|---|---|
| Move up / down in the list | `k` / `j` (or arrow keys) |
| Enter a directory | `l` or `Enter` |
| Go up to parent directory | `h` or `Backspace` |
| Open the selected file | `Enter` (opens in nvim, in this pane) |
| **Copy file's absolute path** to clipboard | `c` then `c` |
| Copy parent dir path | `c` then `d` |
| Copy filename only | `c` then `f` |
| Copy filename (no extension) | `c` then `n` |
| Toggle hidden files | `.` |
| Search in current dir | `/` then type; `n` for next match |
| Quit yazi (closes the pane) | `q` |

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

---

## Cleaning up sessions

**Closing a Ghostty tab does NOT kill the tmux session** — it only
detaches. The session keeps running in the background (that's what lets
you reattach and what `tmux-continuum` restores after a reboot). The
side effect: detached sessions accumulate, especially short-lived named
work.

To reap the leftovers:

```bash
proj-clean        # kill every session whose panes are all idle
                  # (just a shell or yazi — no claude, editor, or server)
proj-clean -n     # dry run: show what WOULD be killed, kill nothing
```

It never touches a session running Claude (or vim/node/etc.), and never
the session you're currently attached to. Run it whenever `tmux ls`
gets cluttered. (If you want it automatic, you can add `proj-clean` to
your shell startup — but note it'll reap any idle session you'd
detached on purpose, so most people run it manually.)

To kill one specific session by hand:

```bash
tmux kill-session -t now-playing/notes
```

## Which command, when

| Command | Reach for it when… |
|---|---|
| `proj` | You want to **jump to a live session, open the home base, or name new work** — the two-screen picker. |
| `pt <work>` / `pt <project> <work>` | You opened a new ⌘T tab and **auto-join didn't fire**, or you just want to skip the picker — create-or-attach `<project>/<work>` directly. |
| `proj-clean` | `tmux ls` is cluttered — **reap idle** shell/yazi-only sessions (never Claude/editor/server, never the one you're in). |

The opt-ins/opt-outs (`pt --claude`, `proj --claude`, `AUTO_CLAUDE`,
`NO_AUTO_TMUX`, `~/.no-auto-tmux`) are covered under
[Adding terminals to a workspace](#opt-ins--opt-outs).

## Switching projects

Multiple projects (and multiple pieces of work within one project) run
simultaneously as separate tmux sessions. You don't need to close one to
use another.

```
proj                                 # picker → switch session, or name new work
prefix → d                           # detach completely
tmux ls                              # list every alive session
tmux kill-session -t now-playing     # tear down a specific session
```

While inside any session, `prefix → s` opens an interactive picker of all
live sessions. Named-work sessions show up as `<project>/<work>`.

---

## After a reboot

Open Ghostty:

```
tmux attach
```

`tmux-continuum` should restore every session with `claude` re-launched in
the left pane and `yazi` in the right.

**What is restored:** session names, window/pane layouts, working
directories, the *commands* that were running in each pane.

**What is NOT restored:** the live state inside long-running TUI apps.
Example: a Claude conversation. The `claude` command relaunches, but in a
fresh conversation — you resume the previous one from within Claude as
usual.

---

## Troubleshooting

- **`⌘V` doesn't paste images into Claude.** Use `Ctrl-V` instead. Known
  Ghostty limitation, see `~/.config/ghostty/config` and the inline comment
  there referencing Ghostty discussion #10099.

- **`prefix → f` does nothing.** You're probably not inside a tmux session.
  Run `tmux ls` to check. If empty, run `proj` (or `tmux attach`) first.

- **You typed `prefix f` literally and zsh said "command not found".** The
  word "prefix" is shorthand for `Ctrl-A` — see the notation guide at the
  top of this doc. You press `Ctrl-A` then `f`, not the word "prefix".

- **Right pane is the wrong size after spawning.** `prefix → f` to close
  yazi, then `prefix → f` again to re-spawn — fresh yazi pane spawns at
  30% width. Or resize with `prefix → H` / `prefix → L` repeatedly.

- **Stuck in vim after accidentally opening a file from yazi.** `Esc`
  `Esc` `:q!` `Enter` to bail without saving.

- **tmux not picking up new config changes.** Inside tmux: `prefix → r` to
  reload. If a deeper change (e.g., plugin block edits), kill the server
  entirely: `tmux kill-server` (detach first if attached), then start
  fresh.
