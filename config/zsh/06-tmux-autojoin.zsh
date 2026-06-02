# Workspace auto-join: when a new shell starts inside a project directory
# and we're not already in tmux, automatically attach to the next free
# <project>-N tmux session. Together with Ghostty's window-inherit-working-
# directory = true, this means ⌘T inside a project's Ghostty window just
# works — each new tab is its own tmux session with its own claude.
#
# Behavior:
#   * Skips if already inside tmux ($TMUX is set).
#   * Skips if NO_AUTO_TMUX is set (escape hatch for one-off shells).
#   * Skips if the cwd is not under one of the configured project roots.
#   * Skips if the *main* project session doesn't exist yet — we don't
#     create the workspace from a stray shell; `proj` is the entry point
#     for spawning a new workspace (and creating its yazi pane).
#   * Otherwise: finds the next free <project>-N slot (N starts at 2) and
#     creates the session attached to the current shell. `tmux new-session
#     -d -s name` errors if the name exists, so we loop until we find a
#     free slot (race-safe).
#
# To disable for a single shell:    NO_AUTO_TMUX=1 zsh
# To disable globally:               touch ~/.no-auto-tmux

__auto_join_project() {
  # Only act on interactive shells.
  [[ $- != *i* ]] && return 0

  # Already inside tmux — nothing to do.
  [[ -n "${TMUX:-}" ]] && return 0

  # Explicit opt-outs.
  [[ -n "${NO_AUTO_TMUX:-}" ]] && return 0
  [[ -f "$HOME/.no-auto-tmux" ]] && return 0

  # Need tmux.
  command -v tmux >/dev/null 2>&1 || return 0

  # Project roots from ~/.config/proj/roots (shared with proj()).
  # Silent no-op if unconfigured — first-run setup happens via `proj`.
  __proj_load_roots || return 0
  local roots=("${PROJ_ROOTS[@]}")

  # Find which root contains $PWD and extract the project name.
  local proj_name="" root rel
  for root in "${roots[@]}"; do
    if [[ "$PWD" == "$root"/* ]]; then
      rel="${PWD#$root/}"
      proj_name="${rel%%/*}"
      break
    fi
  done
  # Not inside a known project (e.g. a new ⌘N window opens at ~). Leave a plain
  # shell at the current dir — don't force the proj picker. Run `proj` yourself
  # when you actually want to jump into a project.
  if [[ -z "$proj_name" ]]; then
    return 0
  fi

  # In a project dir, but its workspace isn't open yet. `proj` is the entry
  # point for creating it — launch the picker instead of a bare shell.
  if ! tmux has-session -t "$proj_name" 2>/dev/null; then
    command -v proj >/dev/null 2>&1 && proj
    return 0
  fi

  # Find the project root dir (not just $PWD — they may be in a subdir).
  local proj_dir
  for root in "${roots[@]}"; do
    if [[ -d "$root/$proj_name" ]]; then
      proj_dir="$root/$proj_name"
      break
    fi
  done
  [[ -z "$proj_dir" ]] && proj_dir="$PWD"

  # Find the next free <project>-N slot starting at 2. tmux new-session
  # -d fails atomically if the name is taken, so the loop is race-safe.
  # New sessions get an empty shell by default; the user runs `claude`
  # (or anything else) themselves. Set AUTO_CLAUDE=1 in the env to have
  # the hook auto-launch claude in the new pane instead.
  local n=2 target
  local launch_cmd=""
  if [[ -n "${AUTO_CLAUDE:-}" ]] && command -v claude >/dev/null 2>&1; then
    launch_cmd="claude"
  fi
  while true; do
    target="${proj_name}-${n}"
    if [[ -n "$launch_cmd" ]]; then
      if tmux new-session -d -s "$target" -c "$proj_dir" "$launch_cmd" 2>/dev/null; then break; fi
    else
      if tmux new-session -d -s "$target" -c "$proj_dir" 2>/dev/null; then break; fi
    fi
    n=$((n + 1))
    (( n > 50 )) && return 0
  done

  # Add the yazi pane on the right. yazi always probes the terminal at startup
  # and tmux routes the responses to the focused pane (see __proj_launch), so
  # keep yazi focused while it probes, then return focus to the left pane after
  # ~0.5s via a detached job. The subshell is forked before the `exec tmux
  # attach` below, so the timer survives the exec and still fires.
  local left
  left=$(tmux list-panes -t "$target" -F '#{pane_id}' 2>/dev/null | head -1)
  tmux split-window -h -l 30% -t "$left" -c "$proj_dir" yazi 2>/dev/null
  ( sleep 0.5; tmux select-pane -t "$left" 2>/dev/null ) &!

  # Replace the current shell with a tmux client attached to the new
  # session. `exec` ensures detach (prefix d) closes the Ghostty tab
  # cleanly instead of dropping back to a stranded shell.
  exec tmux attach -t "$target"
}

# Fire at shell startup. The autoload+precmd dance isn't needed; we want
# this to run once, immediately.
__auto_join_project
