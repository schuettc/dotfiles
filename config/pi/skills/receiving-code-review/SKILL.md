---
name: receiving-code-review
description: Handles code review findings by verifying each against the code first, fixing those that show the approved behavior failing in real use, pushing back on wrong ones with evidence, and sending everything else to one-line follow-ups; the review is finished when the approved behavior works and nothing regressed. Use when a reviewer subagent, Court, or a PR comment returns findings, before changing any code.
---

# Receiving Code Review

Adapted from obra/superpowers (MIT) at 8ca22db; see config/pi/superpowers/.

## Overview

A review is evidence to check, not a list of orders. Verify each finding against the code before acting on it, then sort it.

**Core principle:** the ask defines done. A review is finished when the approved behavior works and nothing regressed (AGENTS.md "Stay on the ask"), not when a reviewer finds nothing.

## The Response Pattern

1. **Read** all the findings before acting on any.
2. **Understand** each one: restate it in your own words, or ask about it.
3. **Verify** it against the code: open the file and line, run the command, reproduce the case in a temp dir.
4. **Sort** it into one of the three outcomes below.
5. **Act** on the fixes one at a time, each with its test.
6. **Report** each finding's outcome in one line.

## Sort Each Finding

**Fix it:** the finding shows the approved behavior failing in real use (a reasonable person using what Court approved gets the wrong result, an error, or a regression of something that worked). Fix it under the test-driven-development skill: a test that reproduces the finding, watched failing, then passing, then the whole suite.

**Push back with evidence:** the finding is wrong for this codebase. Say why in one or two sentences and point at the proof (the line, the test, the command output, the spec section). Examples: the code path it describes isn't reachable; the build target makes the "legacy" code necessary; the spec chose this behavior.

**Follow-up line:** everything else. Style, naming, hypothetical cases, things nobody has hit, a reviewer's failing script for an input that hasn't happened, refactors, and improvements beyond the ask. Each gets one line in the report or an issue, and no code (AGENTS.md "Build for what has happened": a reviewer's or fuzzer's failing script hasn't happened).

A reviewer's severity label is advice. Grade a finding by what a person using the software gets if it ships.

## Is This Feature Actually Needed?

When a reviewer asks to "implement it properly" (metrics with date filters, a config option, full validation), first check whether anything uses it:

- `grep` the codebase for callers.
- Unused: "Nothing calls this endpoint. Remove it rather than build it out?" That question goes to Court if removing it changes what Court approved.
- Used: then the finding is about real behavior, so sort it as above.

Court's rule: the implementer and the reviewer both answer to Court. If we don't need the feature, don't add it.

## When the Review Is Finished

- The approved behavior works and nothing regressed: the review is finished, even if a reviewer would find more on another pass.
- A reviewer finding something new is not by itself a reason for another review pass. New findings get sorted like the rest; most become follow-up lines.
- A re-review, when you ask for one, looks at the fixes (the diff since the reviewed commit), not the whole change again.
- When fixes keep surfacing new problems, or the change goes past what was approved, stop and bring Court what was added (AGENTS.md "Stop when it grows").

## Unclear Findings

If any finding is unclear, ask about it before implementing any of them: findings are often related, and partial understanding produces the wrong fix.

```
Court: "Fix 1-6"
You understand 1, 2, 3 and 6; 4 and 5 are unclear.

Wrong: fix 1, 2, 3 and 6 now and ask about 4 and 5 later.
Right: "I understand 1, 2, 3 and 6. What do you mean by 4 and 5?"
```

## By Source

**From Court:** trusted. Implement after understanding, and still ask when the scope is unclear. A finding from Court that goes beyond what Court approved is a new ask: say what it adds and confirm before building it.

**From a reviewer subagent or an external reviewer:** check before acting.
- Is it correct for this codebase, stack and platform?
- Would the change break something that works?
- Is there a reason for the current code (a spec decision, a compatibility constraint)?
- Does the reviewer have the full context (the spec, the plan's rulings)?
- If it conflicts with a decision Court made, bring it to Court rather than act on it.
- If you can't verify it, say so: "I can't verify this without X. Should I look into it, or leave it as a follow-up?"

## How to Respond

State the fix or the evidence, not a reaction. No "You're absolutely right!", "Great point!" or thanks: the change in the code shows you heard it.

```
Good: "Fixed: empty input now returns the 'Email required' error (test_rejects_empty_email)."
Good: "Not changed: the build target is macOS 10.15, and this API needs 13. The legacy path stays."
Good: "Follow-up: retry on 503 has not happened yet; noted in the report."
Bad:  "You're absolutely right! Let me fix that..."
```

If you pushed back and were wrong, say so plainly and fix it: "Checked: you're right, X does Y. Fixing." No long apology and no defence of the pushback.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Fixing before verifying | Check each finding against the code first |
| Fixing everything the reviewer listed | Fix only what breaks the approved behavior; the rest is follow-ups |
| Another review pass because the last one found something | The review is finished when the approved behavior works and nothing regressed |
| Re-reviewing the whole change | A re-review looks at the fixes |
| Building out a feature nobody uses | grep for usage first |
| Accepting a wrong finding to avoid friction | Push back with the evidence |
| Fixing several findings, then testing | One at a time, each with its test |
| Proceeding on a finding you can't verify | Say what you'd need, and ask |

## Examples

**Wrong finding, pushed back:**
```
Reviewer: "Remove the legacy code path."
You: "Checked: the build target is 10.15+, and the replacement API needs 13+. The legacy path stays."
```

**Unused feature:**
```
Reviewer: "Implement proper metrics tracking with a database, date filters and CSV export."
You: "Grepped: nothing calls this endpoint. Remove it rather than build it out? Or is there a caller I'm missing?"
```

**Hypothetical case:**
```
Reviewer: "This parser will fail on input with a BOM."
You: "No input with a BOM has reached it; follow-up noted in the report."
```

## GitHub Thread Replies

When replying to inline review comments on GitHub, reply in the comment thread (`gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`), not as a top-level PR comment. Write the body to a file rather than putting it inline in the shell command (AGENTS.md "Running work").
