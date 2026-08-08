# Workspace auto-join: when a new shell starts inside a project directory
# and we're not already in tmux, open that project's picker. Together with
# Ghostty's window-inherit-working-directory = true, this means ⌘T inside a
# project's Ghostty window just works — it lands on proj's Screen 2, ready
# to attach to a live session or name new work.
#
# Behavior:
#   * Skips if already inside tmux ($TMUX is set).
#   * Skips if NO_AUTO_TMUX is set (escape hatch for one-off shells).
#   * Skips if the cwd is not under one of the configured project roots.
#   * Otherwise: opens `proj` for the detected project (Screen 2), or
#     `proj --claude` if AUTO_CLAUDE is set.
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

  # Which project (if any) contains $PWD — see __proj_name_for_dir.
  local proj_name
  # Not inside a known project (e.g. a new ⌘N window opens at ~). Leave a plain
  # shell at the current dir — don't force the proj picker. Run `proj` yourself
  # when you actually want to jump into a project.
  proj_name=$(__proj_name_for_dir "$PWD") || return 0
  [[ -z "$proj_name" ]] && return 0

  # ⌘T in a project dir: never mint an anonymous session. Open the
  # project's Screen 2 (live sessions · home base · new work) and let the
  # operator name what they're starting — naming is always an explicit
  # gesture. AUTO_CLAUDE=1 keeps its meaning: a session created from this
  # picker auto-launches Claude in the left pane.
  if [[ -n "${AUTO_CLAUDE:-}" ]]; then
    proj --claude "$proj_name"
  else
    proj "$proj_name"
  fi
}

# Fire at shell startup. The autoload+precmd dance isn't needed; we want
# this to run once, immediately.
__auto_join_project
