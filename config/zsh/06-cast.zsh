# cast's release wrapper (~/.local/share/cast/cast.zsh) defines cast(), with
# the $CAST_EXEC hand-back, and __cast_autojoin, which opens a project's view
# when a fresh shell starts inside it. .zshrc sources the wrapper before PATH is
# set up and holds its auto-join while it loads, so this fires it once, now that
# ~/.local/bin is on PATH. The wrapper's own tests cover the opt-outs.
if (( $+functions[__cast_autojoin] )); then
  __cast_autojoin
fi
