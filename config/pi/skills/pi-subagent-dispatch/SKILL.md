---
name: pi-subagent-dispatch
description: Use when dispatching subagents from a pi session on this machine (Agent tool) — implementers, reviewers, or any child model call — or when a dispatch fails with an extra-usage 400, a prompt-capture error, or a tool-schema `minimum` rejection. Contains the one working recipe and the failure-signature table.
---

# Dispatching pi subagents (this machine)

Verified 2026-08-28 against pi + pi-claude-bridge. Re-verify the failure rows before trusting them after a bridge or pi upgrade.

## The one working recipe

Dispatch children as a **custom agent** + **`isolated: true`** + a **direct-API model**:

```
subagent_type: worker        (or reviewer, or any .pi/agents/*.md agent)
isolated: true
model: anthropic/claude-opus-4-8 | anthropic/claude-sonnet-4-6 | anthropic/claude-haiku-4-5
```

- Custom agents live in `<project>/.pi/agents/<name>.md` (frontmatter: name, description, tools; body = system prompt). tools-workspace ships `worker` (implementer contract: brief file in → report file out) and `reviewer` (read-only, dual verdict). Copy them into other projects as needed.
- Keep the agent's system prompt LEAN and self-authored. That is not a style preference — it is the load-bearing fix (see below).
- Model tiering: implementers on `anthropic/claude-opus-4-8`, task reviewers `anthropic/claude-sonnet-4-6`, mechanical/scoped re-reviews `anthropic/claude-haiku-4-5`. The `anthropic/` (direct API) provider carries the full lineup INCLUDING opus-4-8, opus-5 and fable-5 — do not assume a model is bridge-only because the bridge lists it. Passing a bogus model id errors with the complete provider/model catalog: cheapest way to enumerate what's available.

## Why: the three failure modes

| Signature | Cause | Fix |
|---|---|---|
| `400 Third-party apps now draw from your extra usage...` (also: `You're out of extra usage`) | Server-side classifier keys on **pi's harness block inside the child's system prompt** — content-dependent, not subagent-dependent (full bisection: `pi-claude-bridge/diag/EXTRA-USAGE-400.md`). Built-in `general-purpose` children carry that block and always trip it; parent-session turns and lean-prompt children pass on plan billing. | Custom agent with its own lean prompt (or Explore). Never `general-purpose` while this classifier stands. |
| `prompt-capture: no capture for this N-char system prompt` | pi-claude-bridge cannot match child system prompts to a capture and fails the turn **even after the model answers**. Affects every `claude-bridge/*` model as a child (opus-4-8, fable-5, ...). | No bridge models for children. Bridge = parent session only. Bug worth its own session; do not chase mid-plan. |
| `400 tools.N.custom: For 'number' type, property 'minimum' is not supported` | An extension/MCP tool schema (e.g. Agent's `max_turns`) uses JSON-Schema `minimum`, which the direct Anthropic API rejects. | `isolated: true` — drops extension/MCP tools from the child. Children doing file/test work only need builtins anyway. |

## Notes

- Bridge models (`claude-bridge/*`) remain unusable for children regardless of model; the same model ids on `anthropic/*` work. Verified direct: opus-4-8, opus-4-7, sonnet-4-6, haiku-4-5.
- `isolated` children have no muster/memory/channel tools — hand them everything as file paths in the dispatch prompt (briefs, report paths, diff packages).
- Smoke-test after any harness change: dispatch `worker`, `isolated: true`, prompt "Reply with exactly the word: ready", `max_turns: 1`, on each tier you plan to use.
