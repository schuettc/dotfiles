# proj's release wrapper (~/.local/share/proj/proj.zsh) defines proj(), with
# the $PROJ_EXEC hand-back, and __proj_autojoin, which opens a project's view
# when a fresh shell starts inside it. .zshrc sources the wrapper before PATH is
# set up and holds its auto-join while it loads, so this fires it once, now that
# ~/.local/bin is on PATH. The wrapper's own tests cover the opt-outs.
if (( $+functions[__proj_autojoin] )); then
  __proj_autojoin
fi
