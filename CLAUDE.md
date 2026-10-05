# dotfiles

- tmux status and title indicators: idle or ambient states are dim text, never emoji; emoji are only for states that need attention. Ambient markers go at the end of the bar, and never repeat what is already on screen (the alias shows only when it differs from the session name).
- dotfiles and muster each install and work without the other. When both need the same mechanism, implement it in each repo against a shared written contract; never make one shell out to the other.
