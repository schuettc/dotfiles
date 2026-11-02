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
#   * .zshrc sources proj's release wrapper (~/.local/share/proj/proj.zsh) on
#     its own exact line, once, before the modular configs, so kempt's
#     line-in-file finds it instead of appending through the .zshrc link
#   * a shell without the wrapper starts cleanly; with it, the release proj()
#     is the one defined, runs the binary's $PROJ_EXEC line once, and the
#     auto-join fires once, with its opt-outs
#   * the skills family tools install through the pi skills link stay ignored
#
# Real shells run with a temporary HOME and a stub `proj`; nothing touches the
# machine's own HOME, tmux server or proj.

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

# The base manifest's symlinks, download binaries and notes, one per line.
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
downloads=(${(f)"$(manifest bin)"})
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

echo "── .zshrc includes the proj release wrapper ──"
INCLUDE='source "$HOME/.local/share/proj/proj.zsh"'
ok "include is one exact line" "1" "$(grep -cxF -- "$INCLUDE" "$FIX/.zshrc")"
inc=$(grep -nxF -- "$INCLUDE" "$FIX/.zshrc" | cut -d: -f1)
loop=$(grep -n 'for config in' "$FIX/.zshrc" | cut -d: -f1)
ok "include comes before the modular configs" "yes" "$( (( ${inc:-999} < ${loop:-0} )) && echo yes || echo no)"

# Stub proj binary: answers the auto-join probe from $AUTOJOIN_NAME and, for a
# real invocation, logs it and hands the shell a line through $PROJ_EXEC.
mkdir -p "$H/.local/bin"
cat > "$H/.local/bin/proj" <<EOF
#!/bin/sh
if [ "\$1" = "__autojoin-project" ]; then printf '%s' "\${AUTOJOIN_NAME:-}"; exit 0; fi
echo "bin:\$*" >> "$LOG"
[ -n "\${PROJ_EXEC:-}" ] && echo "echo exec:\$* >> '$LOG'" > "\$PROJ_EXEC"
exit 0
EOF
chmod +x "$H/.local/bin/proj"
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

echo "── startup without proj's wrapper ──"
ok "shell starts, no proj function" "functions:0" \
   "$(shell 'unset TMUX' 'print -r -- RESULT:functions:$+functions[proj]')"

# The release wrapper, as tackle publishes it: proj() over the binary with the
# $PROJ_EXEC hand-back, and the auto-join hook fired at source time.
mkdir -p "$H/.local/share/proj"
cat > "$H/.local/share/proj/proj.zsh" <<'EOF'
proj() {
  command -v proj >/dev/null 2>&1 || { echo "proj: binary not on PATH" >&2; return 127; }
  local ef; ef="$(mktemp "${TMPDIR:-/tmp}/proj-exec.XXXXXX")" || return 1
  PROJ_EXEC="$ef" command proj "$@"
  local rc=$?
  if [[ -s "$ef" ]]; then
    local cmd; cmd="$(<"$ef")"; rm -f "$ef"
    [[ -n "$cmd" ]] && eval "$cmd"
    return
  fi
  rm -f "$ef"
  return $rc
}
__proj_autojoin() {
  [[ $- != *i* ]] && return 0
  [[ -n "${TMUX:-}" ]] && return 0
  [[ -n "${NO_AUTO_TMUX:-}" ]] && return 0
  [[ -f "$HOME/.no-auto-tmux" ]] && return 0
  command -v tmux >/dev/null 2>&1 || return 0
  command -v proj >/dev/null 2>&1 || return 0
  local name; name="$(command proj __autojoin-project 2>/dev/null)"
  [[ -z "$name" ]] && return 0
  if [[ -n "${AUTO_CLAUDE:-}" ]]; then
    proj --claude "$name"
  else
    proj "$name"
  fi
}
__proj_autojoin
EOF

echo "── with proj's release wrapper ──"
ok "proj is the release function" "$H/.local/share/proj/proj.zsh" \
   "$(shell 'unset TMUX' 'print -r -- RESULT:${functions_source[proj]}')"
shell 'unset TMUX' 'proj repo-a extra' >/dev/null
ok "one invocation runs the binary and its line once" "bin:repo-a extra exec:repo-a extra" "$(<"$LOG" | tr '\n' ' ' | sed 's/ $//')"
shell 'unset TMUX' 'source ~/.zshrc 2>/dev/null; source '"'$FIX/.zshrc'"'; proj repo-b' >/dev/null
ok "re-sourcing keeps one wrapper" "bin:repo-b exec:repo-b" "$(<"$LOG" | tr '\n' ' ' | sed 's/ $//')"

shell 'unset TMUX; export AUTOJOIN_NAME=repo-a' '' >/dev/null
ok "auto-join opens the project once" "bin:repo-a exec:repo-a" "$(<"$LOG" | tr '\n' ' ' | sed 's/ $//')"
shell 'unset TMUX; export AUTOJOIN_NAME=repo-a PATH=$HOME/.local/bin:$PATH' '' >/dev/null
ok "auto-join still once when PATH already has proj" "bin:repo-a exec:repo-a" "$(<"$LOG" | tr '\n' ' ' | sed 's/ $//')"
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

echo "── skills family tools install stay out of git ──"
for skill in reviewing-a-document sift imprint diazo muda muda-design; do
  ok "$skill is ignored" "0" "$(git -C "$REPO" check-ignore -q "config/pi/skills/$skill/SKILL.md"; echo $?)"
done
ok "tracked shared skills are not ignored" "" "$(git -C "$REPO" ls-files -ci --exclude-standard config/pi/skills)"
ok "a new skill of your own shows up" "1" "$(git -C "$REPO" check-ignore -q config/pi/skills/my-own/SKILL.md; echo $?)"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
