---
name: verified-task
description: Run one implementation, independent spec-test, and verification cycle from a specification file or a direct user request, using the task_series plugin without a pool.
metadata:
  workflow: single-spec-series
  artifacts: specification-and-tests
---

# Verified Task

Use this skill for one complete implementation → independent tests →
verification cycle. Use the `task_series` tool from the Task-Series plugin;
never use `task_series_pool` for this workflow. The plugin creates fresh
implementation, test, and verification sessions in that order. The primary
agent prepares the contract and reviews the result, but does not implement or
write tests outside the series.

## 1. Establish the specification

The input may be an existing repository-relative Markdown/plain-text spec or
a direct user instruction. No executable test file is required. If there is no
spec file, create `plans/<slug>/spec.md` from the instruction before starting
the series. Record observable behavior, acceptance criteria, relevant inputs
and outputs, and explicit assumptions; preserve the user's intent rather than
inventing requirements. If a missing decision would materially change the
feature, ask the user before creating the task contract. Keep an existing spec
unchanged unless the user asks to revise it. If it contains implementation
code or private design notes, create a separate behavioral spec for the test
session and leave the original file untouched. Use that behavioral spec as the
working spec throughout the Task-Series entry.

Inspect repository conventions and choose the public interface, disjoint
implementation and test paths, allowed tester references, and focused check
commands. The spec and task contract must let a tester write black-box tests
without reading implementation code. Do not include source snippets, private
branches, or implementation findings in tester-visible documents.

## 2. Prepare one Task-Series entry

Create a concise `plans/<slug>/implementation-plan.md` linking the spec and a
single `plans/<slug>/tasks/T01-<slug>.md` with JSON frontmatter required by the
plugin. Use one phase (`P01`), one task (`T01`), attempt `1`, and the `ornith`
execution profile unless the task is clearly small enough for `granite`. Set
`implementation_roots`, `test_roots`, `tester_reference_roots`,
`implementation_checks`, and `verification_commands` to repository-relative
paths and real commands. Keep implementation and test ownership disjoint.
The report path must be `plans/<slug>/reports/P01/T01-<slug>-a01.md`.

Use this frontmatter shape, replacing placeholders with real paths and checks:

```md
---
{
  "schema_version": 1,
  "task_id": "T01",
  "phase": "P01",
  "attempt": 1,
  "execution_profile": "ornith",
  "plan_file": "plans/<slug>/implementation-plan.md",
  "implementation_roots": ["<production-path>"],
  "test_roots": ["<test-path>"],
  "tester_reference_roots": ["plans/<slug>/spec.md", "plans/<slug>/implementation-plan.md"],
  "report_file": "plans/<slug>/reports/P01/T01-<slug>-a01.md",
  "implementation_checks": ["<implementation-only-check>"],
  "verification_commands": ["<focused-test-command>"]
}
---
```

For a working spec at another path, use that path in the task body and
`tester_reference_roots`. Add test framework configuration or fixtures there
only if the test writer needs them; every listed reference path must exist.

The task body must instruct each worker to read the spec and state the
observable contract, public API/import path, owned paths, acceptance criteria,
and validation. Its linked plan must be safe for the test writer to read:
describe the intended public behavior and scope, not the implementation
discovered or written later. Do not edit the task or plan after the series
begins.

Call exactly one `task_series` for this entry and wait for completion:

```text
task_series({
  phase: "P01",
  task_file: "plans/<slug>/tasks/T01-<slug>.md",
  description: "<short feature description>"
})
```

The plugin's test session must derive cases from the spec and public contract.
Its no-code-inspection rule is instructional: all sessions share a worktree,
so this is not a filesystem sandbox. Do not pass implementation output to the
test session or manually run a second test-writing session.

## 3. Review and report

Read the durable report, inspect the actual changes, and run any appropriate
integration or regression checks outside the series. Check that tests cover
observable requirements and were not weakened, skipped, or tailored to private
code. Treat plugin status as evidence to review, not automatic acceptance.

Finish with **funktioniert** or **funktioniert nicht**, the spec and report
paths, checks performed, and reasons for failures or untested requirements.
If a retry is justified, decide explicitly and create a new attempt rather
than overwriting the original task or report; never start a pool or retry
automatically.
