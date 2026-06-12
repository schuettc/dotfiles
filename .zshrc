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

# Claude Code: force synchronized output (DECSET ?2026) on under tmux. Claude
# disables sync whenever it detects tmux, so atomic frame updates never happen
# and heavy streaming leaves stale/garbled input-box frames. Our tmux advertises
# Sync for Ghostty (terminal-features xterm-ghostty:Sync); this forces Claude to
# actually emit the markers, so the two halves together render frames atomically.
export CLAUDE_CODE_FORCE_SYNC_OUTPUT=1

# Machine-local secrets and overrides (not tracked in git)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
