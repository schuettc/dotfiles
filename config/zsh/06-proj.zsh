# proj() itself (over the binary, with the $PROJ_EXEC hand-back) comes from
# proj's release at ~/.local/share/proj/proj.zsh, which .zshrc sources before
# this file. That wrapper defines the same auto-join; this definition is used
# only when it is absent.

# Auto-join: a fresh interactive shell inside a project dir (and not already in
# tmux) opens that project's proj view — so ⌘T in a project's Ghostty window
# lands on proj. Opt-outs preserved from the zsh reference
# (~/dotfiles/config/zsh/06-tmux-autojoin.zsh):
#   * interactive shells only
#   * skip if already inside tmux ($TMUX)
#   * skip per-shell via NO_AUTO_TMUX
#   * skip globally via ~/.no-auto-tmux
#   * silent no-op if tmux or proj is absent, or $PWD is outside every root
# AUTO_CLAUDE=1 keeps its meaning: the project view is opened with claude
# preselected as the agent for any new work.
(( $+functions[__proj_autojoin] )) || __proj_autojoin() {
  [[ $- != *i* ]] && return 0                 # interactive only
  [[ -n "${TMUX:-}" ]] && return 0            # already in tmux
  [[ -n "${NO_AUTO_TMUX:-}" ]] && return 0    # per-shell opt-out
  [[ -f "$HOME/.no-auto-tmux" ]] && return 0  # global opt-out
  command -v tmux >/dev/null 2>&1 || return 0
  command -v proj >/dev/null 2>&1 || return 0
  # Is $PWD inside a known project? Ask the binary (exit 0 + non-empty name).
  local name; name="$(command proj __autojoin-project 2>/dev/null)"
  [[ -z "$name" ]] && return 0
  if [[ -n "${AUTO_CLAUDE:-}" ]]; then
    proj --claude "$name"
  else
    proj "$name"
  fi
}

# Fire once at source time — we want this immediately, not on the next precmd.
__proj_autojoin
