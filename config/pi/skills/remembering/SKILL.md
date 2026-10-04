---
name: remembering
description: Use when Court says "remember this", "note that", "from now on", or "always/never do X", or when a session learns a lesson, decision or fact worth keeping beyond this session. There is no memory store; this skill says which file it belongs in and how to propose the edit.
---

# Remembering

There is no memory store. Things worth keeping live in the file that owns them, where they are
read in full, versioned, and reviewable. Your job is to find that file and propose the edit.

## Where it goes

| What | File |
|---|---|
| How Court works, true in every project (communication, engineering approach, git habits, model routing) | `~/.pi/agent/AGENTS.md` (repo `~/GitHub/schuettc/dotfiles-private`, file `pi/AGENTS.md`; private) |
| A rule or lesson for one repo or workspace | that repo's `CLAUDE.md` (or `AGENTS.md` if that's what it uses) |
| A rule every live session in a project must follow now | a muster standing order for that project (`muster standing set`) |
| Project knowledge: strategy, data quirks, how a system behaves | a doc in that project's repo, next to the docs it relates to |
| A design decision | the project's spec or plan doc (public repos: `tools-ops/docs/<repo>/specs/`, never committed in the public repo) |
| Something to do later | a GitHub issue in the owning repo |
| Status of work in flight | nowhere new: muster threads, casebook, plan files and PRs already hold it |
| How to do a recurring task | a skill (`~/dotfiles/config/pi/skills/` if public, a repo's `.claude/skills/` if project-specific) |

If it fits more than one row, choose the narrowest scope it is true for. Never put project facts
in the global `AGENTS.md`.

## How

1. Read the target file first. If it already says this, or says something that conflicts with it,
   point that out instead of adding a second copy.
2. Write the smallest edit: one rule in plain language, in the file's existing section and style.
   Rules, not history: no dates, PR numbers or "as of" notes unless the rule depends on them.
3. Show Court the edit as a diff (or open the file in galley for a longer change) and wait for
   approval. Never edit `AGENTS.md` or a `CLAUDE.md` without it.
4. Commit it the way that repo works (a PR in repos that use them). For `dotfiles-private`,
   commit and push directly.
