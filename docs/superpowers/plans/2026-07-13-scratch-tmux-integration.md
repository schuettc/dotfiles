# scratch ↔ tmux integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every tmux workspace's right column a fixed vertical stack — `scratch` (notes) → `yazi` (files) → shell (terminal) — built by one canonical helper, toggled as a unit by `prefix f`, with `.scratch.md` globally ignored and the `scratch` binary installed by `install.sh`.

**Architecture:** A single builder script (`bin/proj-right-column.sh`) is the one place that defines the column (splits, sizes, `@sidebar` tags, and the per-app terminal-probe focus dance). The three current pane-creation sites (`__proj_launch`, `pt`, the auto-join hook) and a new `prefix f` toggle (`bin/tmux-sidebar-toggle.sh`) all delegate to it. No pane logic is duplicated.

**Tech Stack:** zsh (dotfiles config), bash (`bin/` helper scripts), tmux 3.x (per-project servers via `-L proj-<name>`), the `scratch` Go binary.

## Global Constraints

- Right column is **30% wide**; main pane stays **70%** (reuses the existing `@agent_pin` `>=3` → `{top-left} -x 70%` hooks — do NOT change the pin or the 30% width).
- Column stack top→bottom: **`scratch` (~12 rows, fixed) → `yazi` (fills middle) → plain shell (~10 rows, fixed)**.
- Every column pane is tagged with the pane option **`@sidebar 1`**; `prefix f` identifies the column by that tag, never by pane content.
- Both `scratch` and `yazi` probe the terminal at startup and must be **focused while probing** (tmux routes probe responses to the focused pane) — the builder gives each ~0.5s focused, then returns focus to the main pane, all in a **detached** job so it survives the caller's `exec tmux attach`.
- Per-project tmux servers: all pane commands run on `-L proj-<name>` (`__proj_srv`). The builder accepts a server arg; `-` means "the current server" (used from inside tmux, e.g. `prefix f`).
- `bin/` scripts: `#!/bin/bash`, invoked by full `~/dotfiles/bin/…` path (matches existing convention).
- Canonical binary location: **`~/.local/bin/scratch`** (built by `install.sh`, mirroring the muster block); the earlier `~/go/bin/scratch` duplicate is removed once.
- Global ignore: append `.scratch.md` to `~/.config/git/ignore` (git's XDG default; already holds a manual entry — machine-local, not repo-tracked, consistent with current practice).
- Subagent panes (Claude `--tmux`) may append below the terminal — accepted; no logic to keep the terminal last.

## File Structure

- **Create:** `bin/proj-right-column.sh` — canonical column builder.
- **Create:** `bin/tmux-sidebar-toggle.sh` — `prefix f` toggle.
- **Modify:** `config/zsh/04-aliases.zsh` — add `__proj_right_column` wrapper; convert `__proj_launch` and the `pt` block to call it.
- **Modify:** `config/zsh/06-tmux-autojoin.zsh` — convert the auto-join yazi block to call it.
- **Modify:** `.tmux.conf` — rebind `prefix f` to the toggle script.
- **Modify:** `install.sh` — add a `scratch` build step.
- **Modify (machine-local, not committed):** `~/.config/git/ignore` — add `.scratch.md`.

---

## Task 1: Canonical column builder script

**Files:**
- Create: `bin/proj-right-column.sh`

**Interfaces:**
- Consumes: `tmux`, `scratch`, `yazi` on PATH.
- Produces: `proj-right-column.sh <server|-> <session> <dir>` — forks a detached job that builds the tagged 3-pane column on the given session (whose only pane is the main/left pane) and returns immediately.

- [ ] **Step 1: Write the script**

Create `bin/proj-right-column.sh`:

```bash
#!/bin/bash
# Build the standard right column for a session whose only pane is the main
# (left) pane:  scratch (top, ~12 rows) -> yazi (middle) -> shell (bottom,
# ~10 rows).  Each pane is tagged `@sidebar 1` so tmux-sidebar-toggle.sh
# (prefix f) can toggle the column by tag regardless of what runs in it.
#
# scratch AND yazi both probe the terminal at startup (bg-color / cursor pos);
# tmux delivers the responses to the FOCUSED pane, so each must be focused while
# it probes or the responses leak as escape-code garbage.  The column is built
# in a detached, staggered job: create each probing app focused, give it ~0.5s
# to read its responses, then move on; finally return focus to the main pane.
# Detached so it never blocks the caller's `exec tmux attach`.
#
# Usage: proj-right-column.sh <server|-> <session> <dir>
#   server "-" means "the current server" (used from inside tmux, e.g. prefix f).
set -u
srv="${1:?server}"; name="${2:?session}"; dir="${3:?dir}"
tm() { if [ "$srv" = "-" ]; then tmux "$@"; else tmux -L "$srv" "$@"; fi; }

left=$(tm list-panes -t "$name" -F '#{pane_id}' 2>/dev/null | head -1)
[ -n "$left" ] || exit 0

(
  right=$(tm split-window -h -l 30% -t "$left" -c "$dir" -P -F '#{pane_id}' scratch 2>/dev/null) || exit 0
  tm set-option -p -t "$right" @sidebar 1 2>/dev/null
  sleep 0.5                                   # scratch reads its probe while focused
  mid=$(tm split-window -v -t "$right" -c "$dir" -P -F '#{pane_id}' yazi 2>/dev/null) || exit 0
  tm set-option -p -t "$mid" @sidebar 1 2>/dev/null
  sleep 0.5                                   # yazi reads its probe while focused
  bottom=$(tm split-window -v -l 10 -t "$mid" -c "$dir" -P -F '#{pane_id}' 2>/dev/null) || exit 0
  tm set-option -p -t "$bottom" @sidebar 1 2>/dev/null
  tm resize-pane -t "$right" -y 12 2>/dev/null
  tm select-pane -t "$left" 2>/dev/null
) &
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x ~/dotfiles/bin/proj-right-column.sh`

- [ ] **Step 3: Syntax check**

Run: `bash -n ~/dotfiles/bin/proj-right-column.sh`
Expected: no output (valid).

- [ ] **Step 4: Verify it builds the tagged, correctly-sized column (headless)**

```bash
S=scrtest; D=$(mktemp -d)
tmux -L "$S" new-session -d -s t -x 250 -y 60 -c "$D"
~/dotfiles/bin/proj-right-column.sh "$S" t "$D"
sleep 2
echo "== panes (id height @sidebar cmd) =="
tmux -L "$S" list-panes -t t -F '#{pane_id} h=#{pane_height} sidebar=#{@sidebar} cmd=#{pane_current_command}'
echo "== counts =="
echo "total:   $(tmux -L "$S" list-panes -t t | wc -l | tr -d ' ')  (expect 4)"
echo "sidebar: $(tmux -L "$S" list-panes -t t -F '#{@sidebar}' | grep -c 1)  (expect 3)"
tmux -L "$S" kill-server 2>/dev/null; rm -rf "$D"
```

Expected: total 4, sidebar 3; one pane `sidebar=1 cmd=scratch` with `h≈12`, one `sidebar=1 cmd=yazi` (tall middle), one `sidebar=1` shell with `h≈10`, and the main pane `sidebar=` (unset). (scratch/yazi may sit idle waiting for a terminal in this detached test — only the structure/tags/sizes matter here.)

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add bin/proj-right-column.sh
git commit -m "feat(tmux): canonical right-column builder (scratch/yazi/shell)"
```

---

## Task 2: Wire the three pane-creation sites to the builder

**Files:**
- Modify: `config/zsh/04-aliases.zsh` (add wrapper; edit `__proj_launch`; edit `pt` block)
- Modify: `config/zsh/06-tmux-autojoin.zsh` (edit auto-join block)

**Interfaces:**
- Consumes: `proj-right-column.sh` (Task 1).
- Produces: `__proj_right_column <srv> <session> <dir>` zsh wrapper; all three sites delegate to it.

- [ ] **Step 1: Add the wrapper in `config/zsh/04-aliases.zsh`**

Immediately after the `__proj_srv()` line (currently `__proj_srv() { print -r -- "proj-$1"; }`), add:

```zsh
# Build the standard right column (scratch -> yazi -> shell) for a freshly
# created session. Thin wrapper over the canonical builder so the same logic
# serves proj / pt / auto-join and `prefix f`.
__proj_right_column() { "$HOME/dotfiles/bin/proj-right-column.sh" "$@"; }
```

- [ ] **Step 2: Convert `__proj_launch`**

In `config/zsh/04-aliases.zsh`, replace this block (the pane-id comment through the `fi`):

```zsh
    # Split + select by PANE ID, not "=name": the "=" exact-match prefix is a
    # session target and is NOT valid for split-window/select-pane (they want a
    # pane), and ":0.0" is wrong under base-index 1. Pane ids (%NN) are global
    # and unambiguous, so this works regardless of name (slashes ok) or indexing.
    #
    # yazi ALWAYS probes the terminal at startup (XTVERSION + DA1), even when it
    # already knows the emulator — see yazi-emulator/src/emulator.rs::detect().
    # tmux delivers the terminal's responses (which are input) to whatever pane
    # is FOCUSED. So yazi must stay focused while it probes, or the responses
    # leak into the shell as escape-code garbage (`>|ghostty 1.3.1…;…c`). Split
    # WITHOUT -d so yazi is focused, let it read its own responses, then return
    # focus to the left pane after ~0.5s via a detached job (so we never block
    # the switch-client/attach below, and the timer survives it).
    local left
    left=$(tmux -L "$srv" list-panes -t "$name" -F '#{pane_id}' 2>/dev/null | head -1)
    if [[ -n "$left" ]]; then
      tmux -L "$srv" split-window -h -l 30% -t "$left" -c "$dir" yazi
      ( sleep 0.5; tmux -L "$srv" select-pane -t "$left" 2>/dev/null ) &!
    fi
```

with:

```zsh
    # Build the right column (scratch -> yazi -> shell). The builder handles
    # pane-id targeting, the per-app terminal-probe focus dance, and tags the
    # panes @sidebar. It forks its work, so it never blocks the goto/attach below.
    __proj_right_column "$srv" "$name" "$dir"
```

- [ ] **Step 3: Convert the `pt` block**

In `config/zsh/04-aliases.zsh`, replace:

```zsh
  # Add the yazi pane on the right (30%). yazi always probes the terminal at
  # startup and tmux routes the responses to the focused pane (see __proj_launch
  # for the full explanation), so keep yazi focused while it probes, then return
  # focus to the left pane after ~0.5s via a detached job.
  local left
  left=$(tmux -L "$srv" list-panes -t "$target" -F '#{pane_id}' 2>/dev/null | head -1)
  tmux -L "$srv" split-window -h -l 30% -t "$left" -c "$proj_dir" yazi
  ( sleep 0.5; tmux -L "$srv" select-pane -t "$left" 2>/dev/null ) &!
```

with:

```zsh
  # Build the right column (scratch -> yazi -> shell); see __proj_right_column.
  __proj_right_column "$srv" "$target" "$proj_dir"
```

- [ ] **Step 4: Convert the auto-join block in `config/zsh/06-tmux-autojoin.zsh`**

Replace:

```zsh
  # Add the yazi pane on the right. yazi always probes the terminal at startup
  # and tmux routes the responses to the focused pane (see __proj_launch), so
  # keep yazi focused while it probes, then return focus to the left pane after
  # ~0.5s via a detached job. The subshell is forked before the `exec tmux
  # attach` below, so the timer survives the exec and still fires.
  local left
  left=$(tmux -L "$srv" list-panes -t "$target" -F '#{pane_id}' 2>/dev/null | head -1)
  tmux -L "$srv" split-window -h -l 30% -t "$left" -c "$proj_dir" yazi 2>/dev/null
  ( sleep 0.5; tmux -L "$srv" select-pane -t "$left" 2>/dev/null ) &!
```

with:

```zsh
  # Build the right column (scratch -> yazi -> shell); see __proj_right_column.
  # The builder forks its work before the `exec tmux attach` below, so it
  # survives the exec.
  __proj_right_column "$srv" "$target" "$proj_dir"
```

- [ ] **Step 5: Syntax-check both files**

Run: `zsh -n ~/dotfiles/config/zsh/04-aliases.zsh && zsh -n ~/dotfiles/config/zsh/06-tmux-autojoin.zsh && echo OK`
Expected: `OK`.

- [ ] **Step 6: Verify no inline yazi split remains and all sites delegate**

```bash
cd ~/dotfiles
echo "-- remaining inline 'split-window ... yazi' (expect none) --"
grep -rn "split-window .*yazi" config/zsh/ || echo "none ✓"
echo "-- call sites (expect 3: __proj_launch, pt, auto-join) --"
grep -rn "__proj_right_column " config/zsh/
```

Expected: no inline `split-window … yazi` remains; exactly three `__proj_right_column "…"` call sites (plus the wrapper definition).

- [ ] **Step 7: Verify the wrapper drives the builder (headless, via a login shell)**

```bash
S=wraptest; D=$(mktemp -d)
tmux -L "$S" new-session -d -s t -x 250 -y 60 -c "$D"
zsh -ic '__proj_right_column wraptest t '"$D"' ; sleep 2'
tmux -L "$S" list-panes -t t -F '#{@sidebar}' | grep -c 1   # expect 3
tmux -L "$S" kill-server 2>/dev/null; rm -rf "$D"
```

Expected: `3` (the wrapper resolved and built the tagged column).
Note: full `proj` / `pt` / `⌘T` end-to-end (which `exec tmux attach`) is a manual Ghostty check in Task 6.

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles
git add config/zsh/04-aliases.zsh config/zsh/06-tmux-autojoin.zsh
git commit -m "refactor(tmux): route proj/pt/auto-join through __proj_right_column"
```

---

## Task 3: `prefix f` toggles the whole column

**Files:**
- Create: `bin/tmux-sidebar-toggle.sh`
- Modify: `.tmux.conf`

**Interfaces:**
- Consumes: `proj-right-column.sh` (Task 1); pane `@sidebar` tags (Task 1).
- Produces: `bin/tmux-sidebar-toggle.sh` — kills `@sidebar` panes if any, else rebuilds the column for the current session on the current server.

- [ ] **Step 1: Write the toggle script**

Create `bin/tmux-sidebar-toggle.sh`:

```bash
#!/bin/bash
# prefix f: toggle the right column (panes tagged @sidebar) in the current
# window. If any tagged panes exist, kill them; otherwise rebuild the column
# via the canonical builder. Run from inside tmux (run-shell), so plain `tmux`
# targets the current server; the builder is called with server "-" (current).
set -u
name=$(tmux display-message -p '#{session_name}')
dir=$(tmux display-message -p '#{pane_current_path}')
tagged=$(tmux list-panes -F '#{pane_id} #{@sidebar}' | awk '$2==1 {print $1}')
if [ -n "$tagged" ]; then
  for p in $tagged; do tmux kill-pane -t "$p" 2>/dev/null; done
else
  "$HOME/dotfiles/bin/proj-right-column.sh" - "$name" "$dir"
fi
```

- [ ] **Step 2: Make it executable + syntax check**

Run: `chmod +x ~/dotfiles/bin/tmux-sidebar-toggle.sh && bash -n ~/dotfiles/bin/tmux-sidebar-toggle.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Rebind `prefix f` in `.tmux.conf`**

Replace the current binding:

```tmux
bind f if-shell '[ #{window_panes} -gt 1 ]' \
  'kill-pane -t :.+' \
  "split-window -h -l 30% -c '#{pane_current_path}' yazi"
```

with:

```tmux
# prefix f → toggle the whole right column (scratch + yazi + terminal), which
# the builder tags @sidebar. Kills the tagged panes if present, else rebuilds
# the column. Identifying by tag (not content) keeps agent panes and any tool
# you run in the column from confusing the toggle.
bind f run-shell "~/dotfiles/bin/tmux-sidebar-toggle.sh"
```

- [ ] **Step 4: Verify the config still parses**

```bash
tmux -L conftest -f ~/dotfiles/.tmux.conf new-session -d 2>&1 && echo "PARSED OK"
tmux -L conftest kill-server 2>/dev/null
```

Expected: `PARSED OK` with no parse errors printed. (TPM's `run` line may warn if plugins aren't installed on this socket — that is unrelated to the `bind f` change.)

- [ ] **Step 5: Verify toggle behavior headlessly (via run-shell on a test server)**

```bash
S=togtest; D=$(mktemp -d)
tmux -L "$S" new-session -d -s t -x 250 -y 60 -c "$D"
# build the column first
~/dotfiles/bin/proj-right-column.sh "$S" t "$D"; sleep 2
echo "before toggle sidebar count: $(tmux -L "$S" list-panes -t t -F '#{@sidebar}' | grep -c 1)  (expect 3)"
# toggle OFF (run inside the server so the script's plain tmux targets it)
tmux -L "$S" run-shell "~/dotfiles/bin/tmux-sidebar-toggle.sh"; sleep 1
echo "after teardown total panes: $(tmux -L "$S" list-panes -t t | wc -l | tr -d ' ')  (expect 1)"
# toggle ON (rebuild)
tmux -L "$S" run-shell "~/dotfiles/bin/tmux-sidebar-toggle.sh"; sleep 2
echo "after rebuild sidebar count: $(tmux -L "$S" list-panes -t t -F '#{@sidebar}' | grep -c 1)  (expect 3)"
tmux -L "$S" kill-server 2>/dev/null; rm -rf "$D"
```

Expected: 3 → teardown to 1 pane → rebuild back to 3 tagged panes.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles
git add bin/tmux-sidebar-toggle.sh .tmux.conf
git commit -m "feat(tmux): prefix f toggles the whole @sidebar column"
```

---

## Task 4: Ignore `.scratch.md` globally

**Files:**
- Modify (machine-local, not committed): `~/.config/git/ignore`

**Interfaces:**
- Consumes: nothing.
- Produces: `.scratch.md` matched by `git check-ignore` in any repo.

- [ ] **Step 1: Append the entry idempotently**

```bash
grep -qxF '.scratch.md' ~/.config/git/ignore || printf '.scratch.md\n' >> ~/.config/git/ignore
cat ~/.config/git/ignore
```

Expected: the file now contains a `.scratch.md` line (alongside the existing `**/.claude/settings.local.json`).

- [ ] **Step 2: Verify it is ignored**

```bash
D=$(mktemp -d); git -C "$D" init -q; : > "$D/.scratch.md"
git -C "$D" check-ignore .scratch.md && echo "IGNORED ✓"
rm -rf "$D"
```

Expected: prints `.scratch.md` then `IGNORED ✓`.

- [ ] **Step 3: (no commit)**

`~/.config/git/ignore` is machine-local and untracked (consistent with its existing manual entry). Nothing to commit for this task.

---

## Task 5: Build `scratch` in `install.sh`

**Files:**
- Modify: `install.sh`
- Modify (one-time cleanup): remove `~/go/bin/scratch`

**Interfaces:**
- Consumes: the `scratch` repo at `~/GitHub/schuettc/scratch`, Go.
- Produces: `~/.local/bin/scratch` on a fresh install; a single canonical binary.

- [ ] **Step 1: Add the scratch build block to `install.sh`**

Insert immediately before the `# Claude attention indicator:` comment (i.e. right after the muster block's closing `fi`):

```bash
# scratch: the per-worktree markdown scratchpad TUI (github.com/schuettc/scratch —
# a private Go project). It is the top pane of every tmux workspace's right
# column (see config/zsh/04-aliases.zsh -> __proj_right_column). When the repo is
# cloned and Go is present, build the binary into ~/.local/bin. Idempotent; skips
# cleanly if the repo/tools are absent.
SCRATCH_REPO="$HOME/GitHub/schuettc/scratch"
if [[ -d "$SCRATCH_REPO" ]] && command -v go &> /dev/null; then
  echo "Building scratch (notes pane)..."
  if ! go -C "$SCRATCH_REPO" build -o "$HOME/.local/bin/scratch" . 2>/dev/null; then
    warn "scratch build failed — build it by hand: (cd $SCRATCH_REPO && go build -o ~/.local/bin/scratch .)"
  fi
else
  echo "Skipping scratch (repo not cloned at $SCRATCH_REPO, or Go not installed)."
fi
```

- [ ] **Step 2: Syntax check**

Run: `bash -n ~/dotfiles/install.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Build once + remove the go/bin duplicate + verify canonical binary**

```bash
go -C ~/GitHub/schuettc/scratch build -o ~/.local/bin/scratch . && echo "built ~/.local/bin/scratch"
rm -f ~/go/bin/scratch && echo "removed ~/go/bin/scratch duplicate"
hash -r 2>/dev/null || true
command -v scratch
~/.local/bin/scratch path >/dev/null && echo "binary runs ✓"
```

Expected: `~/.local/bin/scratch` builds and runs; `command -v scratch` resolves to `~/.local/bin/scratch` (no `~/go/bin/scratch` remaining). Note: `~/go/bin` is earlier in PATH, so confirm `command -v scratch` now points at `~/.local/bin/scratch` (the go/bin copy is gone).

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add install.sh
git commit -m "feat(install): build scratch into ~/.local/bin"
```

---

## Task 6: End-to-end verification in a real terminal

**Files:** none (verification only). Requires an interactive Ghostty session — the maintainer runs this; report observations.

- [ ] **Step 1: Reload tmux + zsh**

In a Ghostty shell: `exec zsh` (loads the updated `04-aliases.zsh` / `06-tmux-autojoin.zsh`), and inside any tmux session `prefix r` (reloads `.tmux.conf`).

- [ ] **Step 2: `proj` into a project**

Run `proj <some-project>`. Expected: 4-pane layout — main ~70% left; right ~30% column stacked scratch (top ~12 rows) → yazi (middle) → shell (bottom ~10 rows). **Focus lands on main**, and no escape-code garbage appears in any pane (confirms the probe focus dance).

- [ ] **Step 3: scratch works per-session**

In the scratch pane, type a line, wait ~1s, `Ctrl-Q`; run `cat .scratch.md` in the project dir — the text is saved. In a `proj <same>/<branch>` worktree session, confirm its `.scratch.md` is separate.

- [ ] **Step 4: `pt` and `⌘T` auto-join**

Run `pt <name>` and (separately) open a new Ghostty tab in the project (`⌘T`) to trigger `06-tmux-autojoin.zsh`. Expected: identical column layout via both paths.

- [ ] **Step 5: `prefix f` toggle**

`prefix f` → the whole column disappears (back to just main). `prefix f` again → scratch → yazi → terminal rebuild, focus returns to main.

- [ ] **Step 6: Subagent spawn**

With Claude agent-teams (`--tmux`) in the main pane, spawn a subagent. Expected: the subagent pane appends below the terminal; main stays pinned at ~70%.

- [ ] **Step 7: Report**

Report pass/fail per step. Any failure → treat as a bug and fix before considering the work complete.

---

## Self-Review

**Spec coverage:**
- Layout (30% col; scratch 12 / yazi / terminal 10; agent-pin unchanged) → Task 1 + Global Constraints. ✓
- One canonical helper replacing three sites → Task 1 (builder) + Task 2 (wrapper + three call sites). ✓
- `@sidebar` tagging + `prefix f` whole-column toggle → Task 1 (tags) + Task 3 (toggle + rebind). ✓
- Startup probe focus dance for scratch AND yazi → Task 1 (staggered detached build). ✓
- Per-session scoping (worktree vs numbered) → inherent (builder uses the session dir); verified Task 6 Step 3. ✓
- Global gitignore `.scratch.md` → Task 4. ✓
- Install into `~/.local/bin` + remove go/bin duplicate → Task 5. ✓
- Subagents may append below terminal → verified Task 6 Step 6. ✓

**Placeholder scan:** No TBD/TODO; every script and edit is shown in full; every verification has exact commands and expected output. ✓

**Consistency:** `__proj_right_column` (zsh wrapper) → `proj-right-column.sh <srv|-> <session> <dir>`; `@sidebar 1` set in the builder and read by the toggle and Task-1/3 verifications; `~/.local/bin/scratch` used in Task 5 and matches the Global Constraints; server arg `-`=current used identically by the toggle (Task 3) and builder (Task 1). ✓
