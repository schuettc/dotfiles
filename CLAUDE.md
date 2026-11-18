# dotfiles

- tmux status and title indicators: idle or ambient states are dim text, never emoji; emoji are only for states that need attention. Ambient markers go at the end of the bar, and never repeat what is already on screen (the alias shows only when it differs from the session name).
- dotfiles and muster each install and work without the other. When both need the same mechanism, implement it in each repo against a shared written contract; never make one shell out to the other.
- This repo is a user layer on the subaud starter (`subaud-tools/starter`). What the starter carries (pi and its base extensions, nvim, Ghostty and yazi base configs, the agents, the process skills, the suite tools) is changed there, never copied here.
