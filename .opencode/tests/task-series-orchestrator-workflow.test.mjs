import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

const root = new URL("../../", import.meta.url)

test("task-series orchestrator skill defines phased pool workflow", async () => {
  const skill = await readFile(new URL(".opencode/skills/task-series-orchestrator/SKILL.md", root), "utf8")
  assert.match(skill, /Do not activate it merely because work could be parallelized/)
  assert.match(skill, /task_series_pool/)
  assert.match(skill, /task_series.*one complete series/s)
  assert.match(skill, /no task may depend on another task in that same phase/)
  assert.match(skill, /Only `accepted` satisfies a dependency/)
  assert.match(skill, /lane_order: "granite_first"/)
  assert.match(skill, /Ornith series run strictly one at a time/)
  assert.match(skill, /Granite and Ornith series are never inferred concurrently/)
  assert.match(skill, /The plugin never retries automatically/)
  assert.match(skill, /execution_profile: "ornith"/)
  assert.match(skill, /Never launch two pool calls concurrently/)
  assert.match(skill, /primary model and agent remain\s+unchanged throughout every pool/)
  assert.match(skill, /read every durable report completely/)
})
