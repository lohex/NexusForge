---
name: task-series-orchestrator
description: Explicitly requested phased implementation workflow. Plan dependencies as phase barriers, execute independent Task-Series entries through task_series_pool, review durable reports and actual changes, and create explicit retry attempts when needed. Do not activate automatically.
metadata:
  workflow: phased-task-series
  artifacts: markdown
---

# Task-Series Orchestrator

Use this skill only when the user explicitly requests the Task-Series workflow,
`task-series-orchestrator`, or phased delegation through `task_series_pool`.
Do not activate it merely because work could be parallelized. Do not combine it
with the older `orchestrator`/`multi_task` workflow for the same task.

The primary orchestrator owns architecture, interfaces, task decomposition,
phase boundaries, review, integration, retries and final validation. Child
sessions execute only bounded work whose contract is already decided.

The implementation is one plugin exposing two tools:

- `task_series`: run one complete series;
- `task_series_pool`: run a phase containing independent series.

Both tools use the same implementation/test/verification sequence. The pool
adds scheduling only; it must not call `task_series` recursively.

## 1. Plan before implementation

Inspect the request and repository first. Before editing production files or
delegating, create:

```text
plans/<task-slug>/
├── implementation-plan.md
├── tasks/
└── reports/
    ├── P01/
    └── P02/
```

The implementation plan is the source of truth and records:

- goal and observable completion criteria;
- repository findings, assumptions, scope and non-goals;
- architecture, public interfaces and invariants;
- task graph and topological phase assignment;
- implementation, test and report ownership paths;
- profile choice (`granite` or `ornith`) for every task;
- phase, task and final validation;
- status, review decision and report for every attempt.

## 2. Task contract

Every delegated Task Markdown must be independently understandable and begin
with JSON frontmatter between `---` markers:

```md
---
{
  "schema_version": 1,
  "task_id": "T04",
  "phase": "P02",
  "attempt": 1,
  "execution_profile": "granite",
  "plan_file": "plans/example/implementation-plan.md",
  "implementation_roots": ["src/parser.js"],
  "test_roots": ["tests/parser.test.mjs"],
  "tester_reference_roots": ["package.json", "tests/helpers"],
  "report_file": "plans/example/reports/P02/T04-parser-a01.md",
  "implementation_checks": ["node --check src/parser.js"],
  "verification_commands": ["node --test tests/parser.test.mjs"]
}
---
```

The Markdown body must state the plan section, one concrete objective, exact
public behavior, in-scope and out-of-scope paths, prerequisites, implementation
steps, independent-test requirements, acceptance criteria and validation.

The observable contract must be complete enough for the Spec-Tester to write
black-box tests without reading implementation paths. If it is not, keep the
work with the primary orchestrator and refine the task contract first.

## 3. Phase barriers

Partition the task graph into topological phases:

```text
P01: T01, T02, T03
P02: T04, T05       # depends only on accepted P01 tasks
P03: T06            # depends only on accepted P01/P02 tasks
```

Within one phase:

- no task may depend on another task in that same phase;
- all prerequisites must be accepted results from earlier phases;
- implementation, test and report ownership paths must be disjoint;
- shared registries, exports, lockfiles, integration and cross-cutting edits
  remain with the orchestrator or a later integration phase;
- a phase may contain more than three Granite tasks; the pool queues them;
- Granite and Ornith series are never inferred concurrently.

If two tasks are actually coupled, create separate phases or implement the
coupled work directly. `lane_order` is an execution choice, never a substitute
for a dependency.

## 4. Choose the execution profile

Use `granite` for a small, local, mechanical task with a settled interface and
comfortable fit in 32K context. Granite tasks run up to three series in
parallel.

Use `ornith` for a bounded task that needs stronger reasoning or more context:

- difficult algorithms or state logic;
- delicate local refactors;
- large relevant reading context;
- difficult debugging inside an already decided design;
- a precisely specified Granite retry that still needs stronger execution.

Ornith is still a subagent, not a second architect. Do not delegate open
architecture, cross-task integration, unclear requirements, phase review or
final product decisions to it. Ornith series run strictly one at a time, with
fresh implementer, Spec-Tester and verifier sessions.

For a mixed phase, default to `lane_order: "granite_first"`. This lets an
`ornith-orchestrator` resume directly into its already loaded model for review
after the Ornith lane. Use `ornith_first` only when the orchestrator has a
specific operational reason to make a complex independent report available
earlier. Document that reason in the plan.

## 5. Submit one phase

Before calling the pool:

1. verify all prerequisites are `accepted`;
2. reread every Task Markdown and its manifest;
3. check ownership disjointness and profile choices;
4. ensure task-specific verification commands do not require unfinished sibling
   tasks;
5. set the plan status to `running`;
6. make one `task_series_pool` call for the phase.

Example:

```text
task_series_pool({
  phase: "P02",
  lane_order: "granite_first",
  series: [
    {
      task_file: "plans/example/tasks/T04-parser.md",
      description: "Parser implementieren und prüfen"
    },
    {
      task_file: "plans/example/tasks/T05-cache.md",
      description: "Cache mit Ornith implementieren und prüfen"
    }
  ]
})
```

The profile is read from each Task Manifest; the caller cannot select arbitrary
agents or models. `task_series` may be used for one standalone series or a
single explicit retry, but the phase workflow uses `task_series_pool`.

Never launch two pool calls concurrently. Wait for the complete result before
reviewing it or starting a retry/next phase. The primary model and agent remain
unchanged throughout every pool.

## 6. Review barrier

The pool's short output is only a pointer. After it returns:

1. read every durable report completely;
2. inspect actual diffs and changed files in the primary session;
3. verify ownership boundaries and forbidden changes;
4. check that tests are derived from the observable contract, not private code;
5. reproduce unclear task-specific failures;
6. run phase-wide integration checks after all sibling series have stopped;
7. perform shared exports, registries and cross-cutting integration directly;
8. mark each task `accepted`, `retry_required` or `rejected`;
9. update the implementation plan and status matrix;
10. release the next phase only after all required predecessors are accepted.

Verifier sessions run task-specific commands only. Avoid global test suites
inside active parallel series because they can observe incomplete sibling
changes. Global validation belongs at this review barrier or the final review.

The live pool title, TUI milestone notifications and `.cache` status snapshot
are operational visibility only. The Markdown report and inspected diff are the
evidence used for acceptance.

## 7. Retry attempts

The plugin never retries automatically. A retry is a new orchestrator decision.
Keep previous Task Markdown and reports immutable:

```text
tasks/T04-parser.md
tasks/T04-parser-a02.md

reports/P02/T04-parser-a01.md
reports/P02R1/T04-parser-a02.md
```

The retry Task Markdown links the original task and previous report, states the
diagnosed cause, clarifies the changed instructions and says whether to build
on or replace the current changes. It runs the complete three-stage series
again.

After a Granite failure, the orchestrator may explicitly change the retry
manifest to `execution_profile: "ornith"` when review shows that stronger
reasoning is appropriate. This is never an automatic escalation. Do not reset
the worktree wholesale; decide explicitly how failed changes are handled.

After two failed attempts, reassess the architecture and contract before making
another attempt. A failed task blocks dependent phases even if unrelated tasks
in the same phase were accepted.

## 8. Status and completion

Use separate technical and review states:

```text
Pool: passed | failed | blocked_spec | infrastructure_error | stage_error | stale_spec | cancelled
Review: planned | running | reported | accepted | retry_required | rejected
```

Only `accepted` satisfies a dependency. Do not declare completion merely because
all child sessions returned. At completion, run the planned full test suite,
lint/type/build/integration checks, inspect all reports and open blockers, run
`git diff --check`, update the plan, and report the plan path, material changes,
validation and remaining risks to the user.

