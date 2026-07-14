# Claude Code + Codex (GPT) — the bridge

Claude Code is the home base. OpenAI's Codex CLI is wired in so you can pull GPT
into the loop for a second opinion, a fast first draft, or an independent
cross-check — **without leaving Claude Code and without a metered API key.**

## The one thing to understand

ChatGPT subscriptions and the OpenAI API are separate wallets. This setup runs
Codex on your **ChatGPT subscription** (`codex login`, browser OAuth), the same
flat-rate plan you use in the ChatGPT app — *not* usage-based API billing. The
MCP bridge shells out to your logged-in `codex` CLI, so Claude's delegated calls
bill against the subscription too.

## One-time setup

```bash
brew bundle --file=~/dotfiles/Brewfile   # installs cask "codex" (or: brew install --cask codex)
codex login                              # browser sign-in with your ChatGPT plan
codex login status                       # → should print your account, "logged in"
```

`install.sh` already registers the MCP bridge. To do it by hand / re-verify:

```bash
claude mcp add codex -s user -- codex mcp-server   # idempotent; user scope = all projects
claude mcp list                                    # look for: codex … ✔ Connected
```

Requires an active ChatGPT plan — **Plus ($20/mo)** includes Codex CLI; bump to
**Pro ($100/mo)** only if you hit the 5-hour rolling usage caps.

## Two ways to use it

### 1. Delegate from inside Claude Code (MCP bridge)

Once registered, Claude Code has a `codex` tool. You drive Claude as usual and
ask it to hand specific work to GPT. Claude plans/orchestrates; Codex executes
in a sandboxed pass and reports back. Good prompts:

- "Use the codex tool to get a second opinion on this function's edge cases."
- "Have codex draft the first version of this parser, then you review and
  integrate it."
- "Ask codex to independently find the bug, then compare with your diagnosis."

The bridge exposes two underlying tools: `codex` (a fresh task) and
`codex-reply` (continues the same Codex thread, preserving its context).

### 2. Standalone Codex in its own tab

For a fully independent pass, run `codex` directly in a second terminal
(`⌘T` gets you a new workspace tab). Point both agents at the same tricky task:

- **They agree** → high confidence, move on.
- **They diverge** → the disagreement is the signal; that's where your judgment
  goes.

Handy standalone forms:

```bash
codex                       # interactive TUI
codex exec "…"              # one-shot, non-interactive (scriptable / CI)
codex review                # non-interactive code review of the working tree
```

## Which tool for which job

| Want… | Reach for |
|---|---|
| Deep reasoning, large delegated runs, tight repo integration | **Claude Code** (primary) |
| Fast first draft, token-efficient scaffolds, headless/CI runs | **Codex** (`codex exec`) |
| A second opinion mid-task | Claude Code → **`codex` MCP tool** |
| Independent cross-check on security-sensitive / subtle work | **Both**, side by side, compare |

## Troubleshooting

- **`codex … ✘ Failed to connect`** in `claude mcp list` → make sure `codex` is
  on PATH (`which codex`) and re-run the `claude mcp add` line above.
- **Delegated calls fail / "not authenticated"** → the MCP server starts fine
  without login, but calls need it: run `codex login`, confirm with
  `codex login status`.
- **Rate-limited** → Codex enforces soft/hard caps per rolling 5-hour window on
  Plus; wait out the window or upgrade to Pro.
- **Remove the bridge** → `claude mcp remove codex -s user`.

## Deliberately not done

Routing GPT in as Claude Code's *underlying model* (via a LiteLLM proxy +
`ANTHROPIC_BASE_URL`) was considered and skipped: it needs a metered OpenAI API
key, loses Claude's harness tuning, and carries a supply-chain caveat (LiteLLM
PyPI 1.82.7/1.82.8 shipped credential-stealing malware). The MCP bridge gets the
"combine both" benefit on subscription billing instead.
