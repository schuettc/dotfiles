---
name: install-wizard
description: Use when someone wants to selectively install components of this dotfiles repo — walks through each package (what it does, what it touches), resolves dependencies, runs chosen package installs, verifies. Triggers on "install wizard", "selective install", "set up these dotfiles", "what would this install".
---

# Dotfiles Install Wizard

Guide the user through a selective install of this repo's packages. The
packages — not this file — are the source of truth: read every
`packages/*/pkg.sh` for `PKG_DESC` and `PKG_DEPS` before saying anything.

## Flow (one question per message, always)

1. **Prereq scan.** Verify macOS (`uname`). Report what's already present:
   brew, go, claude, codex, cursor-agent, SwiftBar, an existing ~/.claude/settings.json
   (say clearly: merges are additive — their settings are preserved).
2. **Inventory.** Present the package list with one-line descriptions and
   the dependency graph, then walk packages ONE AT A TIME in canonical
   order (core terminal nvim markedit claude swiftbar codex pi cursor muster).
   Pi is an opt-in local-model package and is not part of root `install.sh`;
   explicitly call out that it installs llama.cpp, writes additive Pi provider
   defaults, and creates a persistent loopback-only router LaunchAgent. For
   each: what it is, how it works, and EXACTLY what it touches — casks
   installed, files symlinked into $HOME, settings files merged, and any
   persistence (login items, LaunchAgents) called out explicitly. Codex
   needs a paid ChatGPT subscription — say so. Then ask: install? yes/no.
3. **Dependency closure.** Expand picks with hard deps (PKG_DEPS,
   transitively). Tell the user exactly what was added and why. Show the
   final list and get explicit confirmation before installing anything.
4. **Execute.** Run `bash packages/run.sh <pkg>` one package at a time, in
   canonical order, streaming output. On a failure: report it, ask
   continue-or-stop. Never install anything outside the confirmed set;
   never edit package scripts.
5. **Report.** Per-package verify results (run.sh prints them), then an
   honest summary: installed / skipped / failed / remaining manual steps
   (SwiftBar Accessibility grant, `codex login`, `atuin login`).

## Rules

- One question per message. No compound questions.
- Explain before asking — the user should understand a package before
  deciding. Answer side-questions from the pkg.sh/README content.
- Never run root ./install.sh from this skill (that is the standard-package
  path); the wizard only runs packages/run.sh with the confirmed set.
- If a package's verify FAILs, say so plainly — no "mostly worked".
