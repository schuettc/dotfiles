# Terminal Usage — Day-to-Day Guide

How to use the Ghostty + tmux + yazi setup. This is the cheat sheet you reach
for in week 2 when the muscle memory hasn't fully landed.

## The mental model

```
Ghostty window  =  workspace  =  a project, on one branch
                                  ├── Tab 1  (main terminal: shell + yazi)
                                  ├── Tab 2  (another terminal, own claude conversation)
                                  └── Tab 3  (another terminal)
```

* **One workspace per project workspace.** Each Ghostty window is rooted at
  one working tree — either the project's primary clone (your "home base")
  or a per-branch git worktree.
* **The branch decides isolation.** When you enter a project with `proj`, the
  branch you pick determines *where* the workspace is rooted: the default
  branch opens the primary clone (read / coordinate), any other branch opens
  a dedicated git worktree at `<repo>/.worktrees/<branch>` so parallel lines
  of work never collide in one tree. You think in branches; `proj` handles the
  `git worktree` plumbing.
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
| tmux session | What each Ghostty tab is attached to. Sessions are named `<project>`, `<project>-2`, … for the primary clone, and `<project>/<branch>` for a worktree. |
| tmux pane | A split inside a session — like the shell + yazi side-by-side in the main tab. |
| primary clone | The project's original clone — your home base for reading and coordinating, *not* for editing while parallel work is live. |
| worktree | A linked working tree at `<repo>/.worktrees/<branch>`, one per branch, where you actually edit. |

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

   **Screen 2 — pick what to work on (git repos only).** This is where **the
   branch decides isolation.** The rows:

   | Row | What it does |
   |---|---|
   | `● <session>` | Jump to an already-open session for this project. |
   | `🏠 primary clone — on <branch>` | Open the **home base** session in the primary clone, on whatever it has checked out (`main`/`dev`). For reading & coordinating — not for editing while worktrees are live. |
   | `+ new session here` | Spawn *another* session in the primary clone (`<project>-2`, `-3`, …). |
   | `▸ <branch>  (worktree)` | Open the session for a branch that **already has** a worktree. |
   | `▸ <branch>  (branch → new worktree)` | A branch that exists but has no worktree yet — creates the worktree at `<repo>/.worktrees/<branch>`, then opens it. |
   | `+ new branch…` | Prompts for a name, creates the branch off `dev` (falls back to `origin/dev`, else current HEAD), makes its worktree, and opens it. |
   | `+ prune worktrees…` | Interactive cleanup of worktrees you're done with. |

   A non-git project directory skips Screen 2 and just opens a plain home-base
   session (no worktree machinery).

## Worktrees — how the plumbing works

You rarely touch any of this directly — `proj` drives it — but it helps to
know what's on disk:

* **Worktrees live at `<repo>/.worktrees/<branch>`.** Picking any non-default
  branch in Screen 2 creates one there if it doesn't already exist.
* **They're ignored locally via `.git/info/exclude`**, *not* the repo's
  tracked `.gitignore` — so the project's committed ignore rules are never
  touched. `proj` appends `.worktrees/` to `.git/info/exclude` the first time.
* **`.worktreeinclude` seeds each new worktree.** A `<repo>/.worktreeinclude`
  file (gitignore syntax) lists gitignored paths — e.g. `.env` — that should
  be copied into every new worktree so it's immediately runnable. `proj` copies
  them in when it creates the tree.
* **`+ prune worktrees…` never force-removes.** It offers a multi-select list
  of worktrees (never the primary clone), kills each one's session, and removes
  the tree — but a tree with **uncommitted or untracked work is kept** and
  reported, with the exact `git worktree remove --force …` command printed so
  you can force it yourself if you really mean to.

### The `⚠ primary` status-bar marker

When the focused pane is in the **primary clone** *and* one or more linked
worktrees exist, the status bar shows a peach `⚠ primary` badge. That's the
cue: you're about to edit the shared tree while parallel work is live — the
collision trap. Go run `proj` and pick a branch (which puts you in its own
worktree) instead. The badge never appears inside a worktree, and never when
the project has no worktrees at all.

> How it's detected (`bin/tmux-git-status.sh`): a linked worktree's git-dir
> path contains `/worktrees/`; the primary clone's does not. So the script
> flags the pane only when its git-dir is *not* under `/worktrees/` **and**
> `git worktree list` shows more than one tree.

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
  (`06-tmux-autojoin.zsh`) sees you're in a project and creates the next
  available session (`<project>-2`, `<project>-3`, …) with the same
  shell + yazi layout as the main tab. The new tab is **independent** — run
  `claude` (or vim, or anything else) yourself when you want it.

The manual fallback:

* **`pt`** → when ⌘T auto-join didn't fire (e.g., the tab landed at `$HOME`
  instead of the project dir, because tmux didn't forward the cwd via OSC 7).
  From inside the project dir, `pt` auto-detects the name; from elsewhere,
  `pt now-playing` works. It picks the same next-free `<project>-N` slot the
  auto-join would have.

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
side effect: detached sessions accumulate, especially the `-2`/`-3`
sub-sessions.

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
tmux kill-session -t now-playing-3
```

## Which command, when

| Command | Reach for it when… |
|---|---|
| `proj` | You want to **enter or create a workspace** — pick a project, then choose home base (the primary clone) or a branch (its own worktree). Also the way to jump back to any live session. |
| `pt [name]` | You opened a new ⌘T tab and **auto-join didn't fire** — add another terminal to the current project manually. |
| `proj-clean` | `tmux ls` is cluttered — **reap idle** shell/yazi-only sessions (never Claude/editor/server, never the one you're in). |

The opt-ins/opt-outs (`pt --claude`, `proj --claude`, `AUTO_CLAUDE`,
`NO_AUTO_TMUX`, `~/.no-auto-tmux`) are covered under
[Adding terminals to a workspace](#opt-ins--opt-outs).

## Switching projects

Multiple projects (and multiple branches of one project) run simultaneously as
separate tmux sessions. You don't need to close one to use another.

```
proj                                 # picker → switch session, or open a project/branch
prefix → d                           # detach completely
tmux ls                              # list every alive session
tmux kill-session -t now-playing     # tear down a specific session
```

While inside any session, `prefix → s` opens an interactive picker of all
live sessions. Worktree sessions show up as `<project>/<branch>`.

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
