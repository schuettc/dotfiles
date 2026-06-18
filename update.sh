#!/usr/bin/env bash
# One-step dotfiles update for this machine: pull the latest, then re-apply
# (brew packages + symlinks via install.sh). Run it anytime:
#
#   ~/dotfiles/update.sh      # or the `dotup` alias
#
# --autostash means an uncommitted local tweak won't block the pull — it's
# stashed, the pull rebases on top, then it's re-applied. A real conflict stops
# and tells you, so nothing is silently lost.

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DOTFILES_DIR" || { echo "✗ can't find dotfiles at $DOTFILES_DIR"; exit 1; }

echo "→ Pulling latest…"
if ! git pull --rebase --autostash; then
  echo "✗ Pull hit a conflict — resolve it above, then re-run. Nothing was applied."
  exit 1
fi

echo "→ Applying (brew packages + symlinks)…"
./install.sh

# Reload the running tmux server's config, if there is one.
tmux info >/dev/null 2>&1 && tmux source-file "$HOME/.tmux.conf" 2>/dev/null && echo "→ tmux config reloaded"

echo
echo "✓ dotfiles updated. To finish: reload Ghostty config (⌘⇧,) and open a new shell (or run: source ~/.zshrc)."
