#!/usr/bin/env zsh
# Guards that every AUTO-launch path types `claude --`, never a bare `claude`.
#
# Run directly:  zsh tests/claude-launch-cmd.test.zsh
#
# A bare `claude` — nothing in argv past the program name — does not start a
# session on 2.1.220. It opens agent view, the fleet launcher: its prompt
# dispatches a NEW background agent instead of talking to you, so typing
# "hello" into a freshly-launched pane silently spawns a detached job.
#
# This regressed once already and will again, because the symptom does not
# look like a shell bug. The old muster handshake passed `--session-id`, which
# happened to satisfy the same argv check; when that wrapper was removed the
# auto-launch paths fell back to bare `claude` and every new proj session
# landed in the fleet list. Nothing named agent view was touched either time.
#
# The `--` is therefore load-bearing and must survive anyone "tidying" it.

set -u

REPO="${0:A:h:h}"
ZSHDIR="$REPO/config/zsh"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

# Strip comments before scanning: the blocks explaining WHY the `--` is there
# necessarily quote the bare form they warn against.
code() { grep -hv '^[[:space:]]*#' "$ZSHDIR"/*.zsh; }

echo "── one canonical launch command ──"
ok "__claude_launch_cmd defined once" "1" \
   "$(code | grep -cE '^[[:space:]]*__claude_launch_cmd[[:space:]]*\(\)')"

# Source for the real value rather than asserting on the source text — a
# helper that returns the wrong string would pass a grep and fail in a pane.
ok "emits 'claude --'" "claude --" \
   "$(zsh -c "source '$ZSHDIR/04-aliases.zsh' 2>/dev/null; __claude_launch_cmd")"

echo "── the session name carries into Claude ──"
# proj/pt create the session already named for the work, but nothing used to
# tell Claude that name: the only tmux→Claude naming channel was `muster
# become` typing /rename, which fires on prefix T and nowhere else. So a
# session born as dotfiles/nfl-4 launched an agent that called itself
# something else entirely. `--name` closes that at launch — no injection, no
# waiting for the agent to boot. Verified on 2.1.220: it accepts a '/' and
# writes a transcript custom-title record, which is exactly what
# config/claude/statusline.sh reads to decide a name is user-set — so the
# very first status tick sees Claude and #S already aligned and takes its
# cheap path instead of treating them as diverged.
ok "names the session" "claude --name 'dotfiles/nfl-4' --" \
   "$(zsh -c "source '$ZSHDIR/04-aliases.zsh' 2>/dev/null; __claude_launch_cmd 'dotfiles/nfl-4'")"
# The `--` survives alongside the name. It is not redundant belt-and-braces:
# it is what the no-name branch relies on, and dropping it here would make
# the two branches disagree about how agent view is avoided.
ok "keeps the -- with a name" "1" \
   "$(zsh -c "source '$ZSHDIR/04-aliases.zsh' 2>/dev/null; __claude_launch_cmd x" | grep -c -- ' --$')"
# An empty argument must fall back to the bare form rather than emitting
# `--name '' --`, which claude rejects.
ok "empty name falls back" "claude --" \
   "$(zsh -c "source '$ZSHDIR/04-aliases.zsh' 2>/dev/null; __claude_launch_cmd ''")"

echo "── the auto-launch site passes the session name ──"
# Not the literal string 'claude' — the session name proj just created.
ok "launch site passes \$name" "1" \
   "$(code | grep -c '__claude_launch_cmd "\$name"')"

echo "── no auto-launch path types a bare claude ──"
# Any of: send-keys ... 'claude' Enter, or claude as a bare pane command.
ok "no bare-claude launch" "0" \
   "$(code | grep -cE "([\"']claude[\"'][[:space:]]+Enter|-c[[:space:]]+\"\\\$[a-z_]+\"[[:space:]]+[\"']claude[\"']|launch_cmd=[\"']claude[\"'])")"

echo "── every launch site routes through the helper ──"
# pt and the auto-join hook route through __proj_launch rather than calling
# the helper directly, so there is exactly one call site now.
ok "one helper call site" "1" "$(code | grep -c '\$(__claude_launch_cmd')"

echo "── send-keys targets a pane, not a session ──"
# tmux 3.7b: send-keys takes a target-PANE and will not resolve a bare
# "=name" to the active pane — it errors "can't find pane: =name" to stderr,
# which nothing checks, so the launch vanishes silently. "=name:" resolves.
ok "no bare =session send-keys" "0" \
   "$(code | grep -cE 'send-keys[^|]*-t[[:space:]]+"=\$[a-z_]+"')"

echo "── the shell still seeds no identity ──"
# `--session-id <uuid>` also clears agent view, and is the wrong fix: minting
# an id here is exactly the identity-seeding claude-wrapper-scope.test.zsh bans.
ok "no --session-id" "0" "$(code | grep -c 'session-id')"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
