# Recover from a working directory that no longer exists.
#
# Deleting a git worktree (or any dir) out from under a running tmux pane leaves
# that pane's cwd dangling. tmux keeps handing the dead path to every new pane
# and shell it spawns, so the shell starts with an invalid cwd and every command
# that calls getcwd() spews:
#
#   shell-init: error retrieving current directory: getcwd: cannot access
#   parent directories: No such file or directory
#
# …and the prompt collapses to ".". The pane is then effectively unusable until
# you cd out by hand, and `proj`/split bindings that inherit
# #{pane_current_path} propagate the dead dir into new panes.
#
# Loads first (sorts before 00-terminal.zsh, which reads $PWD for OSC 7) so
# everything after it sees a valid cwd. When PWD is still an absolute path we
# walk up to the nearest surviving ancestor, which keeps you next to the work
# you were doing; when getcwd() failed outright there is no path to walk, so
# $HOME is the only honest answer.
#
# This is defence in depth, NOT the primary fix. The usual cause is a tmux
# server whose own cwd was deleted, which makes it ignore `-c` and birth every
# pane in the dead path — that is fixed at source by __tmux_new_session
# (config/zsh/04-aliases.zsh) pinning new servers to $HOME. This guard only
# rescues a shell that was already sitting in a directory when it vanished.
# Two distinct broken states, and testing `-d $PWD` alone catches neither
# reliably: when getcwd() fails zsh sets PWD to "." — and `test -d .` still
# SUCCEEDS, because the process keeps a reference to the deleted directory's
# inode. So treat a non-absolute PWD as broken too.
if [[ $PWD != /* || ! -d $PWD ]]; then
  () {
    local d=$PWD
    # When getcwd() fails outright zsh reports PWD as "." — there is no path to
    # walk up, and ${d:h} of "." is "." (an infinite loop), so bail straight to
    # $HOME for anything that isn't absolute.
    [[ $d == /* ]] || d=$HOME
    while [[ $d != / && ! -d $d ]]; do d=${d:h}; done
    [[ -d $d ]] || d=$HOME
    builtin cd -q -- "$d" 2>/dev/null || builtin cd -q -- "$HOME"
    [[ -o interactive ]] && print -u2 "cwd was unavailable — moved to $PWD"
  }
fi
