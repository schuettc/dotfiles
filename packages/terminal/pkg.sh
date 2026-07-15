#!/bin/bash
# terminal — Ghostty, tmux (+plugins), yazi. Sourced by packages/lib.sh's run_pkg.

PKG_DESC="Terminal workspace: Ghostty, tmux (+plugins), yazi file explorer, nerd fonts"
PKG_DEPS=(core)

pkg_install() {
  pkg_brew

  # Ghostty config
  echo "Linking Ghostty config..."
  mkdir -p "$CONFIG_DIR/ghostty"
  backup_if_exists "$CONFIG_DIR/ghostty/config"
  ln -sf "$DOTFILES_DIR/config/ghostty/config" "$CONFIG_DIR/ghostty/config"

  # tmux config
  echo "Linking tmux config..."
  backup_if_exists "$HOME/.tmux.conf"
  ln -sf "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"

  # yazi config (file explorer)
  echo "Linking yazi config..."
  backup_if_exists "$CONFIG_DIR/yazi"
  ln -sfn "$DOTFILES_DIR/config/yazi" "$CONFIG_DIR/yazi"

  # Install TPM (tmux plugin manager) and bootstrap declared plugins.
  # `~/.tmux/plugins/tpm` is where TPM lives; the .tmux.conf above declares
  # tmux-sensible, tmux-resurrect, and tmux-continuum.
  if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    echo "Cloning TPM..."
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" \
      || warn "TPM clone failed (network?) — tmux plugins won't install; re-run later."
  fi
  if command -v tmux &> /dev/null; then
    echo "Installing tmux plugins..."
    # install_plugins reads TMUX_PLUGIN_MANAGER_PATH from a running tmux
    # server's global env, so we need a live server that has loaded the
    # current .tmux.conf. Run the whole bootstrap on a DEDICATED throwaway
    # socket (-L) with $TMUX scrubbed: if this script runs from a shell
    # inside tmux, bare `tmux` inherits $TMUX and targets the CURRENT
    # server — a kill-server there nukes the project you're sitting in
    # (this bit us: it killed the live proj-muster server mid-upgrade and
    # left its replacement's hook queue deadlocked behind a hung tpm).
    # run-shell (not a direct script call) so install_plugins' bare `tmux`
    # calls inherit $TMUX for the bootstrap server, not the default socket.
    env -u TMUX tmux -L _bootstrap_tpm kill-server 2>/dev/null || true
    env -u TMUX tmux -L _bootstrap_tpm new-session -d -s _bootstrap_install 2>/dev/null || true
    env -u TMUX tmux -L _bootstrap_tpm run-shell "$HOME/.tmux/plugins/tpm/bin/install_plugins" 2>/dev/null || true
    env -u TMUX tmux -L _bootstrap_tpm kill-server 2>/dev/null || true
  fi
}

pkg_verify() {
  local ok=0
  command -v tmux &> /dev/null && echo "  PASS tmux" || { echo "  FAIL tmux"; ok=1; }
  [[ "$(readlink "$HOME/.tmux.conf")" == "$DOTFILES_DIR/.tmux.conf" ]] \
    && echo "  PASS ~/.tmux.conf -> repo" || { echo "  FAIL ~/.tmux.conf"; ok=1; }
  [[ -d "$HOME/.tmux/plugins/tpm" ]] && echo "  PASS TPM" || { echo "  FAIL TPM missing"; ok=1; }
  [[ "$(readlink "$CONFIG_DIR/yazi")" == "$DOTFILES_DIR/config/yazi" ]] \
    && echo "  PASS yazi config" || { echo "  FAIL yazi config"; ok=1; }
  return $ok
}
