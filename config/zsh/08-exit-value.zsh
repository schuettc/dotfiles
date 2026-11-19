# Print a failed command's exit code ("zsh: exit N"), so an agent that quits
# with an error leaves its code in the pane (diazo 2026-11-18-recover-crashed-session).
setopt PRINT_EXIT_VALUE
