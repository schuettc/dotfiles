---
name: pi-subagent-dispatch
description: Use when dispatching subagents from a pi session on this machine (Agent tool) — implementers, reviewers, or any child model call — to pick the model and provider, or when a dispatch fails (expired OpenAI login, extra-usage 400, prompt-capture error, tool-schema `minimum` rejection).
---

# Dispatching pi subagents (this machine)

Verified 2026-10-04 on pi 1.0.1, `@tintinweb/pi-subagents` 0.19.0, `@schuettc/pi-claude-bridge` 0.9.1-schuettc.2.

## Choosing the model

The session's model is the subscription in use. When one runs out, Court switches the session
(`/claude-account`, `/model`) and subagents follow. The `worker` and `reviewer` agent files carry
**no `model:` or `isolated:` lines**, so the dispatch decides. (Frontmatter is authoritative in
pi-subagents: a pinned field can't be overridden at dispatch.)

| Role | Model |
|---|---|
| `worker` (implementer) | omit `model`: it inherits the session model (Opus). Routine work: pass Sonnet on the same provider, e.g. `claude-bridge/claude-sonnet-5-5` |
| `reviewer` | the **other provider family** from the implementer. Anthropic work → `openai/gpt-6.1-sol` or `openai/gpt-6-astra`. OpenAI work → `claude-bridge/claude-opus-5-5` |
| Security review or question | prefer OpenAI (`openai/gpt-6.1-sol` / `openai/gpt-6-astra`); otherwise the normal other-family rule |
| Mechanical, scoped re-review | `claude-bridge/claude-haiku-4-5`, still from the other family when the work is OpenAI's |

Providers: `claude-bridge/*` bills the bridge's active account (switch with `/claude-account`);
`anthropic/*` bills pi's own login (`~/.pi/agent/auth.json`); `openai/*` is Court's OpenAI
subscription (OAuth). Prefer Anthropic; use OpenAI when Anthropic usage is exhausted, and for
reviews.

Dispatch with `isolated: false` (the default). Name the brief and report files in the prompt.

## Failure signatures

| Signature | Cause | Fix |
|---|---|---|
| `OAuth refresh failed for openai … refresh_token_invalidated` | Court's OpenAI login has expired | Stop and ask Court to `/login` → OpenAI, then re-dispatch. Never substitute an Anthropic reviewer for an OpenAI one |
| `400 Third-party apps now draw from your extra usage...` | Server-side classifier keys on pi's harness block in a child's system prompt; built-in `general-purpose` children carry it | Use a custom agent (`worker`, `reviewer`, or a `.pi/agents/*.md`) with its own lean prompt, never `general-purpose` |
| `prompt-capture: no capture for this N-char system prompt` | Seen 2026-08/09 with `claude-bridge/*` children dispatched `isolated: true` | Dispatch bridge children with `isolated: false` |
| `400 tools.N.custom: For 'number' type, property 'minimum' is not supported` | A tool schema uses JSON-Schema `minimum`, which the direct `anthropic/*` API rejects | Prefer `claude-bridge/*`; if `anthropic/*` is required, dispatch `isolated: true` |
| `Cannot find module .../dist/bundle/chunks/<provider>-*.js` (e.g. `openai-responses-*`, `anthropic-messages-*`) | The session started before a pi upgrade and never loaded that provider's code; the upgrade replaced the files. Providers already used in the session keep working | Restart pi (resume the session). Check with a fresh `pi -p --no-session --model <m> ...` |

## Smoke test

After a harness change, dispatch each model you plan to use with the prompt
"Reply with exactly the word: ready" and `max_turns: 1`. (A `worker` may answer
`NEEDS_CONTEXT` instead: it wants a brief. That still proves the model runs.)
Outside a session: `pi -p --no-session --model <provider/model> "Reply with exactly the word: ready"`.
