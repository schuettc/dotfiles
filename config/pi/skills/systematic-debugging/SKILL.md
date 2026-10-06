---
name: systematic-debugging
description: Finds the root cause of a bug before fixing it, in four phases (root cause investigation from real logs and state, pattern analysis against working code, one hypothesis at a time, a fix at the cause backed by a reproducing test), reproducing only in throwaway clones or temp dirs. Use when hitting any bug, test failure, build failure or unexpected behavior, before proposing a fix.
---

# Systematic Debugging

Adapted from obra/superpowers (MIT) at 8ca22db; see config/pi/superpowers/.

## Overview

Find the root cause before attempting a fix. A fix aimed at the symptom usually moves the failure somewhere else, and each guess that half-works makes the next one harder to read.

Propose a fix only after Phase 1 has told you what is failing and why. This holds for simple-looking bugs too: they have root causes, and finding them is quick. It holds most of all when a quick fix looks obvious, when a previous fix didn't work, or when you don't fully understand the issue.

Nothing is urgent (AGENTS.md "Asking and explaining"). Say "I don't know yet" rather than guess a cause.

## Where to Investigate and Reproduce

- **Gather real logs and state first.** Reading is always allowed (AGENTS.md "Running work"): logs, CI output (`gh run view <id> --log-failed`), the live store, `git log`, config files, process state. Collect them without asking. Mutations stay one explicit step at a time.
- **Reproduce somewhere disposable.** Run reproductions in a throwaway clone or a temp dir (`mktemp -d`), never against a real or shared repo or a live system. A test run under a git hook once wrote junk into a shared `.git/config`: a script that runs git in a temp repo unsets the `GIT_*` environment variables first and asserts `git rev-parse --git-dir` is inside its temp dir (AGENTS.md "Git").
- **Check siblings and history.** Before fixing, check how sibling repos solve the same thing and whether the failing path is live or legacy. Check whether something already shipped resolves the cause on its own; if so, say so and let Court choose (AGENTS.md "Verifying").

## The Four Phases

Finish each phase before starting the next.

### Phase 1: Root Cause Investigation

1. **Read the error messages carefully.** Read stack traces to the end, and note line numbers, file paths and error codes. Errors and warnings often name the exact cause.
2. **Reproduce it consistently.** Find the exact steps, in a disposable location, and check whether it happens every time. If it doesn't reproduce, gather more data rather than guess.
3. **Check recent changes.** `git diff`, recent commits, new dependencies, config changes, environment differences between where it works and where it doesn't.
4. **Gather evidence across component boundaries.** When the system has several components (CI → build → signing, API → service → database), find out which boundary breaks before proposing anything. For each boundary, log what enters and what leaves, and check that environment and config propagate. Run once, read where it breaks, then investigate that component.

   ```bash
   # Layer 1: workflow
   echo "IDENTITY: ${IDENTITY:+SET}${IDENTITY:-UNSET}"
   # Layer 2: build script
   env | grep IDENTITY || echo "IDENTITY not in environment"
   # Layer 3: signing
   security find-identity -v
   codesign --sign "$IDENTITY" --verbose=4 "$APP"
   ```

   This shows which layer fails (secrets reach the workflow, but not the build).
5. **Trace the data flow.** When the error is deep in a call stack, trace the bad value backwards to where it originated and fix it there. See [root-cause-tracing.md](root-cause-tracing.md).

Before reporting that something is missing or wrong, query the underlying source rather than a summary, prove the query can see a case you know exists, and test the boring explanations first (AGENTS.md "Verifying").

### Phase 2: Pattern Analysis

1. **Find working examples.** Locate similar code that works, in this repo or a sibling.
2. **Read the reference completely.** If you are applying a pattern, read the reference implementation all the way through; a skimmed pattern gets applied wrong.
3. **List the differences.** Every difference between the working and the broken case, however small. Don't assume one can't matter.
4. **Understand the dependencies.** Which components, settings, config and environment does it need, and what does it assume?

### Phase 3: One Hypothesis at a Time

1. **State one hypothesis.** "I think X is the root cause because Y." Write it down and make it specific.
2. **Test it with the smallest change.** One variable at a time, in the disposable reproduction. Changing several things at once means you can't tell which one mattered.
3. **Read the result.** Confirmed: go to Phase 4. Not confirmed: form a new hypothesis from what you learned, and undo the change rather than stacking another on top.
4. **When you don't know,** say "I don't understand X yet" and gather more evidence or ask Court one specific question.

### Phase 4: Fix the Cause

1. **Write a failing test that reproduces the failure actually seen,** using the test-driven-development skill. The simplest reproduction: an automated test where the repo has a framework, a one-off script in a temp dir where it doesn't. Watch it fail for the same reason the bug did.
2. **Make one fix at the root cause.** No "while I'm here" improvements and no bundled refactoring; those go in a one-line follow-up.
3. **Verify.** The reproducing test passes, the whole suite passes by its exit code, and the original symptom is gone where it was seen. For anything that touches an external system, that means a live run reaches it.
4. **If the fix doesn't work,** go back to Phase 1 with what you learned.
5. **When two or three fixes in a row each surface a new error,** the model of the problem is wrong (AGENTS.md "Verifying"). Stop fixing and bring it to Court: what you found, what each fix revealed, and the question it raises about the design (shared state, coupling, a pattern that doesn't fit). Each fix revealing a new problem in a different place is a sign of a wrong design, not a run of failed hypotheses.

## Signs You've Skipped Ahead

These thoughts mean go back to Phase 1:

- "Quick fix for now, investigate later."
- "Just try changing X and see if it works."
- "Change several things, then run the tests."
- "Skip the test, I'll check it by hand."
- "It's probably X, let me fix that."
- "I don't fully understand, but this might work."
- Listing fixes before tracing the data flow.
- Reaching for one more fix after the last ones each surfaced something new.

Court's questions are signals too: "Is that actually happening?" means you assumed without verifying; "Will it show us...?" means gather evidence first; "Stop guessing" means you proposed a fix without understanding; "We're stuck?" means the approach isn't working. Go back to Phase 1.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "The issue is simple, I don't need the process" | Simple issues have root causes too, and the process is quick for them. |
| "Just try this first, then investigate" | The first fix sets the pattern. Investigate first. |
| "I'll write the test after confirming the fix" | A test written after passes at once and proves nothing about the bug. |
| "Several fixes at once saves time" | You can't tell which one worked, and you add new bugs. |
| "I'll reproduce it here, it's quicker" | Reproduce in a temp dir or throwaway clone; the real repo is not a test bench. |
| "I see the problem, let me fix it" | Seeing the symptom is not understanding the cause. |
| "One more fix will do it" | After fixes that each surface something new, the model is wrong. Bring it to Court. |
| "I'll add guards everywhere so it can't happen again" | Guard the path the bad value actually took; anything more is a follow-up (see defense-in-depth.md). |

## Quick Reference

| Phase | What you do | Done when |
|-------|-------------|-----------|
| **1. Root cause** | Read errors, reproduce in a temp dir, check changes, gather evidence | You know what fails and why |
| **2. Pattern** | Find working examples, compare | You've listed the differences |
| **3. Hypothesis** | One theory, smallest test | Confirmed, or a new hypothesis |
| **4. Fix** | Reproducing test, one fix, verify | The bug is gone and the suite is green |

## When the Cause Is Outside the Code

If investigation shows the cause is environmental, timing-dependent or external: write down what you investigated and what you found, and bring Court the options (handle it with a retry, timeout or clearer error; fix it at its source elsewhere; leave it). Most "no root cause" findings are incomplete investigations, so check Phase 1 was finished first.

## Supporting Files

- [root-cause-tracing.md](root-cause-tracing.md): trace a bug backwards through the call stack to its original trigger.
- [defense-in-depth.md](defense-in-depth.md): after finding the cause, decide which layers the bad value passed through deserve a check.
- [condition-based-waiting.md](condition-based-waiting.md): replace guessed sleeps in flaky tests with waits on the actual condition.
- [find-polluter.sh](find-polluter.sh): run test files one by one to find which one leaves a file or directory behind.
