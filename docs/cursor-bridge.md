# Cursor Agent + muster — peer workflow

Cursor Agent is a peer coding agent on the local [muster](https://github.com/schuettc/muster)
bus. Unlike Codex, it is not bridged into Claude Code: run it in its own tmux
workspace and let both agents coordinate directly through muster.

## Install and sign in

Install the `cursor` and `muster` packages (with their dependencies):

```bash
bash packages/run.sh core cursor muster
```

`packages/cursor` installs the `cursor-cli` cask. Sign in with your Cursor
subscription when `cursor-agent` (or its `agent` alias) prompts you.

When muster builds successfully and Cursor is present, it automatically:

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
