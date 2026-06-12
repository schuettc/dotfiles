# ~/.zshrc - Minimal, fast shell configuration
# Modular configs are in ~/.config/zsh/

# Set XDG config directory
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Source modular configs in order
for config in "$XDG_CONFIG_HOME/zsh"/*.zsh(N); do
  [[ -f "$config" ]] && source "$config"
done

# Starship prompt (must be last, only in interactive shells)
[[ $- == *i* ]] && eval "$(starship init zsh)"

# opencode
export PATH=/Users/courtschuett/.opencode/bin:$PATH

# Claude Code: fullscreen (alternate-screen) renderer everywhere. It draws only
# the visible viewport instead of rendering inline and sharing the terminal with
# tmux — which is the root cause of the input-box border bleed, scroll tearing,
# and focus-repaint garble. Owning its own screen sidesteps the whole class.
# Trade-off: the transcript lives in Claude's own viewport, not tmux scrollback.
# (Equivalent to running /tui fullscreen in every session.)
export CLAUDE_CODE_NO_FLICKER=1

# Machine-local secrets and overrides (not tracked in git)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
