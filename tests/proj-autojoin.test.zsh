#!/usr/bin/env zsh
# __proj_autojoin — the auto-join hook in config/zsh/06-proj.zsh.
#
# Run directly:  zsh tests/proj-autojoin.test.zsh
#
# This is all that remains shell-side of the old proj/pt machinery: pt, the
# roots parser and the fzf picker moved into the tackle `proj` binary and are
# covered by its Go tests (internal/proj/roots_test.go, identity_test.go,
# internal/projtui/model_test.go, internal/projcli/*_test.go). What the SHELL
# still owns is the decision to fire at all — so that is what this guards:
#
#   * project detection is delegated to the binary (`proj __autojoin-project`);
#     an empty answer means "not a project" and nothing launches
#   * already inside tmux → do nothing (the ⌘T pane is the entry point)
#   * NO_AUTO_TMUX and ~/.no-auto-tmux opt-outs are honoured
#   * a hit runs `proj <name>`, and AUTO_CLAUDE=1 makes it `proj --claude <name>`
#
# The hook fires once at source time; the driver below re-invokes it directly
# under controlled env after shadowing proj() with a recorder.

set -u
REPO="${0:A:h:h}"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"

# `command -v tmux` must succeed; its exit/output is irrelevant to the hook.
print -r -- '#!/bin/sh'  > "$BIN/tmux"; print -r -- 'exit 0' >> "$BIN/tmux"
chmod +x "$BIN/tmux"

# Fake proj binary: `proj __autojoin-project` echoes $AUTOJOIN_NAME (empty ⇒
# "not a project"). The hook's `proj <name>` calls hit the shell FUNCTION we
# shadow in drive(), never this binary.
cat > "$BIN/proj" <<'EOF'
#!/bin/sh
if [ "$1" = "__autojoin-project" ]; then
  printf '%s' "${AUTOJOIN_NAME:-}"
  [ -n "${AUTOJOIN_NAME:-}" ] && exit 0 || exit 1
fi
exit 0
EOF
chmod +x "$BIN/proj"

# drive <env-setup> → the `proj:` calls the hook made. `zsh -fic` is
# interactive (satisfies the $- guard) and skips rc files.
drive() {
  : > "$TMP/log"
  zsh -fic "
    export PATH='$BIN':\$PATH HOME='$TMP'
    source '$REPO/config/zsh/06-proj.zsh' 2>/dev/null
    proj() { print -r -- \"proj:\$*\" >> '$TMP/log'; }
    $1
    __proj_autojoin
  " 2>/dev/null
  cat "$TMP/log" 2>/dev/null
}

echo "── a project hit opens proj ──"
ok "project → proj <name>" "proj:repo-a" \
   "$(drive 'unset TMUX; export AUTOJOIN_NAME=repo-a')"
ok "AUTO_CLAUDE → proj --claude <name>" "proj:--claude repo-a" \
   "$(drive 'unset TMUX; export AUTOJOIN_NAME=repo-a AUTO_CLAUDE=1')"

echo "── the hook stays out of the way ──"
ok "not a project → nothing" "" \
   "$(drive 'unset TMUX; export AUTOJOIN_NAME=')"
ok "already in tmux → nothing" "" \
   "$(drive 'export TMUX=fake,1,0 AUTOJOIN_NAME=repo-a')"
ok "NO_AUTO_TMUX → nothing" "" \
   "$(drive 'unset TMUX; export NO_AUTO_TMUX=1 AUTOJOIN_NAME=repo-a')"

# Global opt-out lives at ~/.no-auto-tmux (HOME=$TMP here). Tested last: the
# file would otherwise suppress every case above.
touch "$TMP/.no-auto-tmux"
ok "~/.no-auto-tmux → nothing" "" \
   "$(drive 'unset TMUX; export AUTOJOIN_NAME=repo-a')"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
