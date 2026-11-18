---
name: install-wizard
description: Use when someone wants to set up this machine from these dotfiles, or choose which of its packages and layers to take — walks through kempt's profiles and packages (what each does, what it touches), resolves dependencies, runs `kempt init` or a deliberate adoption, and lists the personal follow-ups. Triggers on "install wizard", "selective install", "set up these dotfiles", "what would this install".
---

# Dotfiles Install Wizard

Guide the user through setting up this machine with kempt. This repo is a
user layer on the subaud starter (`subaud-tools/starter`), which is the base.
The manifests, not this file, are the source of truth: read this repo's
`kempt.toml` (the layer's packages and profiles) and the starter's
`kempt.toml` before saying anything, and take descriptions, `needs`, `notes`
and profiles from them. Do not keep a package list here.

The commands below are yours to run. Ask the user only for the choices and
sign-ins only they can make.

## Flow (one question per message, always)

1. **Prereq scan.** Verify macOS (`uname`) and `kempt version` (0.13.0 or
   later; otherwise install it from kempt.tools first). Find out whether this
   machine already has a kempt selection: `kempt plan` with no flags uses the
   saved selection, and `kempt layer list` shows its layers.
2. **Choose.** New machine: the base is the starter's `suite` profile, with
   `pi` and `neovim` offered as adoptions. Then present this layer's profiles
   (`developer`, `workspace`, `minimal`) and
   then each package ONE AT A TIME in the profile's order. For each: what it
   is, and EXACTLY what it touches: casks and formulas, files linked into
   $HOME, settings merged, and anything persistent (LaunchAgents, login
   items). A download with `setup = true` also takes the hooks, plugins,
   channels, services and skills its release publishes; name them from the
   plan, not from memory. Call out access: the suite downloads need a
   subaud.tools account, and Codex needs a paid ChatGPT plan. Then ask:
   include it? yes/no.
3. **Dependency closure.** Expand picks with their `needs`, transitively. Say
   exactly what was added and why, show the final list, and get explicit
   confirmation before anything runs.
4. **Other layers.** Work and private layers are the user's own; add them
   only from a path or repo they name, after this one.
5. **Execute.** New machine: `kempt init -profile suite
   https://github.com/subaud-tools/starter.git`, `kempt adopt` for `pi` and
   `neovim` if chosen, then clone this repo and `kempt layer add dotfiles
   <checkout>` with the chosen profile or `-packages`. kempt prepares the
   selected releases online (binary and setup together), shows the whole
   plan and asks before applying; read the plan back to the user and wait for
   their yes. `kempt plan` alone works offline from what an earlier apply
   cached, and reports a release it has not prepared as blocked. On a
   failure: report it, ask continue-or-stop.
6. **Report.** `kempt verify`, then an honest summary: applied / skipped /
   failed, and the follow-ups for what was selected (below).

## Follow-ups, by package selected

Offer each only for a selected package, one at a time, and only with the
user's go-ahead. Never ask for a credential before saying what it is for and
what lighter option exists; capture any secret with the secret tool, never in
chat.

- The suite: sign this machine in to the subaud.tools account (`kempt login`,
  once for every subaud tool).
- codex: `codex login`. claude: sign in on first run.
- casebook (the starter's): `casebook init`, then decide whether to install its
  Git recorder (`casebook hooks install`).
- cull (the starter's): `cull init` in each project, which asks for the TypeSafe
  key and whether that project's tests may be sent.
- sift: `sift init --root DIR` for the directories to audit.
- swiftbar: the three macOS steps in its notes (plugin folder, login item,
  Accessibility).
- pi-llama (opt-in): the GGUF weights it serves.

## Rules

- One question per message. No compound questions.
- Explain before asking — the user should understand a package before
  deciding. Answer side-questions from the manifests and the README.
- Never apply anything outside the confirmed selection; never edit the
  manifests during the wizard.
- If a verify fails, say so plainly — no "mostly worked".
