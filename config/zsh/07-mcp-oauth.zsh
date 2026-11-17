# pi-mcp-adapter keeps MCP OAuth tokens in AES-256-GCM files instead of the
# macOS Keychain (settings.oauthCredentialStore = "encrypted-file", set by the
# pi package in kempt.toml). This exports the key it decrypts them with.
#
# The key is per machine and made here on first shell start: kempt has no way
# to generate a secret, and it must never live in this repo. It sits apart
# from the tokens (~/.pi/agent/mcp-oauth-encrypted/). Losing it only means
# signing in to each server again with /mcp-auth. openssl, not node: node
# loads lazily (02-nvm-lazy.zsh) and may not be on PATH yet.
() {
  local key=$HOME/.config/pi-mcp/oauth.key
  if [[ ! -s $key ]] && command -v openssl &> /dev/null; then
    mkdir -p -m 700 ${key:h}
    (umask 077; openssl rand -base64 32 > $key)
  fi
  [[ -s $key ]] && export PI_MCP_ADAPTER_OAUTH_FILE_KEY=$(<$key)
}
