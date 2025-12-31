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

    # Enable anti-aliasing for smooth font rendering (important for MonoLisa)
    defaults write com.googlecode.iterm2 "Anti Aliased" -bool true

    echo "✓ iTerm2 will now sync preferences from: $ITERM_DIR"
    echo "✓ Anti-aliasing enabled"
    echo ""
    echo "To save changes back to dotfiles, set in iTerm2:"
    echo "  Settings → General → Settings → Save changes: 'Automatically'"
    ;;

  set-fonts)
    echo "Setting iTerm2 fonts..."

    # Check if MonoLisa is installed, fall back to FiraCode Nerd Font
    if system_profiler SPFontsDataType 2>/dev/null | grep -q "MonoLisa"; then
      MAIN_FONT="MonoLisa-Regular 13"
      echo "  Using MonoLisa as main font"
    else
      MAIN_FONT="FiraCodeNerdFont-Regular 13"
      echo "  MonoLisa not found, using FiraCode Nerd Font"
    fi

    defaults write com.googlecode.iterm2 "Normal Font" -string "$MAIN_FONT"

    # Enable non-ASCII font for Nerd Font icons
    defaults write com.googlecode.iterm2 "Use Non-ASCII Font" -bool true
    defaults write com.googlecode.iterm2 "Non Ascii Font" -string "FiraCodeNerdFontComplete-Regular 13"

    echo "✓ Fonts configured"
    echo "  Main: $MAIN_FONT"
    echo "  Non-ASCII: FiraCode Nerd Font 13"
    echo ""
    echo "Restart iTerm2 to apply changes."
    ;;

  set-preferences)
    echo "Applying recommended iTerm2 preferences..."

    PLIST=~/Library/Preferences/com.googlecode.iterm2.plist

    # Anti-aliasing (smooth text rendering)
    defaults write com.googlecode.iterm2 "Anti Aliased" -bool true

    # Option key as Esc+ for proper terminal keybindings (Alt+C, etc.)
    # This is a per-profile setting, so we use PlistBuddy
    /usr/libexec/PlistBuddy -c "Set ':New Bookmarks':0:'Option Key Sends' 2" "$PLIST" 2>/dev/null || true

    # Scrollback buffer (100k lines) - per-profile setting
    /usr/libexec/PlistBuddy -c "Set ':New Bookmarks':0:'Scrollback Lines' 100000" "$PLIST" 2>/dev/null || true

    # Disable audible bell - per-profile setting
    /usr/libexec/PlistBuddy -c "Set ':New Bookmarks':0:'Silence Bell' true" "$PLIST" 2>/dev/null || true

    echo "✓ Preferences applied:"
    echo "  - Anti-aliasing enabled"
    echo "  - Left Option key set to Esc+ (for Alt+C, etc.)"
    echo "  - Scrollback buffer: 100,000 lines"
    echo "  - Audible bell disabled"
    echo ""
    echo "Restart iTerm2 to apply changes."
    ;;

  *)
    echo "Usage: $0 {export|import|configure|set-fonts|set-preferences}"
    echo ""
    echo "Commands:"
    echo "  export          - Export current iTerm2 settings to dotfiles"
    echo "  import          - Import settings from dotfiles (new machine)"
    echo "  configure       - Set iTerm2 to sync with dotfiles folder"
    echo "  set-fonts       - Configure fonts (MonoLisa or FiraCode fallback)"
    echo "  set-preferences - Apply recommended settings (anti-alias, scrollback, etc)"
    echo ""
    echo "Recommended setup on current machine:"
    echo "  1. ./setup-iterm.sh export"
    echo "  2. ./setup-iterm.sh configure"
    echo ""
    echo "On a new machine:"
    echo "  1. ./setup-iterm.sh import"
    echo "  2. ./setup-iterm.sh set-fonts"
    echo "  3. ./setup-iterm.sh set-preferences"
    ;;
esac
