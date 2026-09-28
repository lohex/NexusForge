---
name: orchestrator
description: Explicitly requested planning and delegation workflow for non-trivial implementation work. Create a durable implementation-plan Markdown file, split independent small work into precise Task Markdown files, fan those files out to Granite multi subagents while preserving the primary orchestrator model, then review and integrate the results. Do not activate automatically.
metadata:
  workflow: local-multi-agent
  artifacts: markdown
---

# Orchestrator Workflow

Use this skill only when the user explicitly asks for the `orchestrator` skill
or explicitly requests this plan-and-Granite delegation workflow. Do not select
it automatically merely because implementation work could be parallelized. The
orchestrator owns the architecture, interfaces, task boundaries, integration,
and final validation. Do not delegate a task merely to create parallel work.

This workflow requires the NexusForge llama.cpp router and the configured
`granite-multi` subagent. The primary session remains on its current
orchestrator agent and model throughout delegation. For example, an
`ornith-orchestrator` session remains an `ornith-orchestrator` session before,
during, and after Granite tasks run.

## 1. Plan before implementation

Inspect the request and the relevant repository state. Choose a short,
filesystem-safe task slug and create:

`plans/<slug>/implementation-plan.md`

The plan is the source of truth and must contain:

- the goal and observable completion criteria;
- relevant repository findings and assumptions;
- scope and explicit non-goals;
- the proposed structure, interfaces, and important decisions;
- an ordered task graph with dependencies and owned paths;
- integration risks and conflict boundaries;
- validation commands or other acceptance checks;
- a status section that the orchestrator keeps current.

Keep the plan proportional to the work, but create it before editing production
files or dispatching subagents. Revise it when implementation discoveries change
the design.

## 2. Decide what to delegate

The Granite multi subagents are less capable than the primary orchestrator.
Treat them as focused execution workers, not as planners or substitutes for the
primary model's reasoning. Give each subagent a narrow assignment with an
already-decided interface, explicit steps, limited file ownership, and an
unambiguous validation target.

Delegate only small, bounded tasks that have a clear result and can be completed
without redesigning the plan. Suitable tasks include a self-contained module,
focused refactor, tests for an agreed interface, documentation, or an independent
diagnostic investigation.

If a candidate task contains multiple objectives, requires choices between
architectures, spans unrelated paths, or combines investigation, implementation,
integration, and review, split it into multiple Task Markdown files first. Make
dependencies explicit and dispatch only the parts whose prerequisites and
interfaces are already settled. Prefer several small sequential tasks over one
large ambiguous task, even when that reduces parallelism.

Keep architecture decisions, cross-cutting changes, overlapping file ownership,
integration, and final review with the orchestrator. If work cannot be divided
into independent owned paths, implement it directly instead of forcing a
subagent split.

## 3. Write one Task Markdown per subagent

For every delegated task, create:

`plans/<slug>/tasks/TNN-<task-slug>.md`

Each Task Markdown must include:

- a link to `../implementation-plan.md` and the relevant plan section;
- one concrete objective and the expected deliverable;
- exact in-scope and out-of-scope paths;
- inputs, established interfaces, and dependencies;
- step-by-step requirements where ordering matters;
- constraints and invariants the subagent must preserve;
- acceptance criteria and exact validation commands;
- the required return report: changed files, checks run, results, and blockers.

Task files must be independently understandable after reading the linked plan.
Do not assign two concurrent tasks ownership of the same file. Do not ask a
subagent to infer requirements that the orchestrator can state explicitly. If
the objective cannot be explained precisely in one bounded Task Markdown, split
it again before dispatching it.

## 4. Fan out one ready task layer with `multi_task`

Once one to three Task Markdown files in the same dependency layer are ready,
invoke the `multi_task` tool exactly once. Pass each file as one item:

```text
multi_task({
  tasks: [
    { task_file: "plans/<slug>/tasks/T01-<slug>.md", description: "..." },
    { task_file: "plans/<slug>/tasks/T02-<slug>.md", description: "..." }
  ]
})
```

Include only tasks that are mutually independent, have disjoint owned paths, and
have all prerequisites satisfied. The plugin accepts at most three tasks because
the Granite server has three slots. If more tasks are ready, dispatch them in
dependency-aware batches of at most three and review each returned batch before
starting another. Do not make multiple `multi_task` calls in the same assistant
turn.

`multi_task` validates the repository-relative Task Markdown paths, obtains the
same `task` permission used for `granite-multi`, creates one child session per
file, and starts all child prompts concurrently. Every child is fixed to the
configured `granite-multi` agent and
`llama-granite/granite-4.2-3b-multi`; the caller cannot select another agent or
model. The plugin waits for the whole batch and returns the reports and child
session IDs together. Do not use OpenCode's background-task mode for this
workflow.

After the primary model emits the single `multi_task` call, it is waiting for
the tool result and performs no model inference. The three child requests cause
the one-model-at-a-time router to unload the physically active orchestrator
model and load Granite once. `parallel = 3` lets those child requests occupy
three Granite slots; it does not create tasks by itself. The primary session's
agent and configured model never change.

After all child results have returned, `multi_task` produces one combined tool
result and OpenCode resumes the unchanged primary session. Its next inference
still requests the original orchestrator model, causing the router to unload
Granite and reload that model automatically. Keep the primary model unchanged before
and after Granite delegation; the router swaps the physically loaded model in
response to child and parent inference requests.

Run dependent tasks only after their prerequisites have returned and the primary
orchestrator has been reloaded to review them.

## 5. Review, integrate, and verify in the primary session

Collect each subagent's report and inspect its actual changes in the unchanged
primary orchestrator session:

1. Check every result against its Task Markdown and the implementation plan.
2. Resolve integration issues and perform any cross-cutting edits directly.
3. Run the plan's final validation rather than relying only on subagent reports.
4. Update the plan status with completed tasks, deviations, and remaining work.
5. Report the plan path, material changes, validation, and any open risks to the
   user.

If a delegated task fails, record the failure in the plan and continue with the
safe work that remains. Do not retry failing subagents in a loop.
