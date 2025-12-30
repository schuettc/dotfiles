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
