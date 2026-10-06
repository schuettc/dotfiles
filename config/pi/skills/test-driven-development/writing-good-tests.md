# Writing Good Tests

**Read this when:** writing or changing tests, adding mocks, or adding cleanup or helper methods for tests.

## Overview

A test exists to catch a specific break in a behavior someone asked for. Two principles govern everything here:

1. Every test names the break it catches.
2. Every test exercises the real thing.

A test written first and watched failing against real code has already proven it can fail, and only earns a mock when the real dependency proves slow or external.

## Principle 1: Name the Break

Before writing the test body, answer: **what production change should make this test fail, and is that change a bug or a decision?** A test earns its place by catching a wrong branch, a missing side effect, a wrong argument or a broken contract in behavior the spec asks for or a failure that happened.

**Derive expectations independently.** Use literals and hand-checked fixtures; table-driven tests with literal `want` values are the preferred shape. An expectation computed by the code under test, or its helpers, passes no matter what that code does:

```typescript
// Bad: mirror assertion, the same builder computes both sides
const expected = buildSearchQuery({ tag: 'urgent' });
expect(buildSearchQuery({ tag: 'urgent' })).toBe(expected);

// Good: hand-derived literal
expect(buildSearchQuery({ tag: 'urgent' })).toBe('tag:"urgent"');
```

**No change detectors.** If only intentional decisions can fail a test (a constant's value, exact message wording, private structure), it fires on redesign and sleeps through bugs. Test the behavior that depends on the decision: not `expect(MAX_RETRIES).toBe(5)` but "a failing call is retried 5 times and the 6th attempt never happens."

**Behavior, not text.** Asserting that a script, skill or config contains an exact line proves only that the source is the source. Run scripts against controlled inputs and assert outputs, side effects or exit codes. Prose for people earns no test at all.

**Your code, not the framework.** Test the contract your code makes at its boundaries: the route you register, the query you emit, the payload you produce. Upstream mechanics are their maintainers' tests to write. When upstream behavior really surprised you, write one narrow characterization test naming the assumption. Constructors, getters, constants and trivial forwarding earn tests only when they validate, normalize, default, derive or cause side effects; otherwise assert the first consumer-visible result that depends on them.

### Before writing the test body

- Name the production change that would make this test fail. If you can't, redesign the test around an observable behavior.
- If the answer is "the source text changed", run the artifact and assert its effects instead.
- If only intentional decisions would fail it, it is a change detector: test the behavior that depends on the decision.
- Confirm the expected value is derived without the code under test; if it reuses the code's logic or helpers, replace it with a literal or a hand-checked fixture.

## Principle 2: Exercise the Real Thing

**The mock earns no assertions.** A mock assertion passes when the mock is present and fails when it is absent; it says nothing about the component. Assert the real component's behavior; if the mock is what you are checking, unmock it or delete the assertion.

```typescript
// Good: real behavior
expect(screen.getByRole('navigation')).toBeInTheDocument();

// Bad: mock existence
expect(screen.getByTestId('sidebar-mock')).toBeInTheDocument();
```

**Mock at the right level.** Learn every side effect of the real method before replacing it; mock the slow or external operation and keep what the test depends on real. When unsure, run the test against the real implementation first and observe what actually needs to happen.

```typescript
// Bad: the mock swallows the config write that duplicate detection reads
vi.mock('ToolCatalog', () => ({
  discoverAndCacheTools: vi.fn().mockResolvedValue(undefined)
}));

// Good: mock only the slow server startup; the config write stays real
vi.mock('MCPServerManager');
```

**Make doubles specific.** When arguments, call counts or ordering are part of the contract, assert them: a fake that accepts anything verifies nothing. Give each branch the spec asks about its own fixture, so the wrong branch cannot satisfy the expectation.

**Mirror real data completely.** Mock the complete structure as it exists in reality, not just the fields your test reads. Partial mocks fail silently when downstream code reads an omitted field: the test passes while integration breaks.

**Production classes carry production methods only.** Cleanup that only tests need lives in test utilities, never as a `destroy()` on the production class.

**Prefer real components over complex mocks.** When mock setup outgrows the test logic, switch to an integration test with real components. Ask: "Do we need a mock here at all?"

### Before adding a mock or test helper

- List the real method's side effects; keep the ones the test depends on real and mock the slow or external level below them.
- Make mock responses mirror the complete real structure.
- Put a method only tests call in test utilities, not production code.
- About to assert on the mock itself? Unmock it or delete the assertion.

## The Mutation Check

Before finishing, mentally mutate the production code for each behavior the spec asks for; at least one test should fail for each realistic mutation of that behavior (a wrong constant or argument, the wrong branch, a missing state change or side effect, an empty or default return). A mutation nothing catches in an asked-for behavior marks a missing or tautological test: fix it. A mutation in a case nobody asked for is a follow-up line, not a new test.

## Quick Reference

| When you... | Do |
|-------------|-----|
| Write any test | Name the break it catches: a bug, not a decision |
| Build an expected value | Derive it by hand, never with the code under test |
| Test a script | Run it and assert outputs and exit codes; never grep its text |
| Reach for a dependency test | Test your boundary contract, not their mechanics |
| Want to assert on a mocked element | Test the real component, or unmock it |
| Are about to mock a method | Learn its side effects; mock the slow or external level |
| Need cleanup only tests use | Put it in test utilities |
| Watch mock setup balloon | Switch to an integration test with real components |
| Think of a case nobody asked for | Write a one-line follow-up, not a test |

## Warning Signs

- Setup and assertion share the same object, guaranteeing equality.
- The test can fail only through a crash or a missing selector.
- The test fails on every intentional change, never on accidental breakage.
- Expected values are hidden behind loops, builders or helpers.
- The test greps source text, or asserts a removed symbol stays removed.
- The test exists for coverage, checking no side effect or outcome.
- An assertion checks a `*-mock` test ID, or fails if you remove the mock.
- A method is called only from test files.
- Mock setup is more than half the test, or mocking is "just to be safe".
- The test file is larger than the feature it tests (that needs Court's yes).
