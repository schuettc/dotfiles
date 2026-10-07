# Defense in Depth

## Overview

After you fix a bug caused by invalid data at its source, ask whether the bad value could reach the same damage by another path that has actually been seen. A check at one layer can be bypassed by a different caller, a refactor or a mock.

This is not a reason to validate everything everywhere. AGENTS.md's "Scope" applies: add a check where the bad value actually travelled, or where a second real path to the same damage exists. Name when it happened for each one; anything else is a one-line follow-up. Guard against the world changing in ways you have seen (AGENTS.md "Engineering"), not against every imaginable caller.

## The Layers to Consider

Walk the path the bad value took and consider each layer. Most fixes need one or two of these, not all four.

### Entry point validation
Reject obviously invalid input at the boundary where it came in.

```typescript
function createProject(name: string, workingDirectory: string) {
  if (!workingDirectory || workingDirectory.trim() === '') {
    throw new Error('workingDirectory cannot be empty');
  }
  // ... proceed
}
```

### Business logic validation
Make sure the data makes sense for this operation, when a second real caller can reach it without passing the entry point.

```typescript
function initializeWorkspace(projectDir: string, sessionId: string) {
  if (!projectDir) {
    throw new Error('projectDir required for workspace initialization');
  }
  // ... proceed
}
```

### Environment guards
Refuse a dangerous operation in a context where it has done damage before. This is the layer that protects shared state: a test that ran `git init` against a real repo, or a hook-run test that wrote into a shared `.git/config`.

```typescript
async function gitInit(directory: string) {
  if (process.env.NODE_ENV === 'test') {
    const normalized = normalize(resolve(directory));
    const tmpDir = normalize(resolve(tmpdir()));
    if (!normalized.startsWith(tmpDir)) {
      throw new Error(`Refusing git init outside temp dir during tests: ${directory}`);
    }
  }
  // ... proceed
}
```

### Debug instrumentation
Temporary logging to find the cause belongs in the reproduction, and comes out with the fix. Keep permanent logging only where the failure has recurred and the log is what would explain it next time.

## Applying It

1. **Trace the data flow** (see [root-cause-tracing.md](root-cause-tracing.md)): where did the bad value come from, and where was it used?
2. **Fix it at the source,** with a test that reproduces the failure actually seen.
3. **For each other layer on that path,** ask: has a bad value reached this layer by another route in real use, or does the failure here destroy shared state? Yes: add the check with a test that tries to bypass the earlier layer. No: write a one-line follow-up.

## Example

Bug: an empty `projectDir` caused `git init` in the source tree.

**Data flow:** test setup → empty string → `Project.create(name, '')` → `WorkspaceManager.createWorkspace('')` → `git init` in `process.cwd()`.

**Built:**
- Source fix: `tempDir` throws if read before `beforeEach` (the trigger that happened).
- Environment guard: `git init` refuses to run outside the temp dir during tests (the damage lands in a real repo, which is the case this layer exists for).

**Follow-ups, not built:** entry validation in `Project.create()` and `WorkspaceManager` (no real caller has passed an empty path outside tests).
