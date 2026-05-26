# Terminal Usage — Day-to-Day Guide

How to use the Ghostty + tmux + yazi setup. This is the cheat sheet you reach
for in week 2 when the muscle memory hasn't fully landed.

## The mental model

```
Ghostty window  =  workspace  =  a project directory
                                  ├── Tab 1  (main terminal: shell + yazi)
                                  ├── Tab 2  (another terminal, own claude conversation)
                                  └── Tab 3  (another terminal)
```

* **One workspace per project.** Each Ghostty window is rooted at one
  project directory.
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
| tmux session | What each Ghostty tab is attached to. Sessions are named `<project>`, `<project>-2`, `<project>-3`, … |
| tmux pane | A split inside a session — like the shell + yazi side-by-side in the main tab. |

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
   The fzf picker shows existing tmux sessions plus every directory under
   `~/GitHub/schuettc/` and `~/learning-with-court/`. Pick one — that
   Ghostty window becomes the workspace for the project.

## Adding terminals to a workspace

Inside a project's Ghostty window:

* **⌘T** → new Ghostty tab. The zsh auto-join hook (`06-tmux-autojoin.zsh`)
  detects you're in a project and creates the next available tmux session
  (`mlb-dk-2`, `mlb-dk-3`, …) with the same shell + yazi layout as the
  main tab. The new tab is **independent** — run `claude` (or vim, or
  anything else) yourself when you want it.

* **`pt`** → manual fallback when auto-join didn't fire (e.g., the tab
  landed at `$HOME` instead of the project dir). From inside the project
  dir, `pt` auto-detects the name. From elsewhere, `pt now-playing`
  works.

Each tab persists across reboots via `tmux-continuum`.

### Opt-ins / opt-outs

```bash
# Auto-launch claude in the left pane instead of leaving it empty:
pt --claude now-playing       # one-shot
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

### yazi — keys (no prefix needed)

You're *inside* yazi when the right pane shows the file listing. These
keys work directly:

| What you want | Keys |
|---|---|
| Move up / down in the list | `k` / `j` (or arrow keys) |
| Enter a directory | `l` or `Enter` |
| Go up to parent directory | `h` or `Backspace` |
| Open the selected file | `Enter` (opens in `$EDITOR`, usually vim) |
| **Copy file's absolute path** to clipboard | `c` then `c` |
| Copy parent dir path | `c` then `d` |
| Copy filename only | `c` then `f` |
| Copy filename (no extension) | `c` then `n` |
| Toggle hidden files | `.` |
| Search in current dir | `/` then type; `n` for next match |
| Quit yazi (closes the pane) | `q` |

### After opening a file from yazi

When you press `Enter` on a file, yazi launches VS Code **without
blocking** — the terminal pane stays fully interactive.

| What happens | What to do |
|---|---|
| VS Code window opens with the file | Keep working in yazi — browse, copy paths, open more files. Each file opens in VS Code (existing window if open, or new). |
| Image / PDF / non-text file | macOS opens it in Preview (or the default app). yazi is unaffected. |

> Under the hood: yazi's `edit` opener is configured to run `code` with
> `orphan = true` — fire-and-forget. The global `$EDITOR` is still
> `code --wait` so git commit (and any other CLI tool that *needs* to
> block on the editor) still works correctly. Best of both.

---

## Switching projects

Multiple projects run simultaneously as separate tmux sessions. You don't
need to close one to use another.

```
proj                            # picker → switch or spawn
prefix → d                      # detach completely
tmux ls                         # list every alive session
tmux kill-session -t mlb-dk     # tear down a specific project
```

While inside any session, `prefix → s` opens an interactive picker of all
live sessions.

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
