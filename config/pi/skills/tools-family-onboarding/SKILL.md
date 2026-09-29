---
name: tools-family-onboarding
description: Use when adding a new .tools family property or migrating an existing tool onto the family standard — standing up a StaticSite, wiring the binary download pipeline (/dl + install.sh + release.yml), adding a tool to the subaud family index, or debugging why a site's content isn't deploying. Fires on "add a .tools site", "put <tool> on the download standard", "onboard <tool>", or "<tool>.tools content isn't updating". Covers the exact gh/cdk/aws commands, the values to harvest, and the steps that are guardrail-blocked and MUST be run by a human.
---

# Onboarding a .tools family member

Everything is either the `StaticSite` construct (infra, in `tools-ops`), the
`tools-common` module (CLI), tools-actions (CI and release), or a documented
convention. This skill is the operational runbook for the site and the `/dl`
pipeline; paths are from the tools-workspace root. The repo itself (justfile,
CI, lint, hooks, release.yml) is the `building-a-tools-family-tool` skill, and
shipping is `releasing-a-tools-family-tool`. The why:
`tools-ops/docs/superpowers/specs/2026-08-30-family-tools-standard.md`.

## Golden rules (the failure modes we actually hit)
- **A green CI matrix job with a skip-gate MASKS a no-op.** `sites.yml` and
  `infra.yml` jobs succeed whether they deploy or skip. After any deploy, verify
  the actual STEP ran: `gh run view <id> --json jobs -q '.jobs[]|select(.name|test("<tool>"))|.steps[]|"\(.conclusion) \(.name)"'` — `Sync and invalidate` must say `success`, not `skipped`. (This is how kempt shipped un-wired.)
- **These steps are guardrail-blocked for the agent — a HUMAN must run them:**
  `gh secret set` with a role ARN, editing a CI workflow to add role-assumption,
  and the literal `curl … | sh`. The agent verifies equivalently (fetch + run, or
  manual download+checksum) and hands the human the exact commands.
- **tools-ops is a shared clone.** `git fetch && rebase` before any push, and
  coordinate on muster (broadcast a HOLD) before an infra/site push during
  someone else's launch.

## A. Add a new site (StaticSite)
1. Register the domain; create/import the zone. In `tools-ops/infra/bin/app.ts` add a
   `new StaticSite(stack, "Site", { apex, zone, deployRepo, stage })`. Stage is
   **committed code**: `zone` (zone only) → `staged` (bucket/cert/dist, NO apex
   alias) → `live` (apex A/AAAA cutover). Deploy via a push to `infra/**` (CI
   `infra.yml` runs `cdk deploy --all`); never `cdk deploy` from a laptop.
2. `tools-ops/.github/workflows/sites.yml`: add the tool to the `changes` filter, the `outputs`, and the
   `matrix`. Then a human sets the **3 site secrets** (values from the stack
   outputs `DeployRoleArn` / `ContentBucketName` / `DistributionId`):
   ```sh
   gh secret set SITE_DEPLOY_ROLE_ARN_<tool> --repo schuettc/tools-ops --body "<DeployRoleArn>"
   gh secret set <tool>_BUCKET --repo schuettc/tools-ops --body "<ContentBucketName>"
   gh secret set <tool>_DISTRIBUTION_ID --repo schuettc/tools-ops --body "<DistributionId>"
   ```
   Without them the gate silently skips the tool forever. VERIFY per the golden rule.
3. Content: `tools-ops/sites/<domain>/` (index.html on the standard header, style.css with a
   distinct accent, site.js, favicon/mark, llms.txt). Add the tool to
   `sites/subaud.tools/` (nav, family card, footer, `icons/<tool>.svg`, meta count).

## B. Wire the binary download pipeline (/dl)
Only for tools that ship a binary (npm tools use trusted-publisher instead).
1. **Infra:** add `downloads: { releaseRepo: "<owner>@<ownerId>/<repo>@<repoId>" }`
   to the site's `StaticSite`. Get ids: `gh api repos/<owner>/<repo> --jq '{id,ownerId:.owner.id}'`.
   Deploy (push `infra/**`). **`downloads` only materializes at `staged`/`live`, not `zone`.**
   Harvest `DownloadsBucketName`, `ReleaseRoleArn`, `DistributionId` from the stack.
2. **OIDC immutable-subject (the #1 gotcha — AssumeRole fails on run 1 without it), human:**
   ```sh
   gh api --method PUT /repos/<owner>/<repo>/actions/oidc/customization/sub -F use_default=false -F use_immutable_subject=true
   ```
   Verify GET → `sub_claim_prefix` = `repo:<owner>@<ownerId>/<repo>@<repoId>`.
3. **Secrets (human), on the `release` environment:** `<TOOL>_RELEASE_ROLE_ARN`
   (=ReleaseRoleArn), `<TOOL>_DOWNLOADS_BUCKET` (=DownloadsBucketName).
4. **release.yml:** copy kempt's (tools-actions `release-version` + `go-release`
   at the repo's one tools-actions version) and rename; `go-release` builds,
   signs, publishes `/dl/<tool>/<version>/` and moves `latest` only for a
   non-prerelease. Its `dl-*` inputs take the bucket, role and distribution id
   above. Never hand-write build, sign or upload steps.
5. **rc de-risk (agent):** `gh workflow run release.yml --repo <owner>/<repo> --ref <release ref> -f tag=""`
   (the `release` environment accepts only release refs: `main`, `dev`+`main`, or `*/v*` tags)
   → publishes to `/dl/<tool>/<rc>/`, must NOT move `latest`. Verify artifacts 200,
   `latest` still 404, and full download→`shasum -c`→run.
6. **install.sh is generated:** add `tools-ops/templates/install/sites/<domain>.conf`
   (copy one; `TOOLS`, `PREFIX`, install dir), run `templates/install/render.sh`,
   commit `sites/<domain>/install.sh` (CI's `installers.yml` fails a hand edit).
   **Serve it ONLY after `/dl/<tool>/latest` exists**, or the live `curl … | sh`
   404s: hold that commit until then.
7. **Populate `latest`:** either the tool's next real release moves it, or
   back-fill an existing version — `gh release download v<X> --pattern '<tool>_*.tar.gz'`,
   write sidecars, `aws s3 cp` to `/dl/<tool>/<X>/`, then
   `printf <X> | aws s3 cp - s3://<bucket>/dl/<tool>/latest` + invalidate.
   (Plain `aws s3 cp` is NOT guardrail-blocked; the agent can run it.)
8. **Verify the public path:** `curl <domain>/dl/<tool>/latest` = version;
   download → fail-closed checksum → run. (`curl|sh` literal is human-only.)

## Then: the family standard and check
Add the tool to `tools-ops/templates/family/tools.tsv` and run
`tools-ops/templates/family/check.sh`: the site, `/dl` and signing rows are
this runbook's result; the rest is `building-a-tools-family-tool`.

## C. Set the project's standing orders (muster)
At project setup, author ONE standing order per project so **every session that
starts later is greeted with the project's invariants** — the failure modes that
keep getting rediscovered. This is a durable, keyed, retractable convention
(muster `standing`, shipped 0.15.2+), not an ad-hoc broadcast.

Author it once at setup (idempotent — re-run to update; a change re-greets both
running and future sessions; the key defaults to `invariants`):
```sh
muster standing set <project> --key invariants "shared clone: git fetch+rebase before any push; coordinate before touching a load-bearing tool (branch target + collisions); HUMAN-ONLY, guardrail-blocked: gh secret set / editing a CI workflow to add role-assumption / curl|sh; read tools-ops/docs/superpowers/specs/2026-08-30-family-tools-standard.md + the tools-family-onboarding skill"
```
Audit / verify (the machine-readable seam — confirm a project's orders are
present + current):
```sh
muster standing <project> --json
```
Retract a stale order (stops greeting new sessions; running sessions that already
read it are unaffected):
```sh
muster standing retract <project> [--key <k>]
```
Surfaces: the CLI verbs above work now for anyone with the updated binary. The
MCP tools `standing_set` / `standing_retract` / `standing_list` are the skill's
programmatic surface, available to a session once it's on the 0.15.2+ `muster
mcp` server (long-running MCP processes need a respawn to see new tools). Prefer
the MCP tools when driving this from a session; the CLI is the fallback.
