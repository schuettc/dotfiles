#!/usr/bin/env zsh
# Tests for the project-roots parser and the canonical lookups in
# config/zsh/03-proj-roots.zsh.
#
# Run directly:  zsh tests/proj-roots.test.zsh
#
# Lives outside config/zsh/ on purpose — .zshrc sources every *.zsh in that
# directory, so a test file there would run in every shell you open.
#
# Builds a synthetic home tree + roots file under a temp XDG_CONFIG_HOME so
# nothing touches the real ~/.config/proj/roots.

set -u
source "${0:A:h:h}/config/zsh/03-proj-roots.zsh"

typeset -g PASS=0 FAIL=0

ok() {  # ok <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Synthetic layout:
#   $TMP/GitHub/{repo-a,repo-b}   -> root, children are projects
#   $TMP/dotfiles/{config,bin}    -> declared project (children are NOT projects)
#   $TMP/Downloads                -> nothing; must never resolve
mkdir -p "$TMP/GitHub/repo-a" "$TMP/GitHub/repo-b" \
         "$TMP/dotfiles/config" "$TMP/dotfiles/bin" \
         "$TMP/Downloads/stuff"

export XDG_CONFIG_HOME="$TMP/xdg"
mkdir -p "$XDG_CONFIG_HOME/proj"
ROOTS="$XDG_CONFIG_HOME/proj/roots"

echo "── parsing ──"
cat > "$ROOTS" <<EOF
# a comment
$TMP/GitHub

project:$TMP/dotfiles
$TMP/nonexistent-root
project:$TMP/also-missing
EOF
__proj_load_roots
ok "roots exclude missing dirs"     "$TMP/GitHub"   "${(j:,:)PROJ_ROOTS}"
ok "projects exclude missing dirs"  "$TMP/dotfiles" "${(j:,:)PROJ_PROJECTS}"

# Trailing slashes must not leak into ${p:t} (the project name).
cat > "$ROOTS" <<EOF
$TMP/GitHub/
project:$TMP/dotfiles/
EOF
__proj_load_roots
ok "root trailing slash stripped"    "$TMP/GitHub"   "${(j:,:)PROJ_ROOTS}"
ok "project trailing slash stripped" "$TMP/dotfiles" "${(j:,:)PROJ_PROJECTS}"
ok "name from slashed project"       "dotfiles"      "$(__proj_name_for_dir "$TMP/dotfiles/config")"

# Whitespace after the marker.
print -- "project:   $TMP/dotfiles" > "$ROOTS"
__proj_load_roots
ok "marker tolerates whitespace"     "$TMP/dotfiles" "${(j:,:)PROJ_PROJECTS}"

echo "── backward compatibility (bare paths only) ──"
print -- "$TMP/GitHub" > "$ROOTS"
__proj_load_roots
ok "legacy file loads"          "0"        "$?"
ok "legacy: repo under root"    "repo-a"   "$(__proj_name_for_dir "$TMP/GitHub/repo-a")"
ok "legacy: nested subdir"      "repo-a"   "$(__proj_name_for_dir "$TMP/GitHub/repo-a/src/deep")"
ok "legacy: dir lookup"         "$TMP/GitHub/repo-b" "$(__proj_dir_for_name repo-b)"

echo "── the regression: \$HOME-as-root vs declared project ──"
cat > "$ROOTS" <<EOF
$TMP/GitHub
project:$TMP/dotfiles
EOF
__proj_load_roots

ok "dotfiles itself is the project"   "dotfiles" "$(__proj_name_for_dir "$TMP/dotfiles")"
ok "subdir maps to dotfiles, not it"  "dotfiles" "$(__proj_name_for_dir "$TMP/dotfiles/config")"
ok "deep subdir maps to dotfiles"     "dotfiles" "$(__proj_name_for_dir "$TMP/dotfiles/bin/x/y")"
ok "root child still resolves"        "repo-a"   "$(__proj_name_for_dir "$TMP/GitHub/repo-a")"

# The whole point: unrelated home dirs must NOT look like projects, so the
# auto-join hook leaves them as plain shells instead of firing the picker.
__proj_name_for_dir "$TMP/Downloads" >/dev/null
ok "Downloads is not a project (rc)"  "1" "$?"
ok "Downloads yields no name"         ""  "$(__proj_name_for_dir "$TMP/Downloads")"
ok "Downloads subdir yields no name"  ""  "$(__proj_name_for_dir "$TMP/Downloads/stuff")"
__proj_name_for_dir "$TMP" >/dev/null
ok "temp home root is not a project"  "1" "$?"

echo "── dir lookup ──"
ok "declared project by name"  "$TMP/dotfiles"      "$(__proj_dir_for_name dotfiles)"
ok "root child by name"        "$TMP/GitHub/repo-b" "$(__proj_dir_for_name repo-b)"
__proj_dir_for_name nope >/dev/null
ok "unknown name fails"        "1" "$?"
__proj_dir_for_name "" >/dev/null
ok "empty name fails"          "1" "$?"
# A root's grandchild is not a project, so it must not resolve by name.
__proj_dir_for_name config >/dev/null
ok "project subdir is not a project" "1" "$?"

echo "── enumeration (proj Screen 1) ──"
if command -v fd >/dev/null; then
  ok "all dirs = root children + projects" \
     "$TMP/GitHub/repo-a,$TMP/GitHub/repo-b,$TMP/dotfiles" \
     "$(__proj_all_dirs | LC_ALL=C sort | paste -sd, -)"
else
  echo "  skip (fd not installed)"
fi
# No roots at all: enumeration must still succeed and emit no blank lines.
print -- "project:$TMP/dotfiles" > "$ROOTS"
__proj_load_roots
ok "projects-only enumeration" "$TMP/dotfiles" "$(__proj_all_dirs)"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
