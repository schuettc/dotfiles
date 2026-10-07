---
name: sift
description: Runs a sift round end to end through the sift channel tools, from the audit through recommending each file, the user's review, apply, the pull requests and the cleanup. Use when the user asks to audit or tidy their agent instruction files (global files, repo instruction files, skills).
---

# Running a sift round

sift audits the instruction files agents read and finds what is too big, duplicated, stale, dead or misplaced. You write one revised version of each file with findings. The user decides each file on a review page, and sift turns their approvals into one pull request per repo.

The channel tools are `sift_check`, `sift_next`, `sift_propose`, `sift_review`, `sift_apply`, `sift_status` and `sift_clean`. If they are missing, the sift channel is not registered for this session: tell the user, and stop.

## When to run one

- The user asks for an audit, or asks you to tidy their instruction files.

Run one round at a time. If `sift_status` shows a round still being recommended, or one the user has not sent yet, finish that one first.

## 1. Audit

Call `sift_check`. It records a new round and returns:

- how many files were looked at, and how many need a recommendation;
- the findings per check, and how many are certain;
- any warnings, such as a repo it could not read.

If no file needs a recommendation, tell the user the files are clean, and stop. Pass any warnings on to the user.

## 2. Recommend every file

Repeat until `sift_next` returns `done: true`:

1. Call `sift_next`. It gives one file: its key, where it is, its budget, its content at the audit, its base hash, its findings, the other files it may link to, and the guidance for the rewrite.
2. Read the guidance it returns, and follow it. It is the rule for this round, and it can change between versions of sift.
3. Write the whole revised file. Fix every certain finding. For each other finding, fix it, or keep the text and say why in one line.
4. Call `sift_propose` with the whole file, the base hash from `sift_next`, each finding as `fixed` or `kept` with its one line, and a two or three sentence summary.

### Moving text between files

When text belongs in another file (a repo rule in a global file, say), recommend both files in one `sift_propose` call. Each one lists the other in `links`. Then the user decides the two together, and apply writes both or neither.

### When a file needs no change

If a file is right as it is, propose its content unchanged, with every finding kept and the reason for each. The user then agrees or disagrees with you.

### When `sift_propose` refuses

A refusal gives the reason: a missing finding, a wrong base, a link without its other side. Fix what it names and call it again. Every file in the call is refused together, and none is stored.

## 3. Hand it to the user

Once `sift_next` says done, call `sift_review` once. It opens the review page and makes this session the one the user's decisions are sent to. Tell the user how many files wait, and carry on with other work.

On the page, the user accepts, edits or rejects each file, then presses Send. Send reaches this session as a channel event from sift.

If the session has no sift events (the channel is not attached), the user can run `sift wait` in a terminal, which prints the same steps when they press Send.

## 4. Act on Send

The event gives the counts of files accepted, edited and rejected, the user's notes, and the next steps. Follow them:

- **Notes** explain the user's decisions. A rejected file stays as it is.
- **Recommend again** lists files where you proposed no change and the user disagrees. Read each note, then propose a rewrite of that file with `sift_propose`, using the base hash you were given for it. The page shows the new version, and the user decides it and sends again.
- **Next** is `sift_apply`, for the files the user accepted or edited.

`sift_apply` writes each approved file whole, one branch per repo, in a worktree cut from the repo's base. Then, with `gh` and a GitHub remote, it pushes the branch and opens a pull request. It returns, per repo:

- the pull request or branch, and the files it wrote;
- each file it held, with the reason (the base moved on since the audit, uncommitted or unpushed work in the clone, a linked file not approved);
- what is left for the user: a file outside every repo, whose approved content it saved, with the path.

You can call `sift_apply` with `dry_run` first to see the plan without touching anything. After it, run `sift reconcile` in a terminal: it checks that each branch holds exactly the approved content and nothing else.

## 5. Report

Tell the user:

- each pull request, with its link;
- each held file, with the reason, and what to do about it;
- each file left for them, and where its approved content is.

A held file waits for a new round. Once its cause is fixed, run `sift_check` again.

The pull requests are the user's to merge. Leave merging to them, and leave each pull request's required checks to run as they are.

## 6. Clean up

After the user has merged or closed the round's pull requests, call `sift_clean`. It removes only what apply recorded creating:

- each round branch, local and on the remote, after its pull request is merged or closed;
- any worktree apply left behind.

A branch whose pull request is still open is kept. Call `sift_clean` with `dry_run` to show the plan first, and tell the user what it removed and what it kept.

## When something fails

If a tool returns an error, tell the user what failed, in its own words, and leave the files as they are. `sift_status` shows the round's state, what is open, decided and sent, and whether a Send is still waiting to be delivered.
