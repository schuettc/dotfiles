# Report CWD to the terminal via OSC 7 so Ghostty (its `path` shell feature)
# can open new tabs in the same directory.
#
# Inside tmux the plain OSC 7 is SWALLOWED by tmux — it feeds tmux's own
# #{pane_current_path} (which proj/auto-join rely on) but is never forwarded to
# Ghostty. So Ghostty's per-tab cwd freezes at wherever the client first
# attached, and ⌘T (new tab) inherits that stale dir instead of the project you
# switched into. Fix: when in tmux, ALSO emit the sequence wrapped in tmux
# passthrough (\ePtmux;…\e\\ with inner ESCs doubled) so it reaches Ghostty too.
# Requires `set -g allow-passthrough on` (see ~/.tmux.conf). We emit both: the
# plain form keeps pane_current_path correct, the wrapped form updates Ghostty.
__osc7_cwd() {
  local url="file://${HOST}${PWD// /%20}"
  printf '\e]7;%s\e\\' "$url"
  [[ -n "$TMUX" ]] && printf '\ePtmux;\e\e]7;%s\e\e\\\e\\' "$url"
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd __osc7_cwd
__osc7_cwd  # report initial directory on shell startup
