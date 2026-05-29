# Modern replacements (only if tools are installed)
command -v eza &> /dev/null && alias ls='eza --icons --group-directories-first'
command -v eza &> /dev/null && alias ll='eza -la --icons --group-directories-first --git'
command -v eza &> /dev/null && alias lt='eza --tree --level=2 --icons'
command -v bat &> /dev/null && alias cat='bat --paging=never'
command -v bat &> /dev/null && alias catp='bat --paging=never --style=plain'
command -v rg &> /dev/null && alias grep='rg'
command -v fd &> /dev/null && alias find='fd'
command -v delta &> /dev/null && alias diff='delta'

# Python
alias python='python3'
alias pip='pip3'

# Git shortcuts
alias g='git'
alias gs='git status'
alias gd='git diff'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gp='git push'
alias gl='git pull'
command -v lazygit &> /dev/null && alias lg='lazygit'

# AWS
export AWS_PAGER=""

# Claude (only if installed)
[[ -x "$HOME/.local/bin/claude" ]] && alias claude="$HOME/.local/bin/claude"

# Quick navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Misc
alias c='clear'
alias h='history'
alias reload='source ~/.zshrc'

# ─── tmux + projects ──────────────────────────────────────────────────────
# Project session picker.
#
# Lists active tmux sessions and project directories, then either attaches
# to an existing session or spawns a new one with the workspace layout:
#   left  ~70% — empty shell (run claude / vim / anything yourself)
#   right ~30% — yazi file explorer
#
# Usage:
#   proj             # pick from fzf; new sessions = shell + yazi
#   proj --claude    # same, but auto-launch claude in the left pane
#   proj --edit      # open ~/.config/proj/roots in $EDITOR
#
# Project roots are configured per-machine in ~/.config/proj/roots.
# First run prompts to create the file (see __proj_init_roots).
proj() {
  command -v fzf >/dev/null || { echo "fzf not installed"; return 1; }
  command -v fd  >/dev/null || { echo "fd not installed"; return 1; }

  if [[ "$1" == "--edit" ]]; then
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/proj/roots"
    mkdir -p "${cfg:h}"
    "${EDITOR:-vi}" "$cfg"
    return
  fi

  local auto_claude=0
  if [[ "$1" == "--claude" ]]; then
    auto_claude=1
    shift
  fi

  if ! __proj_load_roots; then
    if [[ -t 0 && -t 1 ]]; then
      __proj_init_roots || { echo "Cancelled. Run \`proj --edit\` to set roots later." >&2; return 1; }
    else
      echo "No project roots configured. Run \`proj\` interactively or edit ~/.config/proj/roots." >&2
      return 1
    fi
  fi
  local project_dirs=("${PROJ_ROOTS[@]}")

  local choice existing
  while true; do
    existing=$(tmux ls -F '#{session_name}' 2>/dev/null | sed 's/^/[session] /')
    choice=$(
      {
        [[ -n "$existing" ]] && print -- "$existing"
        for d in "${project_dirs[@]}"; do
          [[ -d "$d" ]] && fd --type d --max-depth 1 . "$d"
        done
        print -- "[+ add new project root…]"
      } | awk 'NF' | fzf --prompt='project › ' --height=60% --reverse
    )
    [[ -z "$choice" ]] && return
    if [[ "$choice" == "[+ add new project root…]" ]]; then
      __proj_add_root && project_dirs=("${PROJ_ROOTS[@]}")
      continue
    fi
    break
  done

  if [[ "$choice" == "[session] "* ]]; then
    local name="${choice#\[session\] }"
    # cd into the project dir before attaching, so the outer shell reports
    # the right cwd via OSC 7 → Ghostty knows it for future ⌘T tabs.
    local exist_dir
    exist_dir=$(tmux display-message -p -t "$name" '#{pane_current_path}' 2>/dev/null)
    [[ -n "$exist_dir" ]] && [[ -d "$exist_dir" ]] && cd "$exist_dir"
    if [[ -n "$TMUX" ]]; then tmux switch-client -t "$name"
    else tmux attach -t "$name"; fi
    return
  fi

  local dir="$choice"
  local name="${dir:t}"          # zsh: basename
  # cd before tmux takes over — this fires OSC 7 so Ghostty knows the
  # project dir, which makes ⌘T inherit cwd correctly and the workspace
  # auto-join hook fire on the next new tab.
  cd "$dir"
  if tmux has-session -t "$name" 2>/dev/null; then
    if [[ -n "$TMUX" ]]; then tmux switch-client -t "$name"
    else tmux attach -t "$name"; fi
  else
    # Spawn the session. Left pane launches claude (or shell with --bare).
    # The yazi pane spawns to the right.
    if (( auto_claude )) && command -v claude >/dev/null; then
      tmux new-session -d -s "$name" -c "$dir" "claude"
    else
      tmux new-session -d -s "$name" -c "$dir"
    fi
    tmux split-window -h -l 30% -t "$name" -c "$dir" yazi
    tmux select-pane -t "$name":0.0
    if [[ -n "$TMUX" ]]; then tmux switch-client -t "$name"
    else tmux attach -t "$name"; fi
  fi
}

# Project Tab — spawn a new terminal in a project workspace, with the same
# layout as proj() (shell on the left + yazi on the right). Use it in any
# new Ghostty tab where auto-join didn't fire (e.g., the tab landed at
# $HOME or a parent dir instead of the project root).
#
# Usage:
#   pt now-playing         # next free now-playing-N, shell + yazi
#   pt                     # auto-detect project from $PWD
#   pt --claude now-playing  # same, but auto-launch claude in the left pane
#
# Picks the next free <project>-N slot starting at 2 (the unnumbered
# session is the main one created by proj). Uses exec so the Ghostty tab
# closes cleanly when you detach.
pt() {
  local auto_claude=0
  if [[ "$1" == "--claude" ]]; then
    auto_claude=1
    shift
  fi

  local proj_name="$1"
  if ! __proj_load_roots; then
    echo "No project roots configured. Run \`proj\` to set them up." >&2
    return 1
  fi
  local roots=("${PROJ_ROOTS[@]}")

  # If no name given, try to detect from cwd.
  if [[ -z "$proj_name" ]]; then
    local root rel
    for root in "${roots[@]}"; do
      if [[ "$PWD" == "$root"/* ]]; then
        rel="${PWD#$root/}"
        proj_name="${rel%%/*}"
        break
      fi
    done
  fi

  if [[ -z "$proj_name" ]]; then
    echo "usage: pt [--bare] <project>     (or run from inside a project dir)" >&2
    return 1
  fi

  # Find the project directory across roots.
  local proj_dir=""
  for root in "${roots[@]}"; do
    if [[ -d "$root/$proj_name" ]]; then
      proj_dir="$root/$proj_name"
      break
    fi
  done
  if [[ -z "$proj_dir" ]]; then
    echo "project not found: $proj_name" >&2
    return 1
  fi

  # Find next free <project>-N (race-safe: new-session -d errors if taken).
  local n=2 target
  while true; do
    target="${proj_name}-${n}"
    if (( auto_claude )) && command -v claude >/dev/null; then
      if tmux new-session -d -s "$target" -c "$proj_dir" "claude" 2>/dev/null; then break; fi
    else
      if tmux new-session -d -s "$target" -c "$proj_dir" 2>/dev/null; then break; fi
    fi
    n=$((n + 1))
    (( n > 50 )) && { echo "too many sessions" >&2; return 1; }
  done

  # Add the yazi pane on the right (30% width) — matches proj()'s layout.
  tmux split-window -h -l 30% -t "$target" -c "$proj_dir" yazi
  tmux select-pane -t "$target":0.0

  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$target"
  else
    exec tmux attach -t "$target"
  fi
}

# Quick `tat` (tmux attach + create-if-missing) for a named session
# Usage: tat work
tat() {
  local name="${1:-${PWD:t}}"
  if tmux has-session -t "$name" 2>/dev/null; then
    if [[ -n "$TMUX" ]]; then tmux switch-client -t "$name"
    else tmux attach -t "$name"; fi
  else
    tmux new-session -A -s "$name"
  fi
}

# Reap idle tmux sessions — ones whose panes are ALL "idle" (just a shell
# or yazi), i.e. no Claude, no editor, no dev server, nothing running.
# Closing a Ghostty tab only detaches; the session lingers. This cleans
# up the leftovers without touching anything doing real work.
#
# Usage:
#   proj-clean        # reap idle sessions
#   proj-clean -n     # dry run: list what WOULD be reaped, kill nothing
#
# Never kills the session you're currently attached to. A pane running
# `claude` shows up as its version (e.g. 2.1.156), which is not in the
# idle list, so Claude sessions are always preserved.
proj-clean() {
  local dry=0
  [[ "$1" == "-n" || "$1" == "--dry-run" ]] && dry=1

  # Commands that count as "idle" (session reapable if every pane is one).
  local -a idle_cmds=(zsh bash fish sh yazi)

  local current=""
  [[ -n "$TMUX" ]] && current=$(tmux display-message -p '#{session_name}' 2>/dev/null)

  local -a sessions reap cmds
  local s c busy
  sessions=(${(f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"})

  for s in $sessions; do
    [[ -z "$s" || "$s" == "$current" ]] && continue
    cmds=(${(f)"$(tmux list-panes -t "$s" -F '#{pane_current_command}' 2>/dev/null)"})
    busy=0
    for c in $cmds; do
      # (Ie) = exact-match reverse index; 0 means "not in idle_cmds".
      if (( ${idle_cmds[(Ie)$c]} == 0 )); then
        busy=1; break
      fi
    done
    (( busy )) || reap+=("$s")
  done

  if (( ${#reap[@]} == 0 )); then
    echo "No idle sessions to clean."
    return 0
  fi

  if (( dry )); then
    echo "Would reap ${#reap[@]} idle session(s):"
    printf '  %s\n' "${reap[@]}"
    return 0
  fi

  for s in $reap; do tmux kill-session -t "$s" 2>/dev/null; done
  echo "Reaped ${#reap[@]} idle session(s): ${(j:, :)reap}"
}
