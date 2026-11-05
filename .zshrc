# ~/.zshrc - Minimal, fast shell configuration
# Modular configs are in ~/.config/zsh/

# Set XDG config directory
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# proj's shell wrapper, installed by its release (kempt's terminal package).
# The source line is exactly the one proj's setup ensures, so kempt finds it
# here instead of appending it through the ~/.zshrc link; the guard keeps a
# shell without proj starting cleanly. The wrapper's own auto-join is held
# while it loads, since PATH is not set up yet: 06-proj.zsh runs it once,
# after the modular configs have.
__proj_include() {
  local NO_AUTO_TMUX=1
source "$HOME/.local/share/proj/proj.zsh"
}
[[ -r "$HOME/.local/share/proj/proj.zsh" ]] && __proj_include
unfunction __proj_include

# Source modular configs in order
for config in "$XDG_CONFIG_HOME/zsh"/*.zsh(N); do
  [[ -f "$config" ]] && source "$config"
done

# Starship prompt (must be last, only in interactive shells)
[[ $- == *i* ]] && command -v starship &> /dev/null && eval "$(starship init zsh)"

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

# Claude Code: fullscreen (alternate-screen) renderer everywhere. It draws only
# the visible viewport instead of rendering inline and sharing the terminal with
# tmux — which is the root cause of the input-box border bleed, scroll tearing,
# and focus-repaint garble. Owning its own screen sidesteps the whole class.
# Trade-off: the transcript lives in Claude's own viewport, not tmux scrollback.
# (Equivalent to running /tui fullscreen in every session.)
export CLAUDE_CODE_NO_FLICKER=1

# Machine-local secrets and overrides (not tracked in git)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
export PATH="$HOME/.rd/bin:$PATH"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)
