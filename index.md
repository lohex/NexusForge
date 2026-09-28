# Agents Index

This file documents the agent-related configuration, tools, workflows, and tests
of the NexusForge OpenCode environment. It is organized by layer: the agent
definitions in `opencode.json`, the Node.js plugins that expose tools to agents,
the opt-in skills that define their workflows, and the tests that validate them.

## Agent definitions

`opencode.json` — The OpenCode configuration at the repository root. Its `agent`
section defines every agent and its permissions:

- **`ornith-orchestrator`** (primary, default) — the long-context primary agent
  that owns planning, architecture, delegation, integration, and final review.
- **`bonsai-orchestrator`** (primary, optional) — Bonsai 2 27B through the PrismML
  runtime and the shared router (the default backend of `serve_router.sh`).
- **`granite-orchestrator`** (primary, optional) — an optional Granite 8B primary
  agent for planning, integration, and review.
- **`qwen-knowledge`** (subagent) — answers focused knowledge/research questions
  and can create or edit files, including Markdown; allowed `edit`, denied `bash` and `task`.
- **`qwen-vision`** (subagent) — analyzes images/screenshots; denied
  `edit`, `bash`, and `task`.
- **`long-context`** (subagent) — reads one oversized source and returns focused
  findings with evidence locations; denied `edit`, `bash`, and `task`.
- **`granite-multi`** (subagent) — implements one small bounded task from a Task
  Markdown file; denied `task`.
- **`granite-implementer`** / **`granite-spec-tester`** / **`granite-verifier`**
  (subagents) — the three Granite workers of a Task-Series; each denied `task`.
- **`ornith-series-implementer`** / **`ornith-series-spec-tester`** /
  **`ornith-series-verifier`** (subagents) — the serial Ornith equivalents.
- **`test-file-implementer`** / **`test-file-test-writer`** / **`test-file-reviewer`**
  (subagents) — a sequential workflow that starts from one existing test file.

The `provider` section maps each model to the llama.cpp router endpoint
(`http://127.0.0.1:8080/v1`).

## Plugins (tools exposed to agents)

`.opencode/plugins/*.js` — Node.js OpenCode plugins. Each exports one tool that
agents call in their tool-use loop.


- **`multi-task.js`** — exposes `multi_task`. Fans out one to three independent
  Task Markdown files concurrently into `granite-multi` child sessions. Never
  changes the primary agent or model; waits for the whole batch, then returns all
  reports together. Validates repository-relative task paths and owned-path
  disjointness.
- **`task-series.js`** — exposes `task_series` and `task_series_pool`. Runs one
  complete Task-Series (implementation → spec-test → verification) through fresh
  subagent sessions, or schedules multiple independent series through Granite and
  serial Ornith lanes. Enforces phase barriers, ownership checks, and writes a
  Markdown report per task.

## Skills (opt-in workflows)

`.opencode/skills/*/*.md` — Markdown skills agents follow when explicitly
requested. None activate automatically.

- **`orchestrator`** — plan-and-Granite delegation. Requires a durable
  `implementation-plan.md`, decomposition into Task Markdown files, fan-out via
  `multi_task`, then review/integration in the primary session.
- **`task-series-orchestrator`** — phased implementation. Treats dependencies as
  phase barriers, runs entries through `task_series_pool`, and reviews durable
  reports before the next phase or an explicit retry.
- **`long-context`** — delegates reading of an oversized source to the
  `long-context` subagent, then synthesizes in the primary session.
- **`doc-search`** — searches online documentation for technical information.
- **`verified-task`** — creates a spec from the request if needed, then uses
  `task_series` for fresh implementation, black-box test, and verification sessions.

## Tests

`.opencode/tests/*.mjs` — Node.js test scripts (`node:test` + `assert`) that
validate the plugins and skills against their specifications.

- **`multi-task.test.mjs`** — validates the `multi_task` fan-out and validation.
- **`task-series.test.mjs`** / **`task-series-orchestrator-workflow.test.mjs`** —
  validate the Task-Series plugin and its phased workflow.
- **`orchestrator-workflow.test.mjs`** — validates the orchestrator skill workflow.
- **`long-context-workflow.test.mjs`** — validates the long-context workflow.
- **`verified-task-workflow.test.mjs`** — validates the verified-task workflow.
- **`model-roles.test.mjs`** — validates the agent/model role definitions in
  `opencode.json`.

## Related artifacts

- **`plans/*`** — durable plan trees produced by the orchestrator skill
  (`implementation-plan.md` and `tasks/TNN-*.md`).
- **`config/router-models.ini`** — the llama.cpp router presets that back the
  models agents switch between.
- **`README.md`** — the project overview, model table, and operational guidance.

## Shared model router

`serving/serve_router.sh` defaults to the PrismML runtime and
`config/router-models-bonsai.ini`: Bonsai plus the six existing models, one
loaded model at a time. `NEXUSFORGE_LLAMA_BACKEND=standard` selects the original
runtime and `config/router-models.ini` without Bonsai.
`router-backends.test.mjs` checks profile parity, context limits and selection.
