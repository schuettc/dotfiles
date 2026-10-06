---
name: writing-plans
description: Writes an implementation plan from an approved spec or requirements, stating the smallest change that does the ask and its rough size in lines, with tasks only as fine as one implementer needs, then hands off to executing-plans. Use when you have a spec or requirements for a multi-step task, before touching code.
---

# Writing Plans

Adapted from obra/superpowers (MIT) at 8ca22db; see config/pi/superpowers/.

## Overview

Write implementation plans for an engineer who has not seen this codebase or this spec. Assume they write idiomatic code in the project's language once they know the exact interface and the exact test, and that they will make a reasonable choice wherever the plan leaves one open. What they cannot know is what you decided: which files, which names and signatures, which values from the spec, which tests prove each task. Document those. DRY. YAGNI. TDD.

The plan is usually executed by one `worker` subagent reading the whole plan as its brief (or, for a large plan, a fresh worker per task reading only its task), so write it as that brief: self-contained, exact values verbatim, the commands that verify it, and the commit message.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Where the plan goes:**
- Default: `docs/plans/YYYY-MM-DD-<feature>.md` in the repo, committed on the work branch.
- If `gh repo view --json visibility --jq .visibility` prints `PUBLIC`, write it to private tools-ops instead, at `~/GitHub/schuettc/tools-workspace/tools-ops/docs/<repo>/plans/YYYY-MM-DD-<feature>.md`, and commit it there under AGENTS.md's Git rules. Never commit it in the public repo.

## Size It First

Before tasks, write down the smallest change that does the ask and its rough size in lines (code plus tests). Apply AGENTS.md's "Scope and size": every case, guard, option, fallback or test in the plan names when it happened in real use; anything else goes in a "Follow-ups" list of one line each, not in a task. If the plan comes out much bigger than the spec implied, show Court the list with what you'd drop before writing tasks.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans, one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure, but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

## Task Right-Sizing

Keep tasks only as fine as a single implementer needs to work through the plan in order. There is no reviewer per task, so don't split for review gates: fold setup, configuration, scaffolding, and documentation steps into the task whose deliverable needs them. Split where a task produces something a later task consumes, or where a test cycle naturally ends. A small plan may be one task.

Each task carries its own check commands: the test command (and any build or lint command) that proves the task, with the result that means it passed. In executing-plans' large-plan mode, the main session runs exactly those commands between tasks and reads their exit codes, so a task's checks must run on their own from the worktree.

## Step Granularity

**Each step is one action with a checkable result:**
- "Write the failing test": step
- "Run it to make sure it fails": step
- "Implement the minimal code to make the test pass": step
- "Run the tests and make sure they pass": step
- "Commit": step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** Execute with the executing-plans skill. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Size:** [The smallest change that does the ask, rough lines of code + tests]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Spec:** [path to the spec/design doc this plan implements; the plan argues from the spec, so the spec travels with it; executors read both]

**Worktree and branch:** [path and branch name, per AGENTS.md's Git rules]

## Global Constraints

[The spec's project-wide requirements (version floors, dependency limits, naming and copy rules, platform requirements), one line each, with exact values copied verbatim from the spec. Every task's requirements implicitly include this section.]

## Review Focus

[Up to five input classes or failure modes the spec implies but no task's tests exercise that are most likely to bite a person using this software, one line each, naming the input or condition and the behavior a reasonable person would expect, most likely first. Only cases that have happened or that a real user will hit this week; the rest are follow-ups. For each line, add the test that pins it to the task that owns the code. The final reviewer checks each line deliberately.]

## Follow-ups

[One line each: cases and options considered and not built, with why not yet.]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Interfaces:**
- Consumes: [what this task uses from earlier tasks: exact signatures]
- Produces: [what later tasks rely on: exact function names, parameter and return types]

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Implement `function(input: InputType) -> ResultType` in `exact/path/to/file.py`**

One line on the approach when the signature and the test leave a choice (which library call, which data structure); a code block only for an algorithm they do not determine.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## What a Step Contains

A step is done when the implementer can write exactly one reasonable thing from it. That is the whole requirement: unambiguous, not complete. Each kind of step carries what makes it unambiguous and nothing more:

- **A test step:** the test's name and its assertions, as code, with the spec's exact values in them.
- **A code step:** the exact signature (name, parameters, return type), the file it lives in, and the specific values the spec pins. The implementer writes the body. A body appears only for an algorithm the signature and tests do not determine, or for exact copy the spec fixes.
- **A verification step:** the command to run and the output that means it passed.
- **A reference to another task:** that task's Interfaces block says what to use; the plan does not repeat that task's code.

A plan is the set of decisions the implementer cannot make alone. A plan longer than the code it describes has written the code instead. Lines that decide nothing ("TBD", "handle edge cases", "add appropriate validation", "write tests for the above", a type or function no task defines) are the opposite failure, and the self-review catches both.

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself, not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Step scan:** Every step must let the implementer write exactly one reasonable thing, and no step may carry more than that: a line that decides nothing is a gap, a function body the signature and tests already determine is a transcript. Fix both.

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

**4. Review Focus:** For each input class or failure mode the spec implies, is there a task whose tests exercise it? The uncovered ones most likely to bite a person go in Review Focus, each with its test added to the owning task. An empty section means you checked and found none, not that you skipped the check.

**5. Proportion and size:** Compare the plan's length to the spec's, and the Size line to what the tasks actually build. A plan several times longer than the spec is a transcript of the program, not a plan: replace bodies with signatures, test names and assertions. Anything in a task that hasn't happened in real use moves to Follow-ups.

If you find issues, fix them inline. No need to re-review: just fix and move on. If you find a spec requirement with no task, add the task.

## Execution Handoff

After saving and self-reviewing the plan, open it for Court with `galley_open` and give the URL, with the Size line and the Follow-ups list in your message:

**"Plan saved to `<path>` (about <N> lines of change). Please review it in galley. Does it capture what you want?"**

Wait for Court's review. If Court requests changes, make them and re-run the self-review. Once Court approves, use the executing-plans skill. It is the only execution path.
