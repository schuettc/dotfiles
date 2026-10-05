---
name: cleaning-up-branches
description: Use when cleaning up stale local or remote git branches or worktrees in any repo, deciding which branches are safe to delete, or when a cleanup pass finds branches "not merged" that look done.
---

# Cleaning up branches

`git branch --merged` and other ancestry checks miss squash-merged branches: their commits never become ancestors of the base, so finished work looks unmerged.

## Which branches are disposable

A branch is disposable if either is true:

- it is an ancestor of `origin/main` or `origin/dev`, or
- its name is the head ref of a merged PR (`gh api 'repos/<owner>/<repo>/pulls?state=closed&per_page=100' --paginate`, entries with `merged_at` set) **and** its current tip is the PR's `head.sha`. A name match alone can be a reused name or carry commits added after the merge, so a branch whose tip differs is not disposable.

Never delete a branch that has an open PR or is checked out in a worktree.

## Second pass on survivors

Check every branch that survives the first pass by age, commits behind its base, and the sign of its diff against the base. A huge negative diff (the branch deletes most of the repo) is a snapshot from before a migration, not unfinished work.

## Abandoned rebases

Find abandoned rebases through `.git/rebase-merge/head-name` (and `.git/worktrees/<name>/rebase-merge/head-name` for linked worktrees), not `git worktree list`.
