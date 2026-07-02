# Dotfiles: one-step update on this machine (pull latest + re-apply). See update.sh.
alias dotup='~/dotfiles/update.sh'

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

# ─── tmux + projects (worktree-aware) ──────────────────────────────────────
# Project session picker. Two fzf steps, no flags to remember:
#   1. pick a project (or jump straight to a live session)
#   2. pick what to work on — and the BRANCH decides isolation:
#        • the default branch (main/dev — whatever the clone has checked out)
#          → "home base" session in the primary clone (read / coordinate)
#        • ANY other branch (existing or new) → proj transparently creates a
#          git worktree at <repo>/.worktrees/<branch> and opens the session
#          THERE, so parallel work never collides in a single tree.
#   You think in branches; proj handles every `git worktree` mechanic.
#
# Layout for every session: claude-or-shell on the left, yazi (30%) on the right.
#
# Usage:
#   proj            # default branch = home base, any other branch = worktree
#   proj --claude   # same, but auto-launch claude in the left pane
#   proj --edit     # open ~/.config/proj/roots in $EDITOR
#
# Worktrees live at <repo>/.worktrees/<branch>, ignored via .git/info/exclude
# (the repo's tracked .gitignore is untouched). A <repo>/.worktreeinclude file
# (gitignore syntax) lists gitignored paths (e.g. .env) to copy into each new
# worktree. The tmux status bar shows the branch, so you always see which
# worktree a session is in. Project roots: ~/.config/proj/roots (see proj --edit).

# ─── per-project tmux servers ───────────────────────────────────────────────
# Every project gets its OWN tmux server (socket "proj-<project>", i.e.
# `tmux -L proj-<project>`). tmux is single-threaded per server: one pane
# flooding output (a busy claude, a chatty test run) stalls keystroke handling
# for EVERY session on that server — with a single shared server that lagged
# every Ghostty tab on the machine at once. Per-project servers contain the
# blast radius to the project doing the flooding.
#
# Consequences the helpers below absorb:
#   * switch-client only works WITHIN a server — cross-server jumps detach the
#     current client and exec an attach on the target server (__proj_goto).
#   * session listing must enumerate servers (__proj_servers) — including the
#     legacy shared "default" server, so sessions created before this split
#     stay reachable until they wind down naturally.

__proj_srv() { print -r -- "proj-$1"; }

# Socket names of all tmux servers with at least one live session. Dead
# sockets (server already exited) fail the list-sessions probe; skip them.
__proj_servers() {
  local d="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)" s
  for s in "$d"/*(N=); do
    tmux -L "${s:t}" list-sessions >/dev/null 2>&1 && print -r -- "${s:t}"
  done
}

# Socket name of the server this shell's client is attached to ('' outside
# tmux). $TMUX is "<socket-path>,<pid>,<session-idx>".
__proj_cur_server() {
  [[ -n "${TMUX:-}" ]] && print -r -- "${${TMUX%%,*}:t}"
}

# Find which server hosts session <name>; prints the socket name, fails if
# none does.
__proj_find_server() {
  local name="$1" s
  for s in $(__proj_servers); do
    tmux -L "$s" has-session -t "=$name" 2>/dev/null && { print -r -- "$s"; return 0; }
  done
  return 1
}

# Move this client to session <name> on server <srv>:
#   outside tmux         → plain attach on that server
#   inside, same server  → switch-client (instant)
#   inside, other server → detach and exec the attach in the client's place
#                          (brief flicker — servers can't share clients, so
#                          this is the only clean cross-server jump)
__proj_goto() {
  local srv="$1" name="$2" cur
  cur=$(__proj_cur_server)
  if [[ -z "$cur" ]]; then
    tmux -L "$srv" attach -t "=$name"
  elif [[ "$cur" == "$srv" ]]; then
    tmux switch-client -t "=$name"
  else
    tmux detach -E "tmux -L '$srv' attach -t '=$name'"
  fi
}

# Create-or-attach a tmux session named $2 on server $1 in dir $3 with the
# standard layout (claude-or-shell left + yazi right). $4=1 auto-launches
# claude. Uses "=name" exact-match targets so prefix-sharing names (proj vs
# proj/branch) don't clash.
__proj_launch() {
  local srv="$1" name="$2" dir="$3" auto_claude="${4:-0}"
  cd "$dir"
  if ! tmux -L "$srv" has-session -t "=$name" 2>/dev/null; then
    if (( auto_claude )) && command -v claude >/dev/null; then
      tmux -L "$srv" new-session -d -s "$name" -c "$dir" "claude"
    else
      tmux -L "$srv" new-session -d -s "$name" -c "$dir"
    fi
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
  fi
  __proj_goto "$srv" "$name"
}

# Spawn an ADDITIONAL session for a project that already has a home base: find
# the next free <project>-N (N≥2, matching pt/auto-join numbering) and launch it
# in <dir> with the standard shell+yazi layout. $3=1 auto-launches claude.
__proj_launch_numbered() {
  local project="$1" dir="$2" auto_claude="${3:-0}" n=2
  local srv; srv=$(__proj_srv "$project")
  while tmux -L "$srv" has-session -t "=${project}-${n}" 2>/dev/null; do
    (( n++ )); (( n > 50 )) && { echo "too many sessions" >&2; return 1; }
  done
  __proj_launch "$srv" "${project}-${n}" "$dir" "$auto_claude"
}

# Copy gitignored paths listed in <primary>/.worktreeinclude into a new worktree.
__proj_copy_includes() {
  local primary="$1" wt="$2" inc="$1/.worktreeinclude"
  [[ -f "$inc" ]] || return 0
  local line m rel
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    for m in "$primary"/${~line}(N); do
      rel="${m#$primary/}"
      mkdir -p "$wt/${rel:h}"
      cp -R "$m" "$wt/$rel"
    done
  done < "$inc"
}

# Ensure a worktree exists for <branch> in <primary>; echo its path (or fail).
__proj_ensure_worktree() {
  local primary="$1" branch="$2" wt existing base excl
  # Already checked out in some worktree? Reuse it — turns git's "branch
  # already checked out" error into a jump to that worktree.
  existing=$(git -C "$primary" worktree list --porcelain 2>/dev/null \
    | awk -v b="refs/heads/$branch" '/^worktree /{w=substr($0,10)} /^branch /{if($2==b)print w}')
  [[ -n "$existing" ]] && { print -r -- "$existing"; return 0; }

  wt="$primary/.worktrees/$branch"
  [[ -d "$wt" ]] && { print -r -- "$wt"; return 0; }

  # Ignore .worktrees/ locally, without touching the repo's tracked .gitignore.
  excl="$primary/.git/info/exclude"
  [[ -f "$excl" ]] && ! grep -qxF '.worktrees/' "$excl" 2>/dev/null && print -- '.worktrees/' >> "$excl"

  mkdir -p "${wt:h}"
  if git -C "$primary" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$primary" worktree add "$wt" "$branch" >/dev/null 2>&1 || return 1
  else
    # New branch: base off dev if it exists, else origin/dev, else current HEAD.
    if   git -C "$primary" show-ref --verify --quiet refs/heads/dev;          then base=dev
    elif git -C "$primary" show-ref --verify --quiet refs/remotes/origin/dev; then base=origin/dev
    else base=$(git -C "$primary" symbolic-ref --short HEAD 2>/dev/null); fi
    git -C "$primary" worktree add "$wt" -b "$branch" "$base" >/dev/null 2>&1 || return 1
  fi
  __proj_copy_includes "$primary" "$wt"
  print -r -- "$wt"
}

# Build the Screen-2 list for a project: live sessions, home base, worktrees,
# other branches, and the new/prune actions. Glyphs make rows parseable.
__proj_worktree_list() {
  local primary="$1" project="$2" default_branch="$3" b s bare
  # ── jump to a running session ──  (● = already open)
  # Rows carry the session's task label (@claude_task, set via prefix T) as
  # "name  — label"; selection parsing strips everything from "  — " on.
  local -a live live_branches
  local lsrv
  live=(${(f)"$(for lsrv in $(__proj_servers); do
      tmux -L "$lsrv" ls -F $'#{session_name}\t#{@claude_task}' 2>/dev/null
    done \
    | awk -F'\t' -v p="$project" '$1==p || index($1,p"/")==1 {printf "%s%s\n", $1, ($2==""?"":"  — "$2)}' | sort -u)"})
  for s in $live; do
    print -r -- "● ${s}"
    bare="${s%%  — *}"
    [[ "$bare" == "$project/"* ]] && live_branches+=("${bare#$project/}")   # branch already has a session
  done
  # ── home base = the primary clone (read / coordinate), on whatever it's checked out ──
  print -r -- "🏠 primary clone — on ${default_branch}"
  # ── extra workspace in the primary clone (project-2, -3, …) ──
  print -r -- "+ new session here"
  # ── open a worktree on a branch ──  (skip the default branch = home base, and
  #    any branch that already has a live session shown above)
  local -a wt_branches all_branches
  wt_branches=(${(f)"$(git -C "$primary" worktree list --porcelain 2>/dev/null \
    | awk '/^branch /{sub("refs/heads/","",$2); print $2}')"})
  for b in $wt_branches; do
    [[ "$b" == "$default_branch" ]] && continue
    (( ${live_branches[(Ie)$b]} )) && continue
    print -r -- "▸ ${b}  (worktree)"
  done
  all_branches=(${(f)"$(git -C "$primary" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"})
  for b in $all_branches; do
    [[ "$b" == "$default_branch" ]] && continue
    (( ${wt_branches[(Ie)$b]} )) && continue
    (( ${live_branches[(Ie)$b]} )) && continue
    print -r -- "▸ ${b}  (branch → new worktree)"
  done
  print -r -- "+ new branch…"
  print -r -- "+ prune worktrees…"
}

# Interactive removal of worktrees (and their sessions). Never force-removes —
# trees with uncommitted/untracked work are kept and reported.
__proj_prune_worktrees() {
  local primary="$1" project="$2"
  local -a paths
  paths=(${(f)"$(git -C "$primary" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10)}')"})
  paths=(${paths:#$primary})    # never offer the primary clone
  (( ${#paths[@]} == 0 )) && { echo "No worktrees to prune."; return 0; }
  local picks
  picks=$(printf '%s\n' "${paths[@]}" | fzf --multi --reverse --height=60% \
            --prompt='prune › ' --header='Tab=select, Enter=remove. Trees with uncommitted work are kept.')
  [[ -z "$picks" ]] && return 0
  local wt rel ksrv
  for wt in ${(f)picks}; do
    rel="${wt#$primary/.worktrees/}"
    ksrv=$(__proj_find_server "$project/$rel") && tmux -L "$ksrv" kill-session -t "=$project/$rel" 2>/dev/null
    if git -C "$primary" worktree remove "$wt" 2>/dev/null; then
      echo "removed $wt"
    else
      echo "kept $wt (uncommitted/untracked) — force: git -C \"$primary\" worktree remove --force \"$wt\"" >&2
    fi
  done
  git -C "$primary" worktree prune 2>/dev/null
}

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

  # ── Screen 1: pick a project (or jump straight to a live session) ──
  # fd's --no-ignore-vcs (in the picker below): a root may itself be a git repo
  # that gitignores its project subdirs (e.g. a workspace shell whose .gitignore
  # lists its independent member repos). Those are still projects, so surface
  # them. An explicit .fdignore/.ignore in the root still hides entries.
  # (Comments can't live inside the $( { ... } ) substitution — zsh mis-parses.)
  local choice existing s
  while true; do
    existing=$(for s in $(__proj_servers); do
        tmux -L "$s" ls -F '#{session_name}#{?@claude_task,  — #{@claude_task},}' 2>/dev/null
      done | sort -u | sed 's/^/[session] /')
    choice=$(
      {
        [[ -n "$existing" ]] && print -- "$existing"
        for d in "${project_dirs[@]}"; do
          [[ -d "$d" ]] && fd --type d --max-depth 1 --no-ignore-vcs . "$d"
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
    local name="${choice#\[session\] }" exist_dir srv
    name="${name%%  — *}"   # drop the task-label suffix
    srv=$(__proj_find_server "$name") || { echo "session gone: $name" >&2; return 1; }
    exist_dir=$(tmux -L "$srv" display-message -p -t "=$name" '#{pane_current_path}' 2>/dev/null)
    [[ -n "$exist_dir" && -d "$exist_dir" ]] && cd "$exist_dir"
    __proj_goto "$srv" "$name"
    return
  fi

  local primary="$choice" project="${choice:t}"
  local psrv; psrv=$(__proj_srv "$project")

  # Non-git dir → plain home-base session, no worktree machinery.
  if ! git -C "$primary" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    __proj_launch "$psrv" "$project" "$primary" "$auto_claude"
    return
  fi

  # ── Screen 2: pick a branch / worktree — the branch decides isolation. ──
  local default_branch
  default_branch=$(git -C "$primary" symbolic-ref --short HEAD 2>/dev/null)
  local pick
  pick=$(__proj_worktree_list "$primary" "$project" "$default_branch" \
           | fzf --prompt="$project › " --height=60% --reverse)
  [[ -z "$pick" ]] && return

  case "$pick" in
    "● "*)
      local name="${pick#● }" d srv
      name="${name%%  — *}"   # drop the task-label suffix
      srv=$(__proj_find_server "$name") || { echo "session gone: $name" >&2; return 1; }
      d=$(tmux -L "$srv" display-message -p -t "=$name" '#{pane_current_path}' 2>/dev/null)
      [[ -n "$d" && -d "$d" ]] && cd "$d"
      __proj_goto "$srv" "$name"
      ;;
    "🏠 "*)
      # Default branch → home base in the primary clone.
      __proj_launch "$psrv" "$project" "$primary" "$auto_claude"
      ;;
    "+ new session here")
      # Additional workspace in the primary clone (project-2, -3, …) — never
      # attaches to the existing home base.
      __proj_launch_numbered "$project" "$primary" "$auto_claude"
      ;;
    "+ new branch…")
      printf "New branch (off dev): "
      local nb; IFS= read -r nb </dev/tty || return
      [[ -z "$nb" ]] && return
      local wt; wt=$(__proj_ensure_worktree "$primary" "$nb") \
        || { echo "Could not create worktree for $nb" >&2; return 1; }
      __proj_launch "$psrv" "$project/$nb" "$wt" "$auto_claude"
      ;;
    "+ prune worktrees…")
      __proj_prune_worktrees "$primary" "$project"
      ;;
    "▸ "*)
      local branch="${pick#▸ }"; branch="${branch%% *}"
      local wt; wt=$(__proj_ensure_worktree "$primary" "$branch") \
        || { echo "Could not open worktree for $branch" >&2; return 1; }
      __proj_launch "$psrv" "$project/$branch" "$wt" "$auto_claude"
      ;;
  esac
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
    echo "usage: pt [--claude] <project>     (or run from inside a project dir)" >&2
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
  # Sessions live on the project's OWN server (see per-project servers above).
  local srv; srv=$(__proj_srv "$proj_name")
  local n=2 target
  while true; do
    target="${proj_name}-${n}"
    if (( auto_claude )) && command -v claude >/dev/null; then
      if tmux -L "$srv" new-session -d -s "$target" -c "$proj_dir" "claude" 2>/dev/null; then break; fi
    else
      if tmux -L "$srv" new-session -d -s "$target" -c "$proj_dir" 2>/dev/null; then break; fi
    fi
    n=$((n + 1))
    (( n > 50 )) && { echo "too many sessions" >&2; return 1; }
  done

  # Add the yazi pane on the right (30%). yazi always probes the terminal at
  # startup and tmux routes the responses to the focused pane (see __proj_launch
  # for the full explanation), so keep yazi focused while it probes, then return
  # focus to the left pane after ~0.5s via a detached job.
  local left
  left=$(tmux -L "$srv" list-panes -t "$target" -F '#{pane_id}' 2>/dev/null | head -1)
  tmux -L "$srv" split-window -h -l 30% -t "$left" -c "$proj_dir" yazi
  ( sleep 0.5; tmux -L "$srv" select-pane -t "$left" 2>/dev/null ) &!

  if [[ -n "$TMUX" ]]; then
    __proj_goto "$srv" "$target"
  else
    exec tmux -L "$srv" attach -t "$target"
  fi
}

# Quick `tat` (tmux attach + create-if-missing) for a named session.
# Deliberately stays on the shared default server — it's for ad-hoc scratch
# sessions, not project workspaces (those get per-project servers via proj/pt).
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

  local cur_srv current=""
  cur_srv=$(__proj_cur_server)
  [[ -n "$cur_srv" ]] && current=$(tmux display-message -p '#{session_name}' 2>/dev/null)

  # Sweep every proj server (plus the legacy shared one). reap entries are
  # "server<TAB>session" so the kill goes to the right server.
  local -a sessions reap cmds
  local srv s c busy
  for srv in $(__proj_servers); do
    sessions=(${(f)"$(tmux -L "$srv" list-sessions -F '#{session_name}' 2>/dev/null)"})
    for s in $sessions; do
      [[ -z "$s" ]] && continue
      [[ "$srv" == "$cur_srv" && "$s" == "$current" ]] && continue
      cmds=(${(f)"$(tmux -L "$srv" list-panes -t "$s" -F '#{pane_current_command}' 2>/dev/null)"})
      busy=0
      for c in $cmds; do
        # (Ie) = exact-match reverse index; 0 means "not in idle_cmds".
        if (( ${idle_cmds[(Ie)$c]} == 0 )); then
          busy=1; break
        fi
      done
      (( busy )) || reap+=("${srv}"$'\t'"${s}")
    done
  done

  if (( ${#reap[@]} == 0 )); then
    echo "No idle sessions to clean."
    return 0
  fi

  local e
  if (( dry )); then
    echo "Would reap ${#reap[@]} idle session(s):"
    for e in $reap; do printf '  %s  (%s)\n' "${e#*$'\t'}" "${e%%$'\t'*}"; done
    return 0
  fi

  local -a reaped
  for e in $reap; do
    tmux -L "${e%%$'\t'*}" kill-session -t "=${e#*$'\t'}" 2>/dev/null && reaped+=("${e#*$'\t'}")
  done
  echo "Reaped ${#reaped[@]} idle session(s): ${(j:, :)reaped}"
}

# Clear the attention banner (sessions with a pending bell flag).
#
# Usage:
#   bell-clear        # dismiss: cycle the client through each flagged
#                     #   session so tmux clears its bell flag, then return
#                     #   to where you started. Sessions are kept alive.
#   bell-clear -k     # kill: tear down the flagged sessions entirely
#                     #   (use when they're finished/closed, not just unread)
#
# tmux only clears window_bell_flag when an attached client views the
# window, so "dismiss" mode briefly switches your client through them
# (you'll see a flash). Must be run from inside tmux for dismiss mode.
bell-clear() {
  local kill_them=0
  [[ "$1" == "-k" || "$1" == "--kill" ]] && kill_them=1

  # Flagged sessions across every proj server, as "server<TAB>session".
  local -a flagged
  local srv
  flagged=(${(f)"$(for srv in $(__proj_servers); do
      tmux -L "$srv" list-windows -a -F "#{window_bell_flag} ${srv}"$'\t''#{session_name}' 2>/dev/null
    done | awk -F'\t' '$1 ~ /^1 /{sub(/^1 /,"",$1); print $1"\t"$2}' | sort -u)"})

  if (( ${#flagged[@]} == 0 )); then
    echo "No bell flags to clear."
    return 0
  fi

  local e
  if (( kill_them )); then
    for e in $flagged; do tmux -L "${e%%$'\t'*}" kill-session -t "=${e#*$'\t'}" 2>/dev/null; done
    echo "Killed ${#flagged[@]} flagged session(s): ${(j:, :)${flagged[@]#*$'\t'}}"
    return 0
  fi

  if [[ -z "$TMUX" ]]; then
    echo "Run bell-clear from inside tmux (dismiss mode switches your client)." >&2
    echo "Or use 'bell-clear -k' to kill the flagged sessions from anywhere." >&2
    return 1
  fi

  # Dismiss mode can only cycle sessions on THIS client's server — a client
  # can't view windows on another server. Clear what we can, report the rest.
  local cur_srv origin s
  cur_srv=$(__proj_cur_server)
  origin=$(tmux display-message -p '#{session_name}')
  local -a cleared skipped
  for e in $flagged; do
    srv="${e%%$'\t'*}"; s="${e#*$'\t'}"
    if [[ "$srv" == "$cur_srv" ]]; then
      tmux switch-client -t "=$s" 2>/dev/null
      sleep 0.1
      cleared+=("$s")
    else
      skipped+=("$s ($srv)")
    fi
  done
  tmux switch-client -t "=$origin" 2>/dev/null
  (( ${#cleared[@]} )) && echo "Dismissed ${#cleared[@]} bell flag(s): ${(j:, :)cleared}"
  (( ${#skipped[@]} )) && echo "On other servers (attach there or bell-clear -k): ${(j:, :)skipped}"
}
