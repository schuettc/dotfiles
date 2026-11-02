# Cursor Agent + muster — peer workflow

Cursor Agent is a peer coding agent on the local [muster](https://github.com/schuettc/muster)
bus. Unlike Codex, it is not bridged into Claude Code: run it in its own tmux
workspace and let both agents coordinate directly through muster.

## Install and sign in

This repo's kempt manifest does not select Cursor. To use it, install the
Cursor CLI yourself (`brew install --cask cursor-cli`) and sign in with your
Cursor subscription when `cursor-agent` (or its `agent` alias) prompts you.
Then, with muster installed, wire Cursor onto the bus with muster's own
direct setup (`--force` because kempt manages the rest of muster's setup):

```bash
muster setup --force --agent cursor
```

That:

- registers `~/.local/bin/muster mcp` in `~/.cursor/mcp.json`;
- enables the `muster` MCP server in the Cursor CLI;
- writes Cursor `sessionStart`, `stop`, and `sessionEnd` hooks to
  `~/.cursor/hooks.json`; and
- allowlists `Mcp(muster:*)` in `~/.cursor/cli-config.json`, so the Stop-hook
  inbox drain is not paused for a permission prompt.

## Start a peer workspace

```bash
proj --cursor
# or:
pt --cursor my-project
```

The left pane starts `cursor-agent --trust --approve-mcps` (falling back to
`agent`). Cursor auto-registers on the muster bus through its session hooks,
then can use muster MCP tools to message agents, claim tasks, and drain its
inbox.

## tmux notes

- `prefix T` sets the tmux and muster task label for every agent, and types
  `/rename <label>` into a live Claude or Cursor pane so the harness session
  name follows. Codex has no `/rename`, so it only gets the tmux/bus label.
- `prefix m` nudges the selected agent to drain its muster inbox and
  auto-submits for Claude, Codex, and Cursor.
