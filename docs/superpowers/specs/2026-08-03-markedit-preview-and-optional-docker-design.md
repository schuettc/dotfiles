# MarkEdit preview in setup + Docker Desktop opt-in — Design

Date: 2026-08-03
Status: Approved

## Problem

1. MarkEdit's Shift-Cmd-V markdown preview is not built into the app — it
   comes from the [MarkEdit-preview](https://github.com/MarkEdit-app/MarkEdit-preview)
   extension, a JS file in the app container's `scripts/` folder. Nothing in
   the install process installed it, so a fresh machine (or a recreated
   container) has styled-but-previewless MarkEdit.
2. Docker Desktop is a heavyweight cask baked into `packages/core/Brewfile`,
   so every install path gets it whether wanted or not.

## Design

### 1. MarkEdit preview encoded in the `markedit` package

- `packages/markedit/pkg.sh` `pkg_install`: after linking `editor.css`, if
  `scripts/markedit-preview.js` is absent or empty, resolve the latest
  GitHub release via the public API (curl + jq; both guaranteed by the
  `core` dependency), download, unzip, and copy `dist/markedit-preview.js`
  into the container's `scripts/` folder. The extension self-notifies about
  updates, so an existing copy is never overwritten. Download failure is a
  `warn`, not a fatal error, matching the repo's resilient-install ethos.
- `pkg_verify` additionally checks `scripts/markedit-preview.js` exists and
  is non-empty.
- Fonts need no install step: `editor.css` (like the Ghostty config) asks
  for MonoLisa and falls back to system fonts when it isn't installed.
  MonoLisa is commercially licensed and the repo is public, so no font
  files are shipped.

### 2. Docker Desktop becomes an opt-in package

- New `packages/docker/`: `Brewfile` with `cask "docker-desktop"`, `pkg.sh`
  with `PKG_DEPS=(core)` and a `pkg_verify` that checks
  `/Applications/Docker.app`.
- Remove the `docker-desktop` cask from `packages/core/Brewfile`.
- Add `docker` to the canonical `ORDER` in `packages/run.sh` (last).
- `install.sh`'s package loop is unchanged — `docker` not being in it is
  what makes it opt-in. A "Next steps" line points at
  `packages/run.sh docker`.
- Update the install-wizard skill's canonical order and the README package
  list to include `docker`, flagged as opt-in.
- Existing machines keep their Docker Desktop; brew does not uninstall
  casks that leave a Brewfile.

## Out of scope

- Uninstalling Docker Desktop anywhere.
- Managing MarkEdit's `settings.json` or other container files.
- Any font distribution mechanism.
