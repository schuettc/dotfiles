#!/bin/bash
set -euo pipefail

dotfiles_dir=${DOTFILES_DIR:-"$HOME/dotfiles"}
local_config="$dotfiles_dir/config/pi/local.json"
models_preset="$dotfiles_dir/config/pi/models.ini"

if [[ ! -f "$local_config" || ! -f "$models_preset" ]]; then
  printf 'Missing Pi configuration under %s/config/pi.\n' "$dotfiles_dir" >&2
  exit 1
fi

host=$(jq -er '.host' "$local_config")
port=$(jq -er '.port' "$local_config")
api_key=$(jq -er '.apiKey' "$local_config")

llama_server=${LLAMA_SERVER_BIN:-/opt/homebrew/bin/llama-server}
if [[ ! -x "$llama_server" ]]; then
  llama_server=$(command -v llama-server || true)
fi
if [[ -z "$llama_server" || ! -x "$llama_server" ]]; then
  printf 'llama-server is not installed. Run ~/dotfiles/packages/run.sh pi.\n' >&2
  exit 1
fi

export LLAMA_CACHE=${LLAMA_CACHE:-"$HOME/.local/share/llama.cpp"}
mkdir -p "$LLAMA_CACHE" "$HOME/Library/Logs"

exec "$llama_server" \
  --host "$host" \
  --port "$port" \
  --api-key "$api_key" \
  --models-preset "$models_preset" \
  --models-autoload \
  --models-max 2 \
  --jinja \
  --log-file "$HOME/Library/Logs/pi-llama-router.log" \
  --log-timestamps
