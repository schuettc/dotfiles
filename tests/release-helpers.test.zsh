#!/usr/bin/env zsh
# Tests for latest_release_tag / install_release_binary /
# verify_release_current in packages/lib.sh.
#
# Run directly:  zsh tests/release-helpers.test.zsh
#
# curl is stubbed via a PATH shim so no test touches the network. The stub
# serves a redirect URL for HEAD-style calls (-I/--head or -w url_effective)
# and copies fixture files for downloads (-o <file> <url>), driven by:
#   STUB_TAG      tag the fake /releases/latest redirect resolves to
#   STUB_ASSETS   dir holding fixture files served by basename of the URL
#   STUB_FAIL     non-empty → every curl invocation fails (offline)

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

FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT

# ── curl stub ────────────────────────────────────────────────────────────
mkdir -p "$FAKE/bin"
cat > "$FAKE/bin/curl" <<'STUB'
#!/bin/bash
[[ -n "${STUB_FAIL:-}" ]] && exit 6
out="" url="" head=0
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i+1))]}"; ((i++)) ;;
    -I|--head) head=1 ;;
    -w) ((i++)) ;;                       # url_effective handled below
    -*) ;;                               # swallow other flags
    http*) url="${args[$i]}" ;;
  esac
done
if [[ "$url" == */releases/latest ]]; then
  # HEAD probe: emulate -w '%{url_effective}' by printing the final URL
  repo_path="${url%/releases/latest}"
  printf '%s/releases/tag/%s' "$repo_path" "${STUB_TAG:?}"
  exit 0
fi
# download: serve the fixture matching the URL's basename
src="${STUB_ASSETS:?}/$(basename "$url")"
[[ -f "$src" ]] || exit 22
cp "$src" "${out:?}"
STUB
chmod +x "$FAKE/bin/curl"

lib() {  # lib <bash snippet…> — fake HOME, stubbed curl first in PATH
  HOME="$FAKE" PATH="$FAKE/bin:$PATH" \
  STUB_TAG="${STUB_TAG:-}" STUB_ASSETS="${STUB_ASSETS:-}" STUB_FAIL="${STUB_FAIL:-}" \
    bash -c "source '$REPO/packages/lib.sh' >/dev/null 2>&1; $*" 2>/dev/null
}

# ── latest_release_tag ───────────────────────────────────────────────
echo "── latest_release_tag ──"

STUB_TAG="v0.9.9"
ok "resolves the redirect tag" "v0.9.9" "$(lib 'latest_release_tag schuettc/muster')"
ok "rc 0 on success" "0" "$(lib 'latest_release_tag schuettc/muster >/dev/null; echo $?')"

STUB_FAIL=1
ok "offline prints nothing" "" "$(lib 'latest_release_tag schuettc/muster')"
ok "offline rc 1" "1" "$(lib 'latest_release_tag schuettc/muster >/dev/null; echo $?')"
unset STUB_FAIL

# ── install_release_binary ───────────────────────────────────────────────
echo "── install_release_binary ──"

# Build a fixture release: a tarball holding one executable + checksums.txt
ASSETS=$(mktemp -d)
mkdir -p "$ASSETS/stage"
printf '#!/bin/sh\necho fake-tool 9.9.9\n' > "$ASSETS/stage/faketool"
chmod +x "$ASSETS/stage/faketool"
tar -C "$ASSETS/stage" -czf "$ASSETS/faketool_test.tar.gz" faketool
( cd "$ASSETS" && shasum -a 256 faketool_test.tar.gz > checksums.txt )
STUB_ASSETS="$ASSETS"

ok "installs the binary" "0" \
   "$(lib 'install_release_binary schuettc/faketool faketool_test.tar.gz faketool; echo $?')"
ok "binary is on disk and executable" "1" \
   "$([[ -x "$FAKE/.local/bin/faketool" ]] && echo 1 || echo 0)"
ok "binary runs" "fake-tool 9.9.9" "$("$FAKE/.local/bin/faketool")"

# Corrupt checksum → refuse to install, keep the old binary
printf 'old\n' > "$FAKE/.local/bin/faketool"
( cd "$ASSETS" && printf '%064d  faketool_test.tar.gz\n' 0 > checksums.txt )
ok "checksum mismatch rc 1" "1" \
   "$(lib 'install_release_binary schuettc/faketool faketool_test.tar.gz faketool; echo $?')"
ok "old binary kept on mismatch" "old" "$(cat "$FAKE/.local/bin/faketool")"
( cd "$ASSETS" && shasum -a 256 faketool_test.tar.gz > checksums.txt )

# Offline → rc 1, binary untouched
STUB_FAIL=1
ok "offline rc 1, binary kept" "old" \
   "$(lib 'install_release_binary schuettc/faketool faketool_test.tar.gz faketool'; cat "$FAKE/.local/bin/faketool")"
unset STUB_FAIL

# ── verify_release_current ───────────────────────────────────────────────
echo "── verify_release_current ──"

STUB_TAG="v0.9.9"
ok "current → PASS rc 0" "0" "$(lib 'verify_release_current schuettc/muster 0.9.9 muster >/dev/null; echo $?')"
ok "PASS line names the label" "1" \
   "$(lib 'verify_release_current schuettc/muster 0.9.9 muster' | grep -c 'PASS muster')"
ok "leading v tolerated" "0" "$(lib 'verify_release_current schuettc/muster v0.9.9 muster >/dev/null; echo $?')"
ok "drift → FAIL rc 1" "1" "$(lib 'verify_release_current schuettc/muster 0.9.8 muster >/dev/null; echo $?')"
ok "FAIL line shows both versions" "1" \
   "$(lib 'verify_release_current schuettc/muster 0.9.8 muster' | grep -c '0.9.8.*v0.9.9')"
STUB_FAIL=1
ok "offline → silent rc 0" "0" "$(lib 'verify_release_current schuettc/muster 0.9.8 muster >/dev/null; echo $?')"
unset STUB_FAIL

rm -rf "$ASSETS"
echo ""
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
