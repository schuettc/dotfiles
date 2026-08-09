#!/bin/bash
# Run an explicit list of packages (the wizard's entry point):
#   packages/run.sh claude terminal core
# Runs them in canonical dependency order regardless of argument order.
# Dep safety: every hard dep of a requested package must be in the request
# list OR already verify clean on this machine — otherwise we stop before
# installing anything.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[[ "$(uname)" == "Darwin" ]] || die "macOS only."
[[ $# -gt 0 ]] || die "usage: packages/run.sh <package>… (see packages/*/pkg.sh)"

ORDER=(core terminal nvim markedit claude swiftbar codex cursor muster docker)

requested() { local needle="$1" p; shift; for p in "$@"; do [[ "$p" == "$needle" ]] && return 0; done; return 1; }

# Validate names + dep closure before touching anything.
for name in "$@"; do
  [[ -f "$PACKAGES_DIR/$name/pkg.sh" ]] || die "unknown package: $name"
done
for name in "$@"; do
  PKG_DIR="$PACKAGES_DIR/$name"; PKG_DEPS=()
  source "$PKG_DIR/pkg.sh"
  for dep in "${PKG_DEPS[@]}"; do
    if ! requested "$dep" "$@"; then
      PKG_DIR="$PACKAGES_DIR/$dep"
      unset -f pkg_install pkg_verify 2>/dev/null
      source "$PKG_DIR/pkg.sh"
      # PKG_VERIFY_SKIP_DRIFT: this is an existence precheck, not a
      # freshness check — a merely-outdated release-based dep (muster,
      # scratch) must not read as "not installed" and kill the install.
      # Subshell-scoped only; verify_release_current still runs for real
      # inside `pkg_verify` proper (run_pkg), where drift SHOULD fail.
      PKG_VERIFY_SKIP_DRIFT=1 pkg_verify >/dev/null 2>&1 \
        || die "$name requires '$dep' — add it to the list (it is not installed on this machine)"
    fi
  done
done

# Execute in canonical order, only the requested set.
for name in "${ORDER[@]}"; do
  requested "$name" "$@" && run_pkg "$name"
done

echo ""
if (( ${#WARNINGS[@]} )); then
  echo "Finished with ${#WARNINGS[@]} warning(s):"
  for w in "${WARNINGS[@]}"; do echo "  ⚠ $w"; done
else
  echo "Finished — no warnings."
fi
