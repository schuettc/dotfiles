---
name: building-a-tools-family-tool
description: Use when creating a new .tools family tool (kempt, muster, galley, hail, tackle's scratch/proj/creel/casebook, or a new one) or changing any family repo's build, CI, lint, git hooks, justfile, release workflow, installer or layout; when a family CI gate or lint finding disagrees with local; or when a shared gate/action needs a change.
---

# Building a .tools family tool

Court's rule (2026-09-29): **one system for every tool.** "There's no reason to have different systems between similar tools." Only genuinely tool-specific steps differ, and only in fixed slots. If you are about to write something a sibling repo already has, stop: it comes from a shared place.

**The standard's one description:** `tools-ops/templates/family/README.md`. **The proof:** `tools-ops/templates/family/check.sh` (run it; FAIL rows are drift).

## Where every piece comes from

| Piece | Source | Never |
|---|---|---|
| CLI framework: commands, help, `man`, `commands --json`, exit codes 0/1/2, `version`, `update` (self-update from `<site>/dl`) | `github.com/schuettc/tools-common`: `tools.New(tools.Config{...})`, `Register`, `Dispatch`, `tools.Version`, `SelfUpdate` (kempt's `internal/cli/cli.go` is the model). `internal/version` only holds the `-X`-stamped `version`/`commit`/`date` that feed `tools.Version` | cobra, a hand-rolled dispatcher, printing or parsing versions yourself |
| Session identity, channel MCP server, atomic writes, XDG dirs, local page, SQLite | tools-common `harness`, `channelmcp`, `WriteFileAtomic`/`PIDAlive`, `ConfigDir`/`StateDir`/..., `localweb/page`, `sqlitedb` (separate module) | a private copy |
| Justfile first block, `lefthook.yml`, `version-guard.yml` | copy **verbatim** from `tools-ops/templates/family/` | editing them in one repo |
| Go gate (gofmt, vet, golangci-lint, `go test -race`, 4 builds) | `schuettc/tools-actions/go-ci@vX.Y.Z` in CI; `just gate` runs the same version locally | installing golangci-lint by hand, CI steps that re-spell the gate |
| Lint config | ships inside tools-actions `go-ci` | a repo `.golangci.yml` |
| Release | tools-actions `release-version` + `go-release` in `release.yml` (copy kempt's, rename) | hand-written build/sign/upload steps; skipping `prepare`'s files (below) |
| Installer | generated: `tools-ops/templates/install/sites/<domain>.conf` + `render.sh` | a hand-written `install.sh` in the repo |

All tools-actions steps in a repo use **one** version; `dependabot.yml` proposes each tools-actions and tools-common release (copy kempt's; `target-branch: dev` for dev-model tools).

## The only tool-specific slots

In the justfile, after the `# ---- <tool> ----` line:

- `prepare:` files the gate needs that are not committed (empty in galley since 0.11.0, which removed its wasm client). CI's `gate` job runs `just prepare` before `go-ci`. **`go-release` does not run it**, so a release build fails where CI passed unless the files exist there too. For a small generated source file (a schema, a table), prefer committing it, with a `verify-extra` check that regenerates it and fails when it is stale (galley's `bundle-fresh`); then `prepare` stays empty. For a large build output that cannot be committed, `release.yml` needs a step before `go-release` that builds it.
- `verify-extra:` checks beyond the Go gate (galley: TypeScript gate). CI's `extra` job runs it.
- `verify-slow:` checks too slow for a push (a browser, a container). CI runs them as their own required job(s); `just verify-all` runs everything. Model a container suite on muster's `verify-dynamo` recipe and `dynamo` CI job: a service container, a wait until it answers (a container is "started" before it listens), and a step that fails on `--- SKIP` (tests that skip without an endpoint otherwise go green having run nothing).

`just verify` = `prepare` + `gate` + `verify-extra`, and it is exactly what the pre-push hook and CI run. `ci.yml` = kempt's shape: a `gate` job over the tool's OS list and an `extra` job, plus any slow jobs.

## A new tool: the checklist

1. Repo `schuettc/<tool>` (public), Go module `github.com/schuettc/<tool>` on the latest tools-common tag; `main` builds one `tools.New(...)`. Start `VERSION` at `0.1.0` with a `## 0.1.0` changelog entry: the first merge to `main` (with the release environment ready) is the first release.
2. Files: `VERSION` (or `<tool>/vX.Y.Z` tags in tackle), `CHANGELOG.md`, `LICENSE`, `lefthook.yml`, `justfile`, `.github/workflows/{ci,release,version-guard}.yml`, `.github/dependabot.yml`, `.gitignore` with `.worktrees/`.
3. `just hooks` once per clone (plain `lefthook install` refuses: git's global `core.hooksPath` is casebook's recorder, which forwards to `.git/hooks`).
4. Site, `/dl` bucket, OIDC, release secrets: the `tools-family-onboarding` skill.
5. GitHub `release` environment: the 4 Apple secrets (`APPLE_DEVELOPER_ID_P12`, `APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`; `_P12_PASSWORD` only if the p12 has one) and deployment refs limited to the release refs (main-model: `main`; dev-model: `dev` + `main`; tackle: tag `*/v*`).
6. Add a row to `tools-ops/templates/family/tools.tsv`; add the tool's `download` step to `~/dotfiles/kempt.toml` so `kempt update` installs it.
7. `check.sh` shows the tool with no FAIL rows.

## Read the real thing

Model a change on kempt and muster (after `git pull`), or read GitHub: `gh api -H "Accept: application/vnd.github.raw" "repos/schuettc/<repo>/contents/<path>?ref=main"`. **galley: always read GitHub**, never its local copies: it is a bare repo whose worktrees (`public-dev`, `rel`, `rel2`, ...) are old branches and whose `origin/*` refs lag.

## Lint findings

Fix the code. A real exception is `//nolint:<linter> // <why>` on the flagged line (for a statement spanning lines, the line above it; never inside a string literal). Never a repo config, never an exclusion added to the family config for one call site.

## Changing the standard or a shared gate

Change it in the shared place, never in one repo: tools-actions (test, bump `VERSION`, PR, merge, confirm the release tag contains your change) or `tools-ops/templates/family/` (and every repo in the same sweep; the check fails the ones not caught up). Then bump each repo's pins. Before choosing a tools-actions version, check `origin/main:VERSION` and open PRs: another session may have claimed it.

## Traps that cost real time

- **A pipe into `grep -q` under `pipefail`** reports failure on a match (SIGPIPE). Capture output first.
- **Justfile recipes run with `pipefail`**: a producer that exits non-zero on findings (fallow) needs `{ cmd || true; } | verdict-script`.
- **golangci-lint given import paths** loads nothing and says "0 issues"; the gate passes relative dirs and fails on any `level=error`. A green lint you did not see find anything is not proof.
- **galley's layout** (`.git` is a bare repo, branches are worktrees under `.worktrees/`) breaks Go VCS stamping; the gate sets `-buildvcs=false`.
- **Renaming CI jobs** orphans branch-protection required checks (muster `main` requires `gate (ubuntu-26.04)`, `gate (macos-26)`, `extra`, `dynamo`, `version-guard`): update them in the same change.
