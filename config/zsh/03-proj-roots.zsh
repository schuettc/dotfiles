# Project root configuration.
#
# Both proj() (04-aliases.zsh) and the tmux auto-join hook
# (06-tmux-autojoin.zsh) need to know which directories on this machine
# contain projects. The list lives at ~/.config/proj/roots (one absolute
# path per line; blanks and # comments allowed; ~ and $VAR expanded).
# It is NOT tracked in this repo — each machine configures its own.
#
# First-run setup is handled by proj() via __proj_init_roots when the
# config file is missing or empty.

# Loads PROJ_ROOTS from ~/.config/proj/roots.
# Returns 0 if at least one valid (existing) root was loaded, 1 otherwise.
__proj_load_roots() {
  PROJ_ROOTS=()
  local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/proj/roots"
  [[ -f "$config_file" ]] || return 1

  local line expanded
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    # Expand a leading ~ to $HOME, then expand any $VARs. (The ${(e)~...}
    # form does NOT expand a leading tilde when the value comes from a
    # variable, so do it explicitly.)
    expanded="${line/#\~/$HOME}"
    expanded="${(e)expanded}"
    [[ -d "$expanded" ]] && PROJ_ROOTS+=("$expanded")
  done < "$config_file"

  (( ${#PROJ_ROOTS[@]} > 0 ))
}

# Prompt for a single new project root, append it to ~/.config/proj/roots,
# and reload PROJ_ROOTS. Offers to create the directory if it doesn't
# exist. Skips duplicates. Returns 0 on success, 1 on cancel/error.
__proj_add_root() {
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/proj"
  local config_file="$config_dir/roots"
  mkdir -p "$config_dir"
  touch "$config_file"

  printf "New project root (absolute, ~ allowed; blank to cancel): "
  local new
  IFS= read -r new </dev/tty || return 1
  [[ -z "$new" ]] && return 1

  local expanded="${new/#\~/$HOME}"
  expanded="${(e)expanded}"
  if [[ ! -d "$expanded" ]]; then
    printf "Directory does not exist: %s\nCreate it? [y/N]: " "$expanded"
    local yn
    IFS= read -r yn </dev/tty || return 1
    if [[ "$yn" == [yY]* ]]; then
      mkdir -p "$expanded" || { echo "Failed to create $expanded" >&2; return 1; }
    else
      echo "Skipped."
      return 1
    fi
  fi

  if grep -qFx "$new" "$config_file" 2>/dev/null; then
    echo "Already in config: $new"
  else
    print -- "$new" >> "$config_file"
    echo "Added: $new"
  fi
  __proj_load_roots
}

# Interactive first-run prompt. Lets the user pick from common candidates
# that exist on disk, or enter a custom path. Writes ~/.config/proj/roots
# and re-loads PROJ_ROOTS. Returns 0 on success, 1 if cancelled.
__proj_init_roots() {
  command -v fzf >/dev/null || { echo "fzf required for first-run setup" >&2; return 1; }

  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/proj"
  local config_file="$config_dir/roots"

  echo "No project roots configured yet."
  echo "Pick one or more directories whose subdirs are your projects."
  echo "(Tab to multi-select, Enter to confirm, Esc to cancel.)"
  echo

  local -a candidates
  local c
  for c in \
    "$HOME/GitHub" \
    "$HOME/code" \
    "$HOME/projects" \
    "$HOME/work" \
    "$HOME/dev" \
    "$HOME/src" \
    "$HOME/Documents/code" \
    "$HOME/dotfiles"
  do
    [[ -d "$c" ]] && candidates+=("$c")
  done

  local picked
  picked=$({
    printf '%s\n' "${candidates[@]}"
    print -- "[enter custom path…]"
  } | fzf --multi --prompt='project root › ' --height=60% --reverse)
  [[ -z "$picked" ]] && return 1

  # Collect picks first. Read keyboard input from /dev/tty — using the
  # default stdin would consume from the picked-list pipe instead of
  # waiting for the user.
  local -a picks lines
  picks=("${(@f)picked}")

  local p custom
  for p in "${picks[@]}"; do
    if [[ "$p" == "[enter custom path…]" ]]; then
      while true; do
        printf "Custom path (absolute, ~ allowed; blank to skip): "
        if ! IFS= read -r custom </dev/tty; then
          break
        fi
        [[ -z "$custom" ]] && break
        lines+=("$custom")
        printf "Add another? (blank to stop): "
        IFS= read -r custom </dev/tty || break
        [[ -z "$custom" ]] && break
        lines+=("$custom")
      done
    else
      lines+=("$p")
    fi
  done

  if (( ${#lines[@]} == 0 )); then
    echo "No paths entered. Run \`proj --edit\` to configure manually." >&2
    return 1
  fi

  mkdir -p "$config_dir"
  printf '%s\n' "${lines[@]}" > "$config_file"
  echo "Wrote $config_file:"
  printf '  %s\n' "${lines[@]}"
  __proj_load_roots
}
