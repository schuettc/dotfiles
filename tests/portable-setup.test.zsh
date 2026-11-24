#!/usr/bin/env zsh
# Portable setup: the shell and tmux configuration work from any checkout.
#
# Run directly:  zsh tests/portable-setup.test.zsh
#
# kempt init clones the config repo to ~/.config/kempt/repo by default, not
# ~/dotfiles, so nothing tracked may call into the author's checkout. This
# copies the repo to an unrelated path, links what kempt.toml links into a
# temporary HOME, and checks:
#
#   * every helper .tmux.conf and the Claude notification hook run resolves
#     through a manifest link, into the copy
#   * .zshrc sources cast's release wrapper (~/.local/share/cast/cast.zsh) on
#     its own exact line, once, before the modular configs, so kempt's
#     line-in-file finds it instead of appending through the .zshrc link
#   * a shell without the wrapper starts cleanly; with it, the release cast()
#     is the one defined, runs the binary's $CAST_EXEC line once, and the
#     auto-join fires once, with its opt-outs
#   * each family skill is linked as its own folder into the copy
#
# Real shells run with a temporary HOME and a stub `cast`; nothing touches the
# machine's own HOME, tmux server or cast.

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
FIX="$TMP/elsewhere/config-repo"; mkdir -p "$FIX"; FIX=${FIX:A}
rsync -a --exclude .git "$REPO/" "$FIX/"
H="${TMP:A}/home"; mkdir -p "$H/.config"
LOG="$TMP/log"

# The layer manifest's symlinks, download binaries and notes, one per line.
manifest() {
  python3 - "$FIX/kempt.toml" "$1" <<'EOF'
import sys, tomllib
kind = sys.argv[2]
for pkg in tomllib.load(open(sys.argv[1], "rb"))["packages"].values():
    if kind == "link":
        for s in pkg.get("symlink", []):
            print(f"{s['from']}\t{s['to']}")
    elif kind == "bin":
        for d in pkg.get("download", []):
            print(d["bin"])
    else:
        for n in pkg.get("notes", []):
            print(n)
EOF
}

# Link every symlink step into $H, as kempt apply would.
for line in ${(f)"$(manifest link)"}; do
  from=${line%%$'\t'*} to=${line#*$'\t'}
  dest="$H/${to#\~/}"
  mkdir -p "${dest:h}"; ln -sfn "$FIX/$from" "$dest"
done

echo "── helpers resolve through manifest links ──"
refs=$(grep -ohE '(~|\$HOME)/\.local/bin/[A-Za-z0-9._-]+' "$FIX/.tmux.conf" "$FIX/config/claude/claude-notify.sh" | sed -E 's|.*/||' | sort -u)
ok "tmux-hook-pane.sh is among the helpers" "1" "$(print -r -- $refs | grep -cx 'tmux-hook-pane.sh')"
# Binaries the starter (the base this layer sits on) installs.
downloads=(${(f)"$(manifest bin)"} muster cast scratch creel)
for name in ${(f)refs}; do
  (( ${downloads[(Ie)$name]} )) && continue
  target="$H/.local/bin/$name"
  ok "$name is linked into the copy" "yes" \
     "$([[ -x "$target" && "${target:A}" == "$FIX"/* ]] && echo yes || echo no)"
done
ok "no checkout path in .tmux.conf or the Claude hook" "" \
   "$(grep -nE '(~|\$HOME)/dotfiles' "$FIX/.tmux.conf" "$FIX/config/claude/claude-notify.sh")"
ok "no user-specific path in .zshrc" "" "$(grep -n '/Users/' "$FIX/.zshrc")"
ok "no checkout path in kempt.toml notes" "" "$(manifest note | grep '~/dotfiles')"
ok "SwiftBar plugins linked under ~/.config" "$FIX/config/swiftbar/plugins" \
   "$([[ -L "$H/.config/swiftbar/plugins" ]] && print -r -- "${H}/.config/swiftbar/plugins"(:A))"

echo "── .zshrc includes the cast release wrapper ──"
INCLUDE='source "$HOME/.local/share/cast/cast.zsh"'
ok "include is one exact line" "1" "$(grep -cxF -- "$INCLUDE" "$FIX/.zshrc")"
inc=$(grep -nxF -- "$INCLUDE" "$FIX/.zshrc" | cut -d: -f1)
loop=$(grep -n 'for config in' "$FIX/.zshrc" | cut -d: -f1)
ok "include comes before the modular configs" "yes" "$( (( ${inc:-999} < ${loop:-0} )) && echo yes || echo no)"

# Stub cast binary: answers the auto-join probe from $AUTOJOIN_NAME and, for a
# real invocation, logs it and hands the shell a line through $CAST_EXEC.
mkdir -p "$H/.local/bin"
cat > "$H/.local/bin/cast" <<EOF
#!/bin/sh
if [ "\$1" = "__autojoin-project" ]; then printf '%s' "\${AUTOJOIN_NAME:-}"; exit 0; fi
echo "bin:\$*" >> "$LOG"
[ -n "\${CAST_EXEC:-}" ] && echo "echo exec:\$* >> '$LOG'" > "\$CAST_EXEC"
exit 0
EOF
chmod +x "$H/.local/bin/cast"
print -r -- '#!/bin/sh' > "$H/.local/bin/tmux"; print -r -- 'exit 0' >> "$H/.local/bin/tmux"
chmod +x "$H/.local/bin/tmux"

# shell <env-setup> <commands>: an interactive zsh reading only the copy's
# .zshrc, in a directory outside any project, with $H as HOME.
shell() {
  : > "$LOG"
  (cd "$TMP" && env -i HOME="$H" PATH=/usr/bin:/bin TERM=dumb TMPDIR="$TMP" zsh -fic "
    $1
    source '$FIX/.zshrc'
    $2
  " 2>/dev/null) | sed -n 's/.*RESULT://p'
}

echo "── startup without cast's wrapper ──"
ok "shell starts, no cast function" "functions:0" \
   "$(shell 'unset TMUX' 'print -r -- RESULT:functions:$+functions[cast]')"

# The release wrapper, as tackle publishes it: cast() over the binary with the
# $CAST_EXEC hand-back, and the auto-join hook fired at source time.
mkdir -p "$H/.local/share/cast"
cat > "$H/.local/share/cast/cast.zsh" <<'EOF'
cast() {
  command -v cast >/dev/null 2>&1 || { echo "cast: binary not on PATH" >&2; return 127; }
  local ef; ef="$(mktemp "${TMPDIR:-/tmp}/cast-exec.XXXXXX")" || return 1
  CAST_EXEC="$ef" command cast "$@"
  local rc=$?
  if [[ -s "$ef" ]]; then
    local cmd; cmd="$(<"$ef")"; rm -f "$ef"
    [[ -n "$cmd" ]] && eval "$cmd"
    return
  fi
  rm -f "$ef"
  return $rc
}
__cast_autojoin() {
  [[ $- != *i* ]] && return 0
  [[ -n "${TMUX:-}" ]] && return 0
  [[ -n "${NO_AUTO_TMUX:-}" ]] && return 0
  [[ -f "$HOME/.no-auto-tmux" ]] && return 0
  command -v tmux >/dev/null 2>&1 || return 0
  command -v cast >/dev/null 2>&1 || return 0
  local name; name="$(command cast __autojoin-project 2>/dev/null)"
  [[ -z "$name" ]] && return 0
  if [[ -n "${AUTO_CLAUDE:-}" ]]; then
    cast --claude "$name"
  else
    cast "$name"
  fi
}
__cast_autojoin
EOF

echo "── with cast's release wrapper ──"
ok "cast is the release function" "$H/.local/share/cast/cast.zsh" \
   "$(shell 'unset TMUX' 'print -r -- RESULT:${functions_source[cast]}')"
shell 'unset TMUX' 'cast repo-a extra' >/dev/null
ok "one invocation runs the binary and its line once" "bin:repo-a extra exec:repo-a extra" "$(<"$LOG" | tr '\n' ' ' | sed 's/ $//')"
shell 'unset TMUX' 'source ~/.zshrc 2>/dev/null; source '"'$FIX/.zshrc'"'; cast repo-b' >/dev/null
ok "re-sourcing keeps one wrapper" "bin:repo-b exec:repo-b" "$(<"$LOG" | tr '\n' ' ' | sed 's/ $//')"

shell 'unset TMUX; export AUTOJOIN_NAME=repo-a' '' >/dev/null
ok "auto-join opens the project once" "bin:repo-a exec:repo-a" "$(<"$LOG" | tr '\n' ' ' | sed 's/ $//')"
shell 'unset TMUX; export AUTOJOIN_NAME=repo-a PATH=$HOME/.local/bin:$PATH' '' >/dev/null
ok "auto-join still once when PATH already has cast" "bin:repo-a exec:repo-a" "$(<"$LOG" | tr '\n' ' ' | sed 's/ $//')"
shell 'unset TMUX; export AUTOJOIN_NAME=repo-a AUTO_CLAUDE=1' '' >/dev/null
ok "AUTO_CLAUDE forwards --claude" "bin:--claude repo-a exec:--claude repo-a" "$(<"$LOG" | tr '\n' ' ' | sed 's/ $//')"
shell 'export TMUX=fake,1,0 AUTOJOIN_NAME=repo-a' '' >/dev/null
ok "inside tmux → nothing" "" "$(<"$LOG")"
shell 'unset TMUX; export NO_AUTO_TMUX=1 AUTOJOIN_NAME=repo-a' '' >/dev/null
ok "NO_AUTO_TMUX → nothing" "" "$(<"$LOG")"
touch "$H/.no-auto-tmux"
shell 'unset TMUX; export AUTOJOIN_NAME=repo-a' '' >/dev/null
ok "~/.no-auto-tmux → nothing" "" "$(<"$LOG")"
rm -f "$H/.no-auto-tmux"

ok "the copy's tracked files are unchanged" "" "$(rsync -anc --exclude .git --out-format='%n' "$FIX/" "$REPO/" | grep -v '/$')"

echo "── family skills are linked one folder each ──"
for skill in building-a-tools-family-tool releasing-a-tools-family-tool tools-family-onboarding; do
  ok "$skill links into the copy" "$FIX/config/pi/skills/$skill" \
     "$([[ -L "$H/.pi/agent/skills/$skill" ]] && print -r -- "${H}/.pi/agent/skills/$skill"(:A))"
done
ok "the skills folder itself is not a link" "no" "$([[ -L "$H/.pi/agent/skills" ]] && echo yes || echo no)"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
