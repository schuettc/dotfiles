#!/bin/bash
# iTerm2 Configuration Script
# This script configures iTerm2 to use dotfiles for preferences

set -e

DOTFILES_DIR="$HOME/dotfiles"
ITERM_DIR="$DOTFILES_DIR/iterm2"

echo "iTerm2 Configuration Setup"
echo "=========================="

# Check if iTerm2 is installed
if [[ ! -d "/Applications/iTerm.app" ]]; then
  echo "Error: iTerm2 not found. Install it first:"
  echo "  brew install --cask iterm2"
  exit 1
fi

case "${1:-}" in
  export)
    echo "Exporting current iTerm2 preferences..."

    # Copy current preferences
    cp ~/Library/Preferences/com.googlecode.iterm2.plist "$ITERM_DIR/"

    # Also export as readable JSON for inspection
    plutil -convert json -o "$ITERM_DIR/com.googlecode.iterm2.json" \
      ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || true

    echo "✓ Exported to $ITERM_DIR/"
    echo ""
    echo "Key settings exported:"
    defaults read com.googlecode.iterm2 "Normal Font" 2>/dev/null | head -1
    defaults read com.googlecode.iterm2 "Non Ascii Font" 2>/dev/null | head -1
    ;;

  import)
    echo "Importing iTerm2 preferences from dotfiles..."

    if [[ ! -f "$ITERM_DIR/com.googlecode.iterm2.plist" ]]; then
      echo "Error: No preferences file found at $ITERM_DIR/"
      echo "Run './setup-iterm.sh export' first on a configured machine."
      exit 1
    fi

    # Quit iTerm2 if running
    osascript -e 'tell application "iTerm2" to quit' 2>/dev/null || true
    sleep 1

    # Import preferences
    cp "$ITERM_DIR/com.googlecode.iterm2.plist" ~/Library/Preferences/

    echo "✓ Imported preferences"
    echo "Restart iTerm2 to apply changes."
    ;;

  configure)
    echo "Configuring iTerm2 to load preferences from dotfiles..."

    # Tell iTerm2 to load preferences from custom folder
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$ITERM_DIR"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true

    echo "✓ iTerm2 will now sync preferences from: $ITERM_DIR"
    echo ""
    echo "To save changes back to dotfiles, enable in iTerm2:"
    echo "  Preferences → General → Preferences → 'Save changes to folder when iTerm2 quits'"
    ;;

  set-fonts)
    echo "Setting iTerm2 fonts..."

    # Set main font to MonoLisa
    defaults write com.googlecode.iterm2 "Normal Font" -string "MonoLisa-Regular 13"

    # Enable non-ASCII font
    defaults write com.googlecode.iterm2 "Use Non-ASCII Font" -bool true

    # Set non-ASCII font to a Nerd Font
    defaults write com.googlecode.iterm2 "Non Ascii Font" -string "FiraCodeNerdFontComplete-Regular 13"

    echo "✓ Fonts configured"
    echo "  Main: MonoLisa Regular 13"
    echo "  Non-ASCII: FiraCode Nerd Font 13"
    echo ""
    echo "Restart iTerm2 to apply changes."
    ;;

  *)
    echo "Usage: $0 {export|import|configure|set-fonts}"
    echo ""
    echo "Commands:"
    echo "  export     - Export current iTerm2 settings to dotfiles"
    echo "  import     - Import settings from dotfiles (new machine)"
    echo "  configure  - Set iTerm2 to sync with dotfiles folder"
    echo "  set-fonts  - Configure MonoLisa + Nerd Font fallback"
    echo ""
    echo "Recommended setup on current machine:"
    echo "  1. ./setup-iterm.sh export"
    echo "  2. ./setup-iterm.sh configure"
    echo ""
    echo "On a new machine:"
    echo "  1. ./setup-iterm.sh import"
    echo "  or"
    echo "  1. ./setup-iterm.sh configure"
    ;;
esac
