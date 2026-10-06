---
name: executing-plans
description: Executes an approved implementation plan by dispatching one worker subagent for the whole plan, a fresh worker per task for a large plan, or working inline when the plan is small, then ends with a final review by a reviewer from the other provider family whose findings are handled per receiving-code-review. Use when Court has approved a plan from writing-plans, or any written plan, and it is time to implement it.
---

# Executing Plans

Adapted from obra/superpowers (MIT) at 8ca22db; see config/pi/superpowers/.

Execute the whole plan without a reviewer per task. At the end, a reviewer from the other provider family reviews the whole change with fresh context, and its findings are handled per the receiving-code-review skill: the run is finished when the approved behavior works and nothing regressed.

**Core principle:** The plan already did the thinking. Execute it exactly, prove each step with a test you watched fail and then pass, and leave a record that survives forgetting.

**Continuous execution:** Do not pause to check in with Court between tasks. Execute all tasks from the plan without stopping.

**Rulings, not stalls.** Ordinary conflicts, ambiguities and small plan defects: decide them. The spec is the binding authority, the plan is its argument, and judgment settles what neither answers. Record every decision in the report as `Ruling: <what was decided> — <why> — <what it costs if wrong>`, and keep going. Deviating from the plan without a recorded ruling is a decision made in secret.

Stop and bring it to Court for: an irreversible or destructive operation; a security-sensitive action; a side effect outside the worktree that AGENTS.md says to ask about first (a merge, a publish); a genuine design choice between correct approaches that is Court's to make; a finding that makes the accepted plan wrong; and the change growing past its size (see "Stop when it grows"). For those, stop and bring it to Court.

## Choose who implements

- **One `worker` subagent for the whole plan (default).** The main session stays responsive: dispatch it and keep talking with Court while it runs. Pick the model with the `pi-subagent-dispatch` skill (`worker` inherits the session model; routine work may run on Sonnet on the same provider).
- **Inline, in this session,** when the plan is small: a single task or roughly 100 lines of change, or judgment-heavy work that needs Court in the loop.
- **Large-plan mode: a fresh `worker` per task,** when the plan has many independent tasks and one worker would carry too much context through them. Each task starts clean; the main session runs each task's own checks between tasks.

Tasks build their tests per the test-driven-development skill: one failing test per behavior the plan asks for, watched failing, then passing.

## Setup

1. Work in a worktree on a branch cut from a freshly fetched base, per AGENTS.md's Git rules. Confirm it with `git -C <wt> branch --show-current` before anyone writes to it. Never implement on `main` without Court's explicit consent.
2. Read the plan once, note its Size line, Global Constraints and Review Focus. If the plan names a Spec, read that too: conflicts inside the plan resolve against it. A plan with no reachable spec gets a report note saying so; rulings made without one are provisional.
3. Record the base commit: `BASE=$(git -C <wt> rev-parse HEAD)`; the commands below use `$BASE`.
4. Pick a run directory outside the repo: `${XDG_STATE_HOME:-$HOME/.local/state}/plans/<plan-basename>/`. The report (`report.md`) and the review package live there, never in the repo.

## Run it: worker

Dispatch one `worker` with a short prompt naming: the plan file as its brief, the spec path, the worktree path (it works and commits only there), the report path, and these instructions:

- Work the plan's tasks in order under the test-driven-development skill: write the test, watch it fail, implement, watch it pass, and compare every `Expected:` line against real output.
- Commit as the plan's commit steps say.
- Put every deviation from the plan in the report as a `Ruling:` line, and one line per finished task with its commits and test result.
- Stop and return `BLOCKED` with the size so far if the change passes about twice the plan's Size line, or the work needs files or features the plan doesn't name.

While it runs, don't commit in that worktree. When it returns, read the report, then check the size: `git -C <wt> diff --stat "$BASE"...HEAD`.

A `NEEDS_CONTEXT` return is a ruling for you to make with the spec as the authority (record it in the report and re-dispatch with the answer), unless it is a scope question: that goes to Court.

## Run it: large-plan mode

Dispatch one fresh `worker` per task, in order, never in parallel (they share the worktree). No context builds up across tasks, and there is no reviewer model per task.

1. **Brief.** Copy the task's full text into `<run-dir>/task-<N>-brief.md`, with the plan's Global Constraints and the Interfaces it consumes from earlier tasks. The worker reads that file, not the whole plan. Don't paste earlier tasks' history into the dispatch.
2. **Dispatch** with the brief path, the spec path, the worktree, the report path `<run-dir>/task-<N>-report.md`, and the worker instructions above (the size stop applies to the task's share of the plan).
3. **Check it yourself.** When the worker returns, run the task's own check commands from the plan in the worktree and read their exit codes (AGENTS.md "Verifying"); a worker's "tests pass" is not the check. Only when every check passes, append the task line to `<run-dir>/report.md`: `Task <N>: complete (commits <base7>..<head7>, checks: <command> → exit <code>)`. A task with a failing check gets no line, so a resume picks it up again.
4. **A check fails:** re-dispatch a worker on that task with the failing command and its output. When fixes keep surfacing new failures, stop and bring it to Court (AGENTS.md "Stop when it grows").

After compaction, trust `report.md` and `git log`: resume at the first task without a line.

## Run it: inline

Work the plan's steps in order under the test-driven-development skill, as above. Every step that runs a command has an `Expected:` line: run it, read the output, compare. Three outcomes:

- **Matches.** Next step.
- **The code is wrong.** Find the cause; never patch the symptom to make the step's output match. If two or three fixes in a row each surface a new error, the model of the problem is wrong: stop and bring it to Court.
- **The plan is wrong** (a step contradicts the spec, an interface from an earlier task doesn't match, a command that cannot work). Rule on the smallest change that satisfies the spec, record the ruling in the report, and continue.

After each task, append one line to the report: `Task <N>: complete (commits <base7>..<head7>, tests: <command> → <result>)`, in the same tool call as the commit. Conversation memory does not survive compaction: after compaction, trust the report and `git log` over recollection, and resume at the first task without a line.

Redirect long test output to a file in the run directory and read its tail.

## Stop when it grows

At about twice the plan's Size line, fixes that keep surfacing new problems, or a worker that went past its brief (files or features the plan doesn't name), stop (AGENTS.md "Stop when it grows"). Bring Court the size against the plan and what was added. A scope change is never your call.

## Final Review

Build the package in the run directory:

```bash
{ git -C <wt> log --oneline "$BASE"..HEAD; git -C <wt> diff "$BASE"...HEAD; } > <run-dir>/review-package.diff
```

Both modes end here. Dispatch a `reviewer` from the other provider family from the implementer (the `pi-subagent-dispatch` skill names the models; never substitute a same-family reviewer). Its three files are the plan (as the brief), the report, and the package. In the prompt, add the spec path, the plan's Review Focus section verbatim (the reviewer checks each line deliberately), and a pointer to the report's `Ruling:` lines so it can weigh the calls made. This is the one fresh-context review the run buys; don't skip it or replace it with your own read of the diff.

Handle the findings with the [receiving-code-review](../receiving-code-review/SKILL.md) skill: verify each against the code before acting, then sort it. The reviewer's severity labels are advice; grade a finding by what a reasonable person using this software gets if it ships. Its "Cannot verify from diff" list is yours too: each line becomes a ruling or a finding.

- **Shows the approved behavior failing in real use:** fix it. Re-dispatch the worker with these findings as its brief, or fix inline when they are small. Each fix is a test that reproduces the finding, watched failing, then passing, then the whole suite. Record each as `Final: fixed <finding> — <test name> RED→GREEN, suite <N>/<N>`.
- **Wrong:** push back with evidence, recorded as `Final: Ruling: <finding> — <why the code stands> — <cost if wrong>`.
- **Everything else** (style, hypothetical cases, things nobody has hit, improvements beyond the ask): the report as `Final: follow-up: <one-liner>` and your final message under "Follow-ups".

The review is finished when the approved behavior works and nothing regressed. A reviewer finding something new is not by itself a reason for another review; if you ask for a re-review, it looks at the fix commits, not the whole change again.

## Finish

Push the branch and open a PR against its base with `gh pr create --body-file`, per AGENTS.md's Git rules (in visual/UX rounds, wait for Court to say the round is done). Don't merge.

Your final message to Court carries, from the report: the size against the plan's Size line, every `Ruling:` line in order with its cost if wrong under "Rulings I made", and every follow-up under "Follow-ups". Both lists are exhaustive: your final message is the only place the decisions made on Court's behalf reach Court.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "The plan's code is right, skip watching the test fail" | A test you never saw fail proves nothing. It is one step. Run it. |
| "The plan is wrong here, I'll just do the right thing" | Do the right thing and record the ruling. Unrecorded deviation is a decision made in secret. |
| "Let me check in before the next task" | Only the five stops stop you. |
| "The worker said the task's tests pass" | In large-plan mode you run the task's check commands and read the exit code yourself. |
| "It's only a bit past the plan, I'll finish it" | Twice the Size line is the stop. Bring Court the size and what was added. |
| "I read the diff carefully; the final reviewer is redundant" | Same author, same blind spots. The reviewer is the only fresh context this run buys. |
| "Tests should pass, the change was trivial" | "Should" is not evidence. The report needs the command and its output. |
| "The reviewer said Minor, so it's Minor" | Grade what the person gets. Re-grade, then sort. |
| "The reviewer found more, so review again" | The review is finished when the approved behavior works and nothing regressed. New findings get sorted like the rest. |
| "The fix is obvious, no need for a failing test first" | The failing test is the only proof the finding was real and is now gone. |
| "I'll fix the follow-ups too while I'm in there" | Every follow-up fixed is work Court did not ask for. Record them; Court decides. |

## Example Workflow

```
You: I'm using the executing-plans skill. The plan is 3 tasks, about 250 lines, so I'm dispatching one worker.

[Worktree /tmp/feat-x on feat/x, confirmed; BASE a1b2c3d]
[Run dir ~/.local/state/plans/2026-10-05-feat-x/]
[Dispatch worker (session model) with plan, spec, worktree, report path]
[Keep talking with Court while it runs]
[Worker returns DONE: commits d4e5f6a, b7c8d9e, c0d1e2f; 14/14 tests pass; one Ruling: install_hook → installHook (matches Task 1 Produces; cost if wrong: one rename)]
[git diff --stat: 270 lines against a Size of 250: within plan]
[Build review package; dispatch reviewer on openai-codex/gpt-6.1-sol]
Reviewer: One Important finding (progress interval hardcoded). Two Minor.
[Verify each: the hardcoded interval breaks the configured value Court approved → fix; the two minors → follow-ups]
[Fix inline: test_progress_interval_configurable RED → GREEN; suite 15/15; commit. Approved behavior works: review finished]
[Push; gh pr create --body-file]

Size: 285 lines against a planned 250.
Rulings I made:
- Task 2: install_hook → installHook (plan typo; cost if wrong: one rename)
Follow-ups:
- README lacks a usage example
- recovery.js could split verify/repair into two files
```
