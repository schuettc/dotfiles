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

# The claude() wrapper below does exactly one thing: argv-shaping. It carries
# no identity. That distinction is the whole history of this block, so read
# the next paragraphs before extending it.
#
# There used to be a launch handshake: mint a session UUID in the pane,
# pre-register the tmux session under its own name on the muster bus, and
# hand the same UUID to `claude --session-id`. It existed for one reason —
# an agent's hooks run in a stripped environment ($TMUX/$TMUX_PANE unset),
# so muster's own SessionStart hook could not work out which pane it
# belonged to and fell back to a paneless alias with no label/nudge/badge.
#
# muster resolves that itself now (`muster whereami`, v0.8.0: environment
# first, process-ancestry walk as fallback). Verified with $TMUX, $TMUX_PANE
# and $CLAUDE_CODE_SESSION_ID all stripped, its SessionStart hook registers a
# row carrying the correct socket, session_name, pane_id AND the harness UUID
# from its own payload, with nothing seeded beforehand.
#
# So the seed is not merely redundant, it is harmful: it made THIS repo guess
# a bus alias from the tmux session name, a plain upsert with no liveness
# check. Name a tmux session the same as a live claimed alias — likelier now
# that `muster become` gives sessions meaningful ones — and the next fresh
# claude in it silently adopted that conversation's row, inbox and all.
# Assigning bus identity is muster's job; it can compare harness UUIDs
# atomically inside one transaction, which a shell round-trip cannot.
#
# Removing it also deleted the resume asymmetry: the handshake had to skip
# --resume/--continue, because Claude picks the conversation interactively
# and the UUID is unknowable before exec. Fresh and resumed sessions now take
# the same path — none.
#
# That ban still stands, and it is about IDENTITY, not about wrappers. Do not
# reintroduce anything that names a muster alias, passes --harness-session, or
# mints a --session-id. If a session registers wrongly, the bug is in muster's
# hook, not here. (Our own SessionStart hook, bin/harness-session-stamp.sh, is
# unaffected either way: it reads session_id from the hook payload.)
#
# Clears an alias a previously-loaded shell defined — an alias would shadow
# the function below, so `reload` must drop it rather than leave it live.
unalias claude 2> /dev/null

# The name a bare `claude` adopts: this tmux session's name, which IS the
# identity proj/pt already chose. Silent and empty outside tmux, or when the
# server can't answer (detached pane, server gone) — callers fall back to the
# unnamed form rather than passing `--name ''`, which claude rejects.
__claude_session_name() {
  [[ -n "${TMUX:-}" ]] || return 0
  tmux display-message -p '#S' 2>/dev/null
}

# Argv-shaping only: add `--` when called with NO arguments, otherwise pass
# through untouched.
#
# A bare `claude` does not start a session on 2.1.220 — it opens agent view,
# the fleet launcher, whose prompt dispatches a NEW background agent instead
# of talking to you. Typing "hello" there spawns a detached job. Any argv at
# all takes the session path; `--` is the smallest that adds no behaviour of
# its own. See __claude_launch_cmd below for the verification matrix.
#
# The passthrough branch is what keeps the fleet reachable, and it is why this
# is a wrapper rather than the global `disableAgentView` switch: `claude
# agents`, `claude --bg`, `--resume`, `-p` and every subcommand reach the real
# binary with argv byte-identical to what you typed. Only the empty case is
# rewritten, because "I typed the bare word" is the one case where the fleet
# is never what was meant — you were opening a pane to work in.
#
# `command` is load-bearing: without it this recurses into itself.
#
# The no-argument branch also carries the session name through to Claude.
# That is argv-shaping, not the identity seeding this file spent a page
# banning above: `--name` sets the CONVERSATION's display name, it claims no
# bus alias and mints no session id, and it is derived from #S rather than
# used to guess one. The bans are about who assigns bus identity (muster),
# and this touches none of it.
#
# Without it, a session born `dotfiles/nfl-4` launched an agent calling
# itself something else, and the only way to reconcile them was prefix T —
# a gesture for CHANGING a name, being used to set one that was already
# decided. config/claude/statusline.sh compares Claude's name against #S on
# every tick; starting them equal is what keeps it on its cheap path.
claude() {
  (( $# )) && { command claude "$@"; return }
  local -a name_args
  local n; n=$(__claude_session_name)
  [[ -n "$n" ]] && name_args=(--name "$n")
  command claude "${name_args[@]}" --
}

# The command every AUTO-launch path types into a fresh pane. One definition
# so the call site (__proj_launch — pt and the tmux auto-join hook both route
# through it now) can't drift from what a bare `claude` needs.
#
# The trailing `--` is load-bearing, and it is the whole point of this
# function. A BARE `claude` — nothing in argv past the program name — does not
# start a session: it opens agent view, the fleet launcher that lists
# background agents and whose prompt dispatches a NEW background agent rather
# than talking to you. Typing "hello" there spawns a detached job, which is
# exactly the surprise this avoids. Any argv at all takes the session path;
# `--` is the smallest one that adds no behaviour of its own.
#
# Verified on 2.1.220, three sessions in a scratch tmux server: bare `claude`
# rendered the fleet list ("7 awaiting input · 2 working"), while `claude --`,
# `claude --add-dir .` and `claude --session-id <uuid>` all rendered a normal
# prompt. Agent view has exactly one global switch (`disableAgentView` /
# CLAUDE_CODE_DISABLE_AGENT_VIEW) and it also kills `--bg`, `/background` and
# the on-demand daemon — too broad, since we want the fleet, just not as the
# front door.
#
# `--session-id <uuid>` works too and is what the old muster handshake passed,
# which is why this bug stayed hidden until that wrapper was removed. Do not
# reach for it here: minting an id from the shell is the identity-seeding this
# file just deleted, and tests/claude-wrapper-scope.test.zsh fails the string.
#
# Not redundant with the claude() wrapper above, which would also add the
# `--`. The wrapper only exists in shells that have sourced THIS file, and
# auto-launch types into a pane shell we did not start: a tmux session left
# running from before a config change keeps its old environment until it is
# restarted. That is not hypothetical — it is how this bug survived its first
# diagnosis on 2026-07-31, when panes whose zsh predated the handshake kept
# launching bare while freshly-started ones were fine.
#
# So the command is spelled out at the call site rather than relying on the
# receiving shell to have been reloaded.
#
# $1 is the session name to carry into Claude (`--name`), omitted or empty
# for the plain form. The receiving pane's shell may predate the claude()
# wrapper above — that is this function's whole reason to exist — so the name
# is baked into the typed text rather than left for the wrapper to resolve.
__claude_launch_cmd() {
  local n="${1:-}"
  [[ -n "$n" ]] && { print -r -- "claude --name ${(qq)n} --"; return }
  print -r -- 'claude --'
}

# Quick navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Misc
alias c='clear'
alias h='history'
alias reload='source ~/.zshrc'

# ─── tmux + projects (session-identity) ────────────────────────────────────
# Project session picker. The SESSION NAME is the identity: a session is
# born named for its work — `<project>/<work>` (home base: bare
# `<project>`) — and every surface aligns to that one name (tab titles,
# this picker, and, when muster is installed, the bus alias its
# SessionStart hook seeds from the session name). Two fzf steps:
#   1. pick a project (or jump straight to a live session)
#   2. pick a session, open the home base, or name new work
# Isolation is the AGENT'S job (its own worktrees), not the picker's —
# proj creates every session in the primary clone.
#
# Usage:
#   proj              # two-screen picker
#   proj <project>    # jump straight to Screen 2 for that project
#   proj --claude     # auto-launch Claude in the new session's left pane
#   proj --cursor     # auto-launch Cursor in the new session's left pane
#   proj --edit       # open ~/.config/proj/roots in $EDITOR
#   proj --add        # add a root, or a single directory as a project
#   proj --remove     # delete entries from the roots file (Tab = multi-select)
#
# Layout for every session: agent-or-shell on the left, scratch/yazi/shell
# column on the right. Renames go through prefix T (bin/tmux-session-
# rename.sh) so no surface is left behind. Project roots:
# ~/.config/proj/roots — see 03-proj-roots.zsh.

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

# Build the standard right column (scratch -> yazi -> shell) for a freshly
# created session. Thin wrapper over the canonical builder so the same logic
# serves proj / pt / auto-join and `prefix f`.
__proj_right_column() { "$HOME/dotfiles/bin/proj-right-column.sh" "$@"; }

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

# Create a tmux session with the SERVER pinned to a stable cwd.
#
# A tmux server permanently inherits the cwd of whichever client first started
# it, and never updates it afterwards (verified: the server cwd does not follow
# later clients). If that directory is later deleted — a git worktree being the
# usual way — the server's cwd dangles, and from then on tmux SILENTLY IGNORES
# `-c` on every new pane: you ask for the project root, the pane gets the dead
# path. Its shell can't getcwd(), so it spews
#   shell-init: error retrieving current directory
# and the prompt collapses to ".". Every new pane on that server is born broken,
# and nothing short of restarting the server fixes it.
#
# That is exactly how proj-bettor-help-workspace was poisoned: a session was
# first created while the shell sat inside mlb-dk-worktrees/u7-cutover, and the
# worktree was removed later.
#
# So always create sessions from $HOME, which cannot be deleted. `-c "$dir"`
# still sets the pane's directory, so behaviour is unchanged — only the server's
# permanent cwd differs. The subshell keeps the caller's own cwd untouched, and
# the exit status still propagates for the race-safe "name taken" loops.
__tmux_new_session() {  # <srv> <new-session args...>
  local srv="$1"; shift
  ( builtin cd -q -- "$HOME" && tmux -L "$srv" new-session "$@" )
}

# Create a tmux session named $2 on server $1 in dir $3 with the standard
# layout (agent-or-shell left + yazi right), if it doesn't already exist.
# $4 is "" / "claude" / "cursor"; legacy numeric 1 means Claude. Uses "=name"
# exact-match targets so prefix-sharing names (proj vs proj/branch) don't
# clash. Does not move the client — see __proj_launch below.
__proj_ensure_session() {
  local srv="$1" name="$2" dir="$3" auto_agent="${4:-}"
  # Legacy: numeric 1 means claude.
  [[ "$auto_agent" == "1" ]] && auto_agent="claude"
  cd "$dir"
  if ! tmux -L "$srv" has-session -t "=$name" 2>/dev/null; then
    __tmux_new_session "$srv" -d -s "$name" -c "$dir"
    if [[ "$auto_agent" == "claude" ]] && command -v claude >/dev/null; then
      # Type `claude` into the pane's interactive shell rather than making it
      # the pane command, so quitting the agent leaves a usable shell in the
      # workspace instead of killing the pane (and the invocation lands in
      # shell history). This used to be load-bearing for the muster launch
      # handshake; that handshake is gone (see the claude block above), and
      # this is now an ergonomic choice, not a requirement.
      # Target is "=$name:" — the trailing colon matters. Everywhere else in
      # this file "=$name" targets a SESSION, but send-keys takes a
      # target-PANE, and tmux 3.7b will not resolve a bare "=name" to the
      # active pane: it errors "can't find pane: =name" and the keys vanish.
      # The colon makes it "exact session, current window", which resolves.
      # Verified on 3.7b: "=proj/br" fails, "=proj/br:" and "=proj/br.1" work.
      # This silently ate the auto-launch — `proj --claude` opened an empty
      # pane and said nothing, because send-keys' failure goes to stderr in a
      # detached context and nothing checks its exit code.
      tmux -L "$srv" send-keys -t "=$name:" "$(__claude_launch_cmd "$name")" Enter
    elif [[ "$auto_agent" == "cursor" ]]; then
      local ca=""
      command -v cursor-agent >/dev/null && ca="cursor-agent"
      [[ -z "$ca" ]] && command -v agent >/dev/null && ca="agent"
      # Same shape as claude for consistency: launch via the pane's shell.
      # "=$name:" for the same reason as the claude branch above — send-keys
      # needs a target-pane, and a bare "=name" doesn't resolve on tmux 3.7b.
      [[ -n "$ca" ]] && tmux -L "$srv" send-keys -t "=$name:" "$ca --trust --approve-mcps" Enter
    fi
    # Build the right column (scratch -> yazi -> shell). The builder handles
    # pane-id targeting, the per-app terminal-probe focus dance, and tags the
    # panes @sidebar. It forks its work, so it never blocks the goto/attach below.
    __proj_right_column "$srv" "$name" "$dir"
  fi
}

# Create-or-attach: ensure the session exists, then move this client to it.
__proj_launch() {
  __proj_ensure_session "$@"
  __proj_goto "$1" "$2"
}

# A work name: one path segment of the session identity. Letters, digits,
# hyphen, underscore — no '.' or ':' (tmux target separators); '/' is
# reserved for the <project>/<work> join.
__proj_valid_work() { [[ "$1" =~ '^[A-Za-z0-9_-]+$' ]]; }

# Names are typed naturally but live as addresses (tmux target, muster
# alias): collapse whitespace runs to hyphens instead of refusing them.
# Same slug rule as bin/tmux-session-rename.sh — change both together.
__proj_slug_work() { local -a w; w=(${=1}); print -r -- "${(j:-:)w}"; }

# Prompt for a work name on the tty (factored out so tests can stub it).
__proj_read_work() {
  local w
  printf "Work name (letters digits - _; spaces become -): " >/dev/tty
  IFS= read -r w </dev/tty || return 1
  print -r -- "$w"
}

# Build the Screen-2 list: live sessions of this project (● name — topic),
# the home base, and the new-work action. Legacy names (<project>-N,
# <project>/<branch>) keep showing while they're alive — migration is
# "rename as you touch them", never forced.
__proj_session_list() {
  local project="$1" lsrv name label
  for lsrv in $(__proj_servers); do
    tmux -L "$lsrv" ls -F $'#{session_name}\t#{@claude_task}' 2>/dev/null
  done | sort -u | while IFS=$'\t' read -r name label; do
    if [[ "$name" == "$project" || "$name" == "$project"/* || "$name" == "$project"-<-> ]]; then
      print -r -- "● ${name}${label:+  — $label}"
    fi
  done
  print -r -- "🏠 ${project} — home base"
  print -r -- "+ new work…"
}

# Screen 2: this project's sessions — jump to one, open the home base, or
# name new work. New sessions are created as <project>/<work> in the
# primary clone; isolation (worktrees) is the agent's job, not the picker's.
__proj_screen2() {
  local primary="$1" project="$2" auto_agent="${3:-}"
  local psrv; psrv=$(__proj_srv "$project")
  local pick
  pick=$(__proj_session_list "$project" \
           | fzf --prompt="$project › " --height=60% --reverse)
  [[ -z "$pick" ]] && return 0
  case "$pick" in
    "● "*)
      local name="${pick#● }" d srv
      name="${name%%  — *}"   # drop the topic suffix
      srv=$(__proj_find_server "$name") || { echo "session gone: $name" >&2; return 1; }
      d=$(tmux -L "$srv" display-message -p -t "=$name" '#{pane_current_path}' 2>/dev/null)
      [[ -n "$d" && -d "$d" ]] && cd "$d"
      __proj_goto "$srv" "$name"
      ;;
    "🏠 "*)
      __proj_launch "$psrv" "$project" "$primary" "$auto_agent"
      ;;
    "+ new work…")
      local w
      w=$(__proj_read_work) || return 0
      w=$(__proj_slug_work "$w")
      [[ -z "$w" ]] && return 0
      __proj_valid_work "$w" \
        || { echo "invalid work name: $w (allowed: letters digits - _)" >&2; return 1; }
      __proj_launch "$psrv" "$project/$w" "$primary" "$auto_agent"
      ;;
  esac
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

  # --add/--remove are the guided front door to the roots file; --edit stays
  # for anything they can't express.
  if [[ "$1" == "--add" ]]; then
    __proj_load_roots >/dev/null 2>&1
    __proj_add_root
    return
  fi

  if [[ "$1" == "--remove" ]]; then
    __proj_remove_root
    return
  fi

  # Update nudge: instant read of the last check's state (one dim line above
  # the picker, or nothing), then refresh in the background for next time —
  # the picker never waits on the network.
  "$HOME/dotfiles/bin/dotfiles-update-check.sh" status 2>/dev/null
  "$HOME/dotfiles/bin/dotfiles-update-check.sh" refresh >/dev/null 2>&1 &!

  local auto_agent=""
  while [[ "$1" == "--claude" || "$1" == "--cursor" ]]; do
    [[ "$1" == "--claude" ]] && auto_agent="claude"
    [[ "$1" == "--cursor" ]] && auto_agent="cursor"
    shift
  done
  local direct_project="${1:-}"

  if ! __proj_load_roots; then
    if [[ -t 0 && -t 1 ]]; then
      __proj_init_roots || { echo "Cancelled. Run \`proj --edit\` to set roots later." >&2; return 1; }
    else
      echo "No project roots configured. Run \`proj\` interactively or edit ~/.config/proj/roots." >&2
      return 1
    fi
  fi

  # `proj <project>` — skip Screen 1 (auto-join and muscle memory both use it).
  if [[ -n "$direct_project" ]]; then
    local dpdir
    dpdir=$(__proj_dir_for_name "$direct_project") \
      || { echo "project not found: $direct_project" >&2; return 1; }
    __proj_screen2 "$dpdir" "${dpdir:t}" "$auto_agent"
    return
  fi

  # ── Screen 1: pick a project (or jump straight to a live session) ──
  # Candidates come from __proj_all_dirs: the children of every root, plus
  # every `project:`-marked directory. Its fd call passes --no-ignore-vcs
  # because a root may itself be a git repo that gitignores its project
  # subdirs (e.g. a workspace shell whose .gitignore lists its independent
  # member repos). Those are still projects, so surface them. An explicit
  # .fdignore/.ignore in the root still hides entries.
  # (Comments can't live inside the $( { ... } ) substitution — zsh mis-parses.)
  # Roots-file editors live at the bottom of the list. Bound once so the row
  # text and the branch that matches it can't drift apart.
  local add_row="[+ add new project root…]"
  local rm_row="[- remove a project root…]"
  local choice existing s
  while true; do
    existing=$(for s in $(__proj_servers); do
        tmux -L "$s" ls -F '#{session_name}#{?@claude_task,  — #{@claude_task},}' 2>/dev/null
      done | sort -u | sed 's/^/[session] /')
    choice=$(
      {
        [[ -n "$existing" ]] && print -- "$existing"
        __proj_all_dirs
        print -r -- "$add_row"
        print -r -- "$rm_row"
      } | awk 'NF' | fzf --prompt='project › ' --height=60% --reverse
    )
    [[ -z "$choice" ]] && return
    # Both editors loop back to a rebuilt list rather than returning, so you
    # can fix the roots file and pick a project in one trip through proj.
    if [[ "$choice" == "$add_row" ]]; then
      __proj_add_root
      continue
    fi
    if [[ "$choice" == "$rm_row" ]]; then
      __proj_remove_root
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

  __proj_screen2 "$choice" "${choice:t}" "$auto_agent"
}

# Project Tab — create-or-attach a NAMED work session from the shell, with
# the standard layout. The session name is <project>/<work> — same identity
# rule as the proj picker; pt is just the no-picker path for when you
# already know the name.
#
# Usage:
#   pt nfl-4              # work "nfl-4" in the project containing $PWD
#   pt repo-a nfl-4       # explicit project, from anywhere
#   pt --claude nfl-4     # auto-launch Claude in the left pane
#   pt --cursor nfl-4     # auto-launch Cursor in the left pane
pt() {
  local auto_agent=""
  while [[ "$1" == "--claude" || "$1" == "--cursor" ]]; do
    [[ "$1" == "--claude" ]] && auto_agent="claude"
    [[ "$1" == "--cursor" ]] && auto_agent="cursor"
    shift
  done

  if ! __proj_load_roots; then
    echo "No project roots configured. Run \`proj\` to set them up." >&2
    return 1
  fi

  local project="" work=""
  if (( $# >= 2 )); then
    project="$1"; work="$2"
  elif (( $# == 1 )); then
    work="$1"
    project=$(__proj_name_for_dir "$PWD")
  fi
  if [[ -z "$project" || -z "$work" ]]; then
    echo "usage: pt [--claude|--cursor] [<project>] <work>    (project auto-detected inside one)" >&2
    return 1
  fi
  work=$(__proj_slug_work "$work")
  __proj_valid_work "$work" \
    || { echo "invalid work name: $work (allowed: letters digits - _)" >&2; return 1; }

  local proj_dir
  if ! proj_dir=$(__proj_dir_for_name "$project"); then
    echo "project not found: $project" >&2
    return 1
  fi

  local srv name
  srv=$(__proj_srv "$project")
  name="$project/$work"
  if [[ -n "$TMUX" ]]; then
    __proj_launch "$srv" "$name" "$proj_dir" "$auto_agent"
  else
    __proj_ensure_session "$srv" "$name" "$proj_dir" "$auto_agent"
    __proj_attach_exec "$srv" "$name"
  fi
}

# exec-attach endgame for pt outside tmux (factored so tests can stub the
# exec away). `exec` makes detach close the Ghostty tab cleanly.
__proj_attach_exec() { exec tmux -L "$1" attach -t "=$2"; }

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
