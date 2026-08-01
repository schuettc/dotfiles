# Project root configuration.
#
# Both proj() (04-aliases.zsh) and the tmux auto-join hook
# (06-tmux-autojoin.zsh) need to know which directories on this machine
# hold projects. The list lives at ~/.config/proj/roots (one absolute
# path per line; blanks and # comments allowed; ~ and $VAR expanded).
# It is NOT tracked in this repo — each machine configures its own.
#
# A line is one of two kinds:
#
#   ~/GitHub/schuettc        a ROOT — its immediate children are projects
#   project:~/dotfiles       a PROJECT — this directory itself is the project
#
# The `project:` prefix exists because a repo that lives directly in $HOME
# has no root to sit under. Listing bare `~` as a root instead would make
# every folder in your home directory (Downloads, Library, …) look like a
# project, which makes the auto-join hook ambush plain shells with the proj
# picker. Declare the repo itself and leave $HOME alone.
#
# First-run setup is handled by proj() via __proj_init_roots when the
# config file is missing or empty.

# Loads PROJ_ROOTS (containers of projects) and PROJ_PROJECTS (directories
# that are themselves projects) from ~/.config/proj/roots.
# Returns 0 if at least one valid (existing) entry was loaded, 1 otherwise.
__proj_load_roots() {
  PROJ_ROOTS=()
  PROJ_PROJECTS=()
  local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/proj/roots"
  [[ -f "$config_file" ]] || return 1

  local line expanded is_project
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue

    # `project:<path>` marks a directory as a project in its own right.
    # Anything else is a root whose children are projects.
    is_project=0
    if [[ "$line" == project:* ]]; then
      is_project=1
      line="${line#project:}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi

    # Expand a leading ~ to $HOME, then expand any $VARs. (The ${(e)~...}
    # form does NOT expand a leading tilde when the value comes from a
    # variable, so do it explicitly.)
    expanded="${line/#\~/$HOME}"
    expanded="${(e)expanded}"
    # Strip any trailing slash so ${p:t} yields the project name.
    [[ "$expanded" != "/" ]] && expanded="${expanded%/}"
    [[ -d "$expanded" ]] || continue

    if (( is_project )); then
      PROJ_PROJECTS+=("$expanded")
    else
      PROJ_ROOTS+=("$expanded")
    fi
  done < "$config_file"

  (( ${#PROJ_ROOTS[@]} + ${#PROJ_PROJECTS[@]} > 0 ))
}

# ─── canonical project lookups ──────────────────────────────────────────────
# proj(), pt() and the auto-join hook all need to answer the same two
# questions. They ask them here so the three surfaces can never disagree
# about what counts as a project. All three assume __proj_load_roots has
# already run.

# Print the name of the project containing $1 (default $PWD); return 1 if
# the directory isn't inside any known project. Declared projects are
# checked first — they are the more specific claim on a path.
__proj_name_for_dir() {
  local dir="${1:-$PWD}" p root rel
  for p in "${PROJ_PROJECTS[@]}"; do
    if [[ "$dir" == "$p" || "$dir" == "$p"/* ]]; then
      print -r -- "${p:t}"
      return 0
    fi
  done
  for root in "${PROJ_ROOTS[@]}"; do
    if [[ "$dir" == "$root"/* ]]; then
      rel="${dir#$root/}"
      print -r -- "${rel%%/*}"
      return 0
    fi
  done
  return 1
}

# Print the directory of the project named $1; return 1 if no such project.
__proj_dir_for_name() {
  local name="$1" p root
  [[ -z "$name" ]] && return 1
  for p in "${PROJ_PROJECTS[@]}"; do
    [[ "${p:t}" == "$name" ]] && { print -r -- "$p"; return 0 }
  done
  for root in "${PROJ_ROOTS[@]}"; do
    [[ -d "$root/$name" ]] && { print -r -- "$root/$name"; return 0 }
  done
  return 1
}

# Print every candidate project directory, one absolute path per line —
# the children of each root, plus each declared project. Requires fd.
#
# fd --type d emits a trailing slash; declared projects are stored without
# one. Strip it so both sources look alike in the picker and callers get a
# plain path to hand to git.
__proj_all_dirs() {
  local root d
  for root in "${PROJ_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    fd --type d --max-depth 1 --no-ignore-vcs . "$root" | while IFS= read -r d; do
      print -r -- "${d%/}"
    done
  done
  (( ${#PROJ_PROJECTS[@]} )) && print -rl -- "${PROJ_PROJECTS[@]}"
  return 0
}

# Prompt for a single new entry, append it to ~/.config/proj/roots, and
# reload. Asks whether the path is a root (children are projects) or a
# project in its own right. Offers to create the directory if it doesn't
# exist. Skips duplicates. Returns 0 on success, 1 on cancel/error.
__proj_add_root() {
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/proj"
  local config_file="$config_dir/roots"
  mkdir -p "$config_dir"
  touch "$config_file"

  printf "New path (absolute, ~ allowed; blank to cancel): "
  local new
  IFS= read -r new </dev/tty || return 1
  [[ -z "$new" ]] && return 1

  local expanded="${new/#\~/$HOME}"
  expanded="${(e)expanded}"
  [[ "$expanded" != "/" ]] && expanded="${expanded%/}"
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

  # $HOME as a root would make every folder in it a project — the one
  # answer that is never right. Offer the project reading instead.
  local kind
  if [[ "$expanded" == "$HOME" ]]; then
    echo "$HOME can't be a root — every folder in it would become a project."
    return 1
  fi
  printf "Is this [r]oot (its children are projects) or a [p]roject itself? [R/p]: "
  IFS= read -r kind </dev/tty || return 1

  local entry="$new"
  [[ "$kind" == [pP]* ]] && entry="project:$new"

  if grep -qFx "$entry" "$config_file" 2>/dev/null; then
    echo "Already in config: $entry"
  else
    print -- "$entry" >> "$config_file"
    echo "Added: $entry"
  fi
  __proj_load_roots
}

# Pick entries out of ~/.config/proj/roots and delete them (Tab to
# multi-select). The counterpart to __proj_add_root: adding a root you
# meant as a project is easy to do and, until now, only undoable by hand.
#
# Rewrites the file by line index rather than by matching text, so comments
# and blank lines survive and duplicate entries stay distinguishable.
# Returns 1 on cancel or when there is nothing to remove.
__proj_remove_root() {
  command -v fzf >/dev/null || { echo "fzf required to remove entries" >&2; return 1; }
  local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/proj/roots"
  [[ -f "$config_file" ]] || { echo "No roots file at $config_file" >&2; return 1; }

  local -a lines menu
  lines=("${(@f)$(<"$config_file")}")

  local i trimmed
  for i in {1..$#lines}; do
    trimmed="${lines[i]#"${lines[i]%%[![:space:]]*}"}"
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
    # The line index rides along in a tab-delimited first field that fzf
    # displays (--with-nth=2) but hands back on selection.
    menu+=("$i	$trimmed")
  done
  (( ${#menu[@]} > 0 )) || { echo "No entries to remove." >&2; return 1; }

  local picked
  picked=$(printf '%s\n' "${menu[@]}" \
    | fzf --multi --prompt='remove › ' --height=40% --reverse \
          --delimiter=$'\t' --with-nth=2)
  [[ -z "$picked" ]] && return 1

  local -A drop
  local p
  for p in "${(@f)picked}"; do
    drop[${p%%	*}]=1
  done

  local -a keep
  for i in {1..$#lines}; do
    (( ${+drop[$i]} )) || keep+=("${lines[i]}")
  done
  printf '%s\n' "${keep[@]}" > "$config_file"

  for p in "${(@f)picked}"; do
    echo "Removed: ${p#*	}"
  done
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

  # A picked path that is itself a git repo is a project, not a container of
  # projects — mark it so, or its subdirectories become the projects instead.
  local -a entries
  local l lx
  for l in "${lines[@]}"; do
    lx="${l/#\~/$HOME}"
    lx="${(e)lx}"
    if [[ -d "$lx/.git" || -f "$lx/.git" ]]; then
      entries+=("project:$l")
    else
      entries+=("$l")
    fi
  done

  mkdir -p "$config_dir"
  printf '%s\n' "${entries[@]}" > "$config_file"
  echo "Wrote $config_file:"
  printf '  %s\n' "${entries[@]}"
  __proj_load_roots
}
