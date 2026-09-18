---
name: orchestrator
description: Plan and coordinate non-trivial implementation work with a local orchestrator model. Create a durable implementation-plan Markdown file, split independent small work into precise Task Markdown files, delegate those files to Granite multi subagents after loading the multi model with switch_model, then review and integrate the results.
metadata:
  workflow: local-multi-agent
  artifacts: markdown
---

# Orchestrator Workflow

Use this skill for implementation work that benefits from an explicit design or
from multiple independent implementation tasks. The orchestrator owns the
architecture, interfaces, task boundaries, integration, and final validation.
Do not delegate a task merely to create parallel work.

This workflow requires the NexusForge llama.cpp router, the `switch_model` tool,
and the configured `granite-multi` subagent.

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

Delegate only small, bounded tasks that have a clear result and can be completed
without redesigning the plan. Suitable tasks include a self-contained module,
focused refactor, tests for an agreed interface, documentation, or an independent
diagnostic investigation.

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
subagent to infer requirements that the orchestrator can state explicitly.

## 4. Load the multi model and dispatch

When at least one Task Markdown is ready, call `switch_model` once with:

- `model`: `llama-granite/granite-4.2-3b-multi`
- `temporary`: `true`
- `reason`: implementation of the prepared bounded tasks
- `handoff`: the implementation-plan path, every ready Task Markdown path,
  their dependency order, and the instruction to return to the recorded previous
  orchestrator model after all task results are collected

In the continuation, use the Task tool to invoke the `granite-multi` subagent.
The dispatch prompt must name exactly one Task Markdown path and tell the
subagent to read that file and its linked implementation plan before acting.
Do not duplicate or weaken the Task Markdown requirements in the prompt.

Run only dependency-free tasks concurrently, with no more concurrent tasks than
the active Granite server slots. The default preset provides two slots. Run
dependent tasks only after their prerequisites have been reviewed.

## 5. Return, integrate, and verify

Collect each subagent's report and inspect its actual changes. Then call
`switch_model` with the exact previous orchestrator model recorded in the
synthetic handoff, `temporary: false`, and a compact handoff containing task
outcomes, changed paths, validation results, and unresolved issues.

Back in the orchestrator model:

1. Check every result against its Task Markdown and the implementation plan.
2. Resolve integration issues and perform any cross-cutting edits directly.
3. Run the plan's final validation rather than relying only on subagent reports.
4. Update the plan status with completed tasks, deviations, and remaining work.
5. Report the plan path, material changes, validation, and any open risks to the
   user.

If `switch_model` or a delegated task fails, record the failure in the plan and
continue with the safe work that remains. Do not retry model switches or failing
subagents in a loop.
