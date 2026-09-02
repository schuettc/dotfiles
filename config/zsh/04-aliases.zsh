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
# so any auto-launch call site can't drift from what a bare `claude` needs.
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

# The pi analog of __claude_launch_cmd. pi takes --name/-n for the session
# display name and starts an interactive session with no message argument; it
# needs no trailing `--` (there is no bare-pi agent-view trap the way `claude`
# has). The name passed is the tmux session name, so pi's session identity —
# which the harness extension stamps onto the pane and reports to muster —
# matches the pane it launched in, exactly as the claude path does.
__pi_launch_cmd() {
  local n="${1:-}"
  [[ -n "$n" ]] && { print -r -- "pi --name ${(qq)n}"; return }
  print -r -- 'pi'
}

# Quick navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Misc
alias c='clear'
alias h='history'
alias reload='source ~/.zshrc'
