# dotfiles

Terminal configuration with fast shell startup (~98ms), modular zsh config, and modern CLI tools.

## Quick Start

Clone to `~/dotfiles` (recommended):

```bash
git clone https://github.com/schuettc/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh

# Configure iTerm2
./iterm2/setup-iterm.sh import
./iterm2/setup-iterm.sh set-fonts
./iterm2/setup-iterm.sh set-preferences

# Set up shell history sync (optional)
atuin login  # or: atuin register

# Restart terminal
```

## What's Included

### Shell Configuration
- **Modular zsh** - configs split into numbered files in `config/zsh/`
- **Lazy-loaded NVM** - Node available immediately, NVM loads on demand
- **Starship prompt** - two-line prompt with git status, language versions, AWS profile

### Modern CLI Tools (via Brewfile)
| Tool | Replaces | Purpose |
|------|----------|---------|
| eza | ls | File listing with icons and git status |
| bat | cat | Syntax-highlighted file viewing |
| ripgrep | grep | Fast search |
| fd | find | Fast file finding |
| zoxide | cd | Smart directory jumping |
| fzf | - | Fuzzy finder |
| delta | diff | Syntax-highlighted git diffs |
| lazygit | - | Git TUI |
| atuin | history | Shell history with sync |

### iTerm2 Configuration
| Command | Purpose |
|---------|---------|
| `./iterm2/setup-iterm.sh export` | Save current settings to dotfiles |
| `./iterm2/setup-iterm.sh import` | Load settings from dotfiles |
| `./iterm2/setup-iterm.sh configure` | Set iTerm2 to sync with this folder |
| `./iterm2/setup-iterm.sh set-fonts` | Configure fonts (MonoLisa or FiraCode fallback) |
| `./iterm2/setup-iterm.sh set-preferences` | Apply recommended settings |

### Claude Code Integration

The install script automatically configures [Claude Code](https://claude.ai/code) with:

- **Status line** - Rich context display at the bottom of Claude Code
- **Session directory** - `~/.claude/sessions/` for feature context tracking
- **Permissions** - Auto-approves session file writes (no prompts)

**Status line format:**
```
🤖 Opus 4.5 │ 🟡 73% │ 📂 my-project │ 🌿 main
```

| Part | Description |
|------|-------------|
| 🤖 / 💡 | Model name or current feature (from [feature-workflow plugin](https://github.com/schuettc/claude-code-plugins)) |
| 🟢 🟡 🔴 | Context window usage (green < 50%, yellow 50-80%, red > 80%) |
| 📂 | Working directory |
| 🌿 | Git branch |

This makes it easy to identify which feature you're working on and monitor session health.

## Structure

```
~/dotfiles/
├── .zshrc                 # Minimal loader, sources config/zsh/*
├── Brewfile               # Homebrew packages and casks
├── install.sh             # One-command setup
├── config/
│   ├── zsh/
│   │   ├── 01-paths.zsh       # PATH setup
│   │   ├── 02-nvm-lazy.zsh    # Lazy NVM loading
│   │   ├── 03-tools.zsh       # Atuin, zoxide, fzf init
│   │   ├── 04-aliases.zsh     # Modern tool aliases
│   │   └── 05-completions.zsh # Shell completions
│   ├── starship.toml      # Prompt configuration
│   ├── atuin/
│   │   └── config.toml    # History sync settings
│   └── claude/
│       └── statusline.sh  # Claude Code status line script
└── iterm2/
    ├── setup-iterm.sh     # iTerm2 configuration script
    └── com.googlecode.iterm2.plist  # Preferences backup
```

## Customization

### Adding aliases
Edit `config/zsh/04-aliases.zsh`

### Changing the prompt
Edit `config/starship.toml` - see [starship.rs/config](https://starship.rs/config/)

### Adding Homebrew packages
Edit `Brewfile`, then run `brew bundle`

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- iTerm2 (installed via Brewfile if missing)
