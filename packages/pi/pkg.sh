#!/bin/bash
PKG_DESC="Pi coding agent + native llama.cpp router integration"
PKG_DEPS=(core)

pi_merge_json() {
  local target="$1" managed="$2" filter="$3" tmp
  mkdir -p "$(dirname "$target")"
  [[ -s "$target" ]] || printf '{}\n' > "$target"
  if ! jq -e . "$target" >/dev/null 2>&1; then
    warn "$target is invalid JSON — leaving it untouched."
    return 1
  fi
  tmp=$(mktemp "$(dirname "$target")/.pi-merge.XXXXXX") || return 1
  if jq --slurpfile managed "$managed" "$filter" "$target" > "$tmp"; then
    chmod 600 "$tmp"
    mv "$tmp" "$target"
  else
    rm -f "$tmp"
    warn "Couldn't merge Pi configuration into $target."
    return 1
  fi
}

pkg_install() {
  pkg_brew

  if command -v npm &> /dev/null; then
    npm install -g @earendil-works/pi-coding-agent \
      || warn "Pi install failed — run: npm install -g @earendil-works/pi-coding-agent"
  else
    warn "npm missing — install Node/NVM, then run: packages/run.sh pi"
  fi

  command -v jq &> /dev/null || {
    warn "jq missing — cannot safely merge Pi configuration."
    return 1
  }

  local local_config="$DOTFILES_DIR/config/pi/local.json"
  local host port api_key base_url
  host=$(jq -er '.host' "$local_config") || return 1
  port=$(jq -er '.port' "$local_config") || return 1
  api_key=$(jq -er '.apiKey' "$local_config") || return 1
  base_url="http://$host:$port"

  local generated_models generated_auth
  generated_models=$(mktemp) || return 1
  generated_auth=$(mktemp) || { rm -f "$generated_models"; return 1; }
  jq --arg baseUrl "$base_url/v1" \
    '.providers["llama.cpp"].baseUrl = $baseUrl' \
    "$DOTFILES_DIR/config/pi/models.json" > "$generated_models" || {
      rm -f "$generated_models" "$generated_auth"
      return 1
    }
  jq -n --arg url "$base_url" --arg key "$api_key" '{
    "llama.cpp": {
      "type": "api_key",
      "key": $key,
      "env": {"LLAMA_BASE_URL": $url}
    }
  }' > "$generated_auth"

  local agent_dir="${PI_AGENT_DIR:-$HOME/.pi/agent}"
  pi_merge_json "$agent_dir/models.json" "$generated_models" \
    '.providers = ((.providers // {}) + $managed[0].providers)'
  pi_merge_json "$agent_dir/auth.json" "$generated_auth" \
    '. + $managed[0]'
  pi_merge_json "$agent_dir/settings.json" "$DOTFILES_DIR/config/pi/settings.json" \
    '. + $managed[0]'
  rm -f "$generated_models" "$generated_auth"

  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/llama.cpp" "$HOME/Library/LaunchAgents"
  ln -sf "$DOTFILES_DIR/config/pi/llama-router.sh" "$HOME/.local/bin/pi-llama-router"

  local launch_agent="$HOME/Library/LaunchAgents/dev.pi.llama-router.plist"
  cp "$DOTFILES_DIR/config/pi/dev.pi.llama-router.plist" "$launch_agent"

  local service="gui/$(id -u)/dev.pi.llama-router"
  launchctl bootout "$service" >/dev/null 2>&1 || true
  if launchctl bootstrap "gui/$(id -u)" "$launch_agent"; then
    launchctl enable "$service" >/dev/null 2>&1 || true
    launchctl kickstart -k "$service" >/dev/null 2>&1 \
      || warn "llama.cpp router installed but did not start."
  else
    warn "Couldn't load $launch_agent with launchd."
  fi

  echo "Pi uses llama.cpp at $base_url."
  echo "Run Pi normally, then use /llama to download or manage models."

  # Optional: deploy the pi harness stack (extensions, managed settings, config
  # symlinks) from the schuettc/pi repo if it is cloned. Kept optional so this
  # bootstrap never hard-depends on that repo being present. Override the path
  # with PI_HARNESS_REPO.
  local pi_repo="${PI_HARNESS_REPO:-$HOME/GitHub/schuettc/pi}"
  if [[ -x "$pi_repo/deploy.sh" ]]; then
    echo "Deploying pi harness stack from $pi_repo ..."
    "$pi_repo/deploy.sh" || warn "pi harness deploy.sh failed — run it by hand: $pi_repo/deploy.sh"
  else
    echo "pi harness repo not found at $pi_repo — clone schuettc/pi and run ./deploy.sh to add the extension stack (optional)."
  fi
}

pkg_verify() {
  local ok=0 agent_dir="${PI_AGENT_DIR:-$HOME/.pi/agent}"
  local local_config="$DOTFILES_DIR/config/pi/local.json"
  local host port api_key base_url
  host=$(jq -r '.host' "$local_config" 2>/dev/null)
  port=$(jq -r '.port' "$local_config" 2>/dev/null)
  api_key=$(jq -r '.apiKey' "$local_config" 2>/dev/null)
  base_url="http://$host:$port"

  command -v pi &> /dev/null && echo "  PASS Pi CLI ($(pi --version))" \
    || { echo "  FAIL Pi CLI"; ok=1; }
  command -v llama-server &> /dev/null && echo "  PASS llama.cpp" \
    || { echo "  FAIL llama.cpp"; ok=1; }
  jq -e --arg url "$base_url/v1" \
    '.providers["llama.cpp"].baseUrl == $url
      and (.providers["llama.cpp"].models | length > 0)' \
    "$agent_dir/models.json" >/dev/null 2>&1 \
    && echo "  PASS Pi llama.cpp models" || { echo "  FAIL Pi llama.cpp models"; ok=1; }
  jq -e --arg url "$base_url" --arg key "$api_key" \
    '.["llama.cpp"].env.LLAMA_BASE_URL == $url
      and .["llama.cpp"].key == $key' \
    "$agent_dir/auth.json" >/dev/null 2>&1 \
    && echo "  PASS Pi llama.cpp connection" || { echo "  FAIL Pi llama.cpp connection"; ok=1; }
  [[ "$(readlink "$HOME/.local/bin/pi-llama-router")" == "$DOTFILES_DIR/config/pi/llama-router.sh" ]] \
    && echo "  PASS router launcher" || { echo "  FAIL router launcher"; ok=1; }
  launchctl print "gui/$(id -u)/dev.pi.llama-router" >/dev/null 2>&1 \
    && echo "  PASS router LaunchAgent" || { echo "  FAIL router LaunchAgent"; ok=1; }
  local attempt=0 healthy=0
  while [[ $attempt -lt 20 ]]; do
    if curl -fsS -H "Authorization: Bearer $api_key" "$base_url/health" >/dev/null 2>&1; then
      healthy=1
      break
    fi
    attempt=$((attempt + 1))
    sleep 0.25
  done
  [[ $healthy -eq 1 ]] && echo "  PASS router health ($base_url)" \
    || { echo "  FAIL router health ($base_url)"; ok=1; }
  return $ok
}
