# Report CWD to terminal via OSC 7 (enables Ghostty/cmux to open new tabs in the same directory)
__osc7_cwd() {
  printf '\e]7;file://%s%s\e\\' "$HOST" "${PWD// /%20}"
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd __osc7_cwd
__osc7_cwd  # report initial directory on shell startup
