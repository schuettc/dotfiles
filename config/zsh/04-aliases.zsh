# Dotfiles: one-step update on this machine (pull latest + converge). kempt
# pulls the config repo, self-updates its binary, and applies the manifest.
alias dotup='kempt update'

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

# Argv-shaping only: add `--` when called with NO arguments, add the channel
# flags on an interactive launch (bare / --resume / --continue), otherwise pass
# through untouched.
#
# A bare `claude` does not start a session on 2.1.220 — it opens agent view,
# the fleet launcher, whose prompt dispatches a NEW background agent instead
# of talking to you. Typing "hello" there spawns a detached job. Any argv at
# all takes the session path; `--` is the smallest that adds no behaviour of
# its own.
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
# The channel flags an interactive session carries: galley review rounds and
# muster mail arrive as channel events that WAKE the pane, instead of being
# silently missed — which is exactly what happened to a claude session launched
# without them (`claude --resume …` bypassed proj/pt, got no channels, and a
# Revise never woke it). galley and muster are MCP-SERVER channels, so this is
# the development flag (server:<name>), not the stable --channels, which takes
# plugin channels — revisit if they ever ship as plugins. Adding channels is
# NOT the identity-seeding this file bans above: it names no bus alias and mints
# no session id, so it is safe on --resume/--continue, which the identity ban
# had to skip.
__claude_channels=(--dangerously-load-development-channels server:galley server:muster-channel)

claude() {
  if (( $# )); then
    # Channels ride an interactive session launch; a subcommand (mcp, agents,
    # config…), a --print run, or a one-shot prompt passes through untouched.
    case "$1" in
      --resume|-r|--continue|-c)
        command claude "${__claude_channels[@]}" "$@"; return ;;
      *)
        command claude "$@"; return ;;
    esac
  fi
  local -a name_args
  local n; n=$(__claude_session_name)
  [[ -n "$n" ]] && name_args=(--name "$n")
  command claude "${__claude_channels[@]}" "${name_args[@]}" --
}

# Quick navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Misc
alias c='clear'
alias h='history'
alias reload='source ~/.zshrc'
