---
name: brainstorming
description: "Turns an idea into an approved design scoped to the correct change for the ask, kept as small as correctness allows: spikes and bounded designs through one-question-at-a-time dialogue in chat (with an optional browser visual companion for mockups), architectural designs and their spec on diazo's planning page. Use before any creative work (creating features, building components, adding functionality, or modifying behavior) and before writing a spec or plan."
---

# Brainstorming Ideas Into Designs

Adapted from obra/superpowers (MIT) at 8ca22db; see config/pi/superpowers/.

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Start by classifying how much process the request needs, then work through your path: understand the context, refine the idea, present a design, and get Court's approval.

## Establish Shared Understanding

The outcome of brainstorming is an understanding Court can recognize and correct, grounded in what Court wants to accomplish.

1. **Discover intent.** Use the request and available context to identify the intended outcome, who it is for, and what success looks like. When that information is missing, ask one focused question about purpose or intended use before proposing features or an approach. Knowing the app genre does not tell you why Court wants it. Gathering missing requirements does not ask Court to authorize the task again.
2. **Write back your understanding.** Summarize the intended outcome, relevant constraints, and success criteria in a short note Court can assess. Separate what Court said from assumptions. Invite correction and incorporate the answer before treating this as the design brief. On the architectural path this note is diazo's understanding card.
3. **Carry intent into the design.** Preserve the agreed understanding in the selected path's design artifact: the written spec for architectural work, or the in-chat design/probe for bounded work and spikes. Check proposed features and technical choices against that understanding.

When the request already supplies the purpose and constraints, reflect that understanding instead of asking the same questions again. Keep the note concise; its accuracy and the opportunity to correct it matter.

<HARD-GATE>
Before taking any implementation action, including invoking an implementation skill, writing product code, scaffolding, installing product dependencies, or creating an external project, complete the selected path's prerequisites:

- Spike: Court approves the question and probe.
- Bounded: Court approves the short in-chat design.
- Architectural: Court approves the written spec on diazo's page, then the written implementation plan there. Court's answers to the decisions only permit writing the spec; written-spec approval (Approve on the page) only permits invoking writing-plans.

A reply approves the stage actually presented. Approval of an idea or feature scope does not approve artifacts that do not exist yet. Resume at the earliest incomplete stage; do not turn one approval into permission to skip the rest of the selected path. Read-only project exploration is allowed while those prerequisites remain incomplete.
</HARD-GATE>

## Three Paths

Before your first question, classify the request and say the classification out loud ("this looks bounded, so I'll present a short design here rather than write a spec") so Court can override it:

- **Spike**: a feasibility question ("can we...", "is it possible...", "quick and dirty is fine") whose output is an answer, not code you keep. Present the question and what you'll try in 2-3 sentences, get a nod, then find out as cheaply as correctness allows. No design doc, no spec file. Report findings as a recommendation; anything you built stays labeled throwaway.
- **Bounded**: a well-scoped change to code that already exists in this repo: a new flag, a small endpoint, a one-file fix. Understanding the kind of app is not enough: bounded means the flow you are changing is already here to read. If there is no existing flow to change, the task is not bounded. Ask the clarifying questions that matter, present a short design IN CHAT (a few sentences to a few short paragraphs), and STOP. Implementation starts only after Court says yes to that design; a bounded task's approval is as hard a gate as an architectural one. No spec file, no implementation plan document.
- **Architectural**: new projects, new subsystems, changes that restructure how components fit together or alter interfaces others depend on. Run it in diazo: the understanding, the decisions with their approaches, and the written spec on diazo's page, then the writing-plans skill.

When in doubt between two paths, take the heavier one. The ratchet is one-way: hidden complexity discovered mid-task upgrades the path: stop, say so, and step up. Nothing downgrades mid-task.

## Red Flags

| Thought | Reality |
|---------|---------|
| "This is too simple to need a design" | Follow the selected path: a bounded change gets a short chat design; an architectural change gets the written spec and planning handoffs. |
| "I'll call it bounded and skip the spec" | Reaching for a label to skip work IS the doubt. Take the heavier path. |
| "It's bounded and the design is obvious; I'll start while Court reads it" | The gate is the approval, not the design's length. Present, then stop until you hear yes. |
| "I understand this kind of app, so it's bounded" | Bounded measures the repo, not your familiarity. A new project has no existing flow; it is architectural. |
| "The spike works, so I'll keep the code" | A spike's output is an answer. Keeping the code is a new request: classify it. |
| "It grew, but I'm almost done; no need to re-classify" | Hidden complexity upgrades the path mid-task. Stop and say so. |
| "Court approved the spike, so the follow-up change is approved too" | Each task gets its own classification and its own approval. |

## Checklist

Classify first, announce the path, then create a task for each item on your path and complete them in order.

**Spike:**
1. **Explore project context**: enough to frame the probe
2. **Present question + probe plan**: 2-3 sentences
3. **Get approval**: a nod is enough
4. **Investigate**: as cheaply as correctness allows
5. **Report findings**: a recommendation; label anything built as throwaway

**Bounded:**
1. **Explore project context**: check files, docs, recent commits
2. **Ask clarifying questions**: one at a time, the ones that matter; when one would be clearer shown than described, show it with the visual companion (see below)
3. **Present short design in chat**: approach, files touched, testing, and what it leaves out
4. **Get approval**: STOP and wait for an explicit yes; presenting the design and starting in the same breath is skipping the gate
5. **Implement**: write the failing test first where the change has behavior to test; no plan document. When done, push and open a PR per AGENTS.md's Git rules.

**Architectural:**
1. **Explore project context**: check files, docs, recent commits
2. **Open diazo**: load the diazo skill and open the planning folder with `diazo_open` (see "Where the spec goes" below)
3. **Understanding and decisions on the page**: follow the diazo skill; each decision's options follow "Exploring approaches" below
4. **Write and print the spec**: `spec.md` in the folder, self-reviewed (see below) before `diazo_print_spec`
5. **Court approves the spec on the page**: this is the written-spec approval
6. **Transition to implementation**: invoke the writing-plans skill to create the implementation plan

**Terminal states are path-bound.** Architectural: the ONLY skill you invoke after brainstorming is writing-plans. Bounded: after approval, implementation proceeds directly; no plan document. Spike: the terminal state is a reported recommendation.

## The Process

The subsections below serve the bounded and architectural paths (a spike stops at "present the probe, get a nod"). Sections from **Exploring approaches** onward are architectural-path depth: for bounded work, context plus a few questions plus a short in-chat design is the whole process. On the architectural path the questions, approaches and design are diazo's cards and spec, posted as the diazo skill says; the rules below still decide what goes on them.

**Understanding the idea:**

- Check out the current project state first (files, docs, recent commits)
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag this immediately. Don't spend questions refining details of a project that needs to be decomposed first.
- If the project is too large for a single spec, help Court decompose it into sub-projects: what are the independent pieces, how do they relate, what order should they be built? Then brainstorm the first sub-project through the normal design flow. Each sub-project gets its own spec → plan → implementation cycle.
- For appropriately-scoped projects, ask questions one at a time to refine the idea
- Prefer multiple choice questions when possible, but open-ended is fine too
- Only one question per message. Ask only the forks you can't settle from Court's earlier answers or a standard; decide the rest and list them as reversible. Say up front how many questions to expect, and ask fewer once Court keeps taking your recommendations.
- Focus on understanding: purpose, constraints, success criteria

**Exploring approaches (apply AGENTS.md's "Scope"):**

- Build for what has happened. For every case, option, guard or fallback an approach adds, name when it happened in real use and who needs it this week; otherwise it becomes a one-line follow-up, not part of the design.
- Lead with the correct change for the ask, at the smallest size that stays correct. Each bigger option shows what it pulls in.
- Offer "not yet" (and "by hand") as real options when nothing breaks today without the change.
- Recommend the option that does the ask correctly while pulling in the least, and explain why, conversationally. If a smaller option leaves the ask only partly working, say so; don't recommend it.

**What the spec covers:**

- Architecture, components, data flow, error handling, testing
- Scale each section to its complexity: a few sentences if straightforward, up to 200-300 words if nuanced

**Design for isolation and clarity:**

- Break the system into smaller units that each have one clear purpose, communicate through well-defined interfaces, and can be understood and tested independently
- For each unit, you should be able to answer: what does it do, how do you use it, and what does it depend on?
- Can someone understand what a unit does without reading its internals? Can you change the internals without breaking consumers? If not, the boundaries need work.
- Smaller, well-bounded units are also easier for you to work with: you reason better about code you can hold in context at once, and your edits are more reliable when files are focused. When a file grows large, that's often a signal that it's doing too much.

**Working in existing codebases:**

- Explore the current structure before proposing changes. Follow existing patterns.
- Where existing code has problems that affect the work (e.g., a file that's grown too large, unclear boundaries, tangled responsibilities), include targeted improvements as part of the design, the way a good developer improves code they're working in.
- Don't propose unrelated refactoring. Stay focused on what serves the current goal.

## After the Design (architectural path)

**Where the spec goes:**

- `spec.md` in diazo's planning folder, `docs/specs/YYYY-MM-DD-<topic>/` in the repo, committed on the work branch at each approval.
- If `gh repo view --json visibility --jq .visibility` prints `PUBLIC`, the folder goes in private tools-ops instead, at `~/GitHub/tools-workspace/tools-ops/docs/<repo>/specs/YYYY-MM-DD-<topic>/`, committed there under AGENTS.md's Git rules. Never commit it in the public repo.

**Spec Self-Review:**
After writing `spec.md` and before printing it, look at it with fresh eyes:

1. **Placeholder scan:** Any "TBD", "TODO", incomplete sections, or vague requirements? Fix them.
2. **Internal consistency:** Do any sections contradict each other? Does the architecture match the feature descriptions?
3. **Scope check:** Is this focused enough for a single implementation plan, or does it need decomposition? Does it carry anything that hasn't happened in real use? Move that to a follow-up line.
4. **Ambiguity check:** Could any requirement be interpreted two different ways? If so, pick one and make it explicit.

Fix any issues inline. No need to re-review: just fix and move on. No reviewer subagent for the spec; Court is its reviewer.

**Court's review:**
Court reviews the printed spec on diazo's page, where a change is a reopened decision, settled and printed again (the diazo skill says how). Only proceed once Court approves it there. Don't use galley for specs: it is for prose meant for people.

**Implementation:**

- Invoke the writing-plans skill to create the implementation plan
- Do NOT invoke any other skill. writing-plans is the next step.

## Visual Companion

A browser-based companion for showing mockups, diagrams, and visual options during a bounded design (the architectural path shows them on diazo's cards). Available as a tool, not a mode: it doesn't mean every question goes through the browser.

**Using the companion:** Court wants mockups built without asking first. When a question would be clearer shown than told (a real mockup, layout or diagram question, not merely a UI topic), start the server with `--open` and show it; say in one line that it's up.

**Per-question decision:** Decide FOR EACH QUESTION whether to use the browser or the terminal. The test: **would Court understand this better by seeing it than reading it?**

- **Use the browser** for content that IS visual: mockups, wireframes, layout comparisons, architecture diagrams, side-by-side visual designs
- **Use the terminal** for content that is text: requirements questions, conceptual choices, tradeoff lists, A/B/C/D text options, scope decisions

A question about a UI topic is not automatically a visual question. "What does personality mean in this context?" is a conceptual question: use the terminal. "Which wizard layout works better?" is a visual question: use the browser.

If Court agrees to the companion, read the detailed guide before proceeding: `visual-companion.md` in this skill's directory.
