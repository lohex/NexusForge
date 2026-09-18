---
name: orchestrator
description: Plan and coordinate non-trivial implementation work with a local orchestrator model. Create a durable implementation-plan Markdown file, split independent small work into precise Task Markdown files, delegate those files directly to Granite multi subagents while preserving the primary orchestrator model, then review and integrate the results.
metadata:
  workflow: local-multi-agent
  artifacts: markdown
---

# Orchestrator Workflow

Use this skill for implementation work that benefits from an explicit design or
from multiple independent implementation tasks. The orchestrator owns the
architecture, interfaces, task boundaries, integration, and final validation.
Do not delegate a task merely to create parallel work.

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

## 4. Emit Task calls, then let the router load Granite

While the primary orchestrator model is still active, emit one Task tool call for
each ready Task Markdown:

`Task(subagent_type="granite-multi", ...)`

For dependency-free tasks, emit all independent Task calls in the same assistant
turn, up to the three Granite server slots. This is the last action the primary
model takes before OpenCode starts the child work; do not wait for one independent
task to finish before emitting the others.

The dispatch prompt must name exactly one Task Markdown path and tell the
subagent to read that file and its linked implementation plan before acting.
Do not duplicate or weaken the Task Markdown requirements in the prompt.

After the primary model has emitted the Task calls, OpenCode executes them and
creates a child session for each call. Each child uses the model configured on
the selected subagent, so its first inference requests
`llama-granite/granite-4.2-3b-multi`. At that point the one-model-at-a-time router
unloads the physically active orchestrator model and loads Granite. The primary
session itself is only waiting for tool results: its agent and configured model
do not change, and it cannot perform model inference concurrently with Granite.

The Granite child sessions can use the three Granite slots concurrently. After
all Task results for the turn have returned, OpenCode resumes the unchanged
primary session. Its next inference still requests the original orchestrator
model, causing the router to unload Granite and reload that model automatically.
Do not call `switch_model` before or after Granite delegation; the router swaps
the physically loaded model in response to child and parent inference requests.

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
