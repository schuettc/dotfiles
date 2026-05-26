# Terminal Setup (Part 2)

> Picks up where the dotfiles README leaves off. Part 1 — the modular zsh
> foundation, starship, atuin, fzf, etc. — is documented in the existing
> "Building the Perfect Terminal Setup" blog post and in the repo root
> `README.md`. **This guide layers on top of that:** Ghostty, tmux, yazi,
> and a `proj` session picker.

_(Tutorial form — fresh-machine install steps. Filled in after the workflow
is verified end-to-end. See `setup-notes.md` for the live running log.)_

## Result

A fresh Mac runs `install.sh` and ends up with:

- Ghostty configured (MonoLisa, Catppuccin Mocha, splits, scrollback)
- tmux configured (`Ctrl-A` prefix, mouse, vim-style splits, plugins)
- yazi installed and themed to match
- `proj` shell function for fzf-picker-driven session management
- Auto-save/restore across reboots via tmux-resurrect + tmux-continuum

## Sections to write (placeholders)

1. Prerequisites (Part 1 dotfiles installed)
2. Install Ghostty (via Brewfile)
3. Install tmux + TPM + plugins
4. Install yazi
5. Configure: `.tmux.conf`, `config/yazi/`, `config/ghostty/config`
6. Add `proj()` to `config/zsh/04-aliases.zsh`
7. Bootstrap: `install.sh` symlinks + headless plugin install
8. Verification checklist
