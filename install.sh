#!/bin/bash
# One-command full install: runs every package in packages/ in dependency
# order. For selective installs, open Claude Code in this repo and run the
# install-wizard skill (or: packages/run.sh <package>…).
# Resilient by design: no set -e; failures warn and continue; summary at end.

source "$(dirname "${BASH_SOURCE[0]}")/packages/lib.sh"
[[ "$(uname)" == "Darwin" ]] || die "This install is macOS-only (found $(uname)). No Linux/Windows support yet."

echo "Installing dotfiles (all packages)..."

if ! command -v brew &> /dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || die "Homebrew install failed (network?). Fix and re-run."
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
fi
command -v brew &> /dev/null || die "brew not on PATH after install — open a new shell and re-run."

for pkg in core terminal nvim markedit claude swiftbar codex muster; do
  run_pkg "$pkg"
done

echo ""
if (( ${#WARNINGS[@]} )); then
  echo "Installation finished with ${#WARNINGS[@]} warning(s):"
  for w in "${WARNINGS[@]}"; do echo "  ⚠ $w"; done
  echo "(Everything else installed — address the above and re-run; install.sh is safe to repeat.)"
else
  echo "Installation complete — no warnings."
fi
echo ""
echo "Next steps:"
echo "  1. Open Ghostty (cmd+space → \"Ghostty\") and run: source ~/.zshrc"
echo "  2. Run \`proj\` and pick a project to spin up your first workspace."
echo "  3. Inside a project, cmd+T spawns more terminals (auto-joins tmux)."
echo "  4. Optional sign-ins: atuin register/login; codex login (ChatGPT plan)."
[[ -d "/Applications/SwiftBar.app" ]] && echo "     ⚠ MANUAL: grant SwiftBar Accessibility for click-to-focus (see package output above)."
echo "  5. Read docs/terminal-usage.md for the day-to-day cheat sheet."
