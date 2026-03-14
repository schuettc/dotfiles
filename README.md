# dotfiles

Terminal configuration with fast shell startup (~98ms), modular zsh config, modern CLI tools, and Claude Code integration — all running in [cmux](https://cmux.dev).

## Quick Start

**1. Clone and install:**
```bash
git clone https://github.com/schuettc/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```

**2. Set up shell history sync (optional):**
```bash
atuin login
```
Or register a new account: `atuin register`

**3. Open cmux and start working**

## What's Included

### Terminal: cmux + Ghostty

[cmux](https://cmux.dev) is a native macOS terminal built on Ghostty, designed for AI coding agents. The Ghostty config (`config/ghostty/config`) sets up fonts, theme, scrollback, and key mappings.

### Shell Configuration
- **Modular zsh** — configs split into numbered files in `config/zsh/`
- **Lazy-loaded NVM** — Node available immediately, NVM loads on demand
- **Starship prompt** — two-line prompt with git status, language versions, AWS profile

### Modern CLI Tools (via Brewfile)
| Tool | Replaces | Purpose |
|------|----------|---------|
| eza | ls | File listing with icons and git status |
| bat | cat | Syntax-highlighted file viewing |
| ripgrep | grep | Fast search |
| fd | find | Fast file finding |
| zoxide | cd | Smart directory jumping |
| fzf | — | Fuzzy finder |
| delta | diff | Syntax-highlighted git diffs |
| lazygit | — | Git TUI |
| atuin | history | Shell history with sync |

### Claude Code Integration

The install script configures [Claude Code](https://claude.ai/code) with:

- **Status line** — model, context usage, git info, working directory
- **cmux notifications** — Claude Code events surface in cmux's sidebar and desktop notifications
- **Session tracking** — sessions mapped to cmux workspaces

**Status line format:**
```
🤖 Opus 4.5 │ 🟡 73% │ 📂 my-project │ 🌿 main
```

| Part | Description |
|------|-------------|
| 🤖 / 💡 | Model name or current feature |
| 🟢 🟡 🔴 | Context window usage (green < 50%, yellow 50-80%, red > 80%) |
| 📂 | Working directory |
| 🌿 | Git branch with ahead/behind, conflicts, staged/modified/untracked counts |

## Structure

```
~/dotfiles/
├── .zshrc                 # Minimal loader, sources config/zsh/*
├── Brewfile               # Homebrew packages and casks
├── install.sh             # One-command setup
├── config/
│   ├── ghostty/
│   │   └── config         # Terminal config (fonts, theme, behavior)
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
│       ├── statusline.sh  # Claude Code status line
│       └── cmux-notify.sh # Claude Code → cmux notifications
```

## Customization

### Adding aliases
Edit `config/zsh/04-aliases.zsh`

### Changing the prompt
Edit `config/starship.toml` — see [starship.rs/config](https://starship.rs/config/)

### Changing terminal settings
Edit `config/ghostty/config` — cmux reads keybindings from this file

### Adding Homebrew packages
Edit `Brewfile`, then run `brew bundle`

## Requirements

- macOS
- [Homebrew](https://brew.sh)
