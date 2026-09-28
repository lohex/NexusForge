import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

const root = new URL("../../", import.meta.url)

test("verified-task accepts a direct request and delegates one complete cycle to task_series", async () => {
  const skill = await readFile(new URL(".opencode/skills/verified-task/SKILL.md", root), "utf8")

  assert.match(skill, /existing repository-relative Markdown\/plain-text spec or\s+a direct user instruction/)
  assert.match(skill, /create `plans\/<slug>\/spec\.md` from the instruction/)
  assert.match(skill, /No executable test file is required/)
  assert.match(skill, /implementation, test, and verification sessions/)
  assert.match(skill, /task_series\(\{/)
  assert.match(skill, /phase: "P01"/)
  assert.match(skill, /task_file: "plans\/<slug>\/tasks\/T01-<slug>\.md"/)
  assert.match(skill, /without reading implementation code/)
  assert.match(skill, /not a filesystem sandbox/)
  assert.match(skill, /Read the durable report/)
  assert.match(skill, /\*\*funktioniert\*\* or \*\*funktioniert nicht\*\*/)
  assert.doesNotMatch(skill, /task_series_pool\(\{/)
  assert.doesNotMatch(skill, /Task\(subagent_type=/)
})

test("task-series plugin provides the fresh agents used by the skill", async () => {
  const config = JSON.parse(await readFile(new URL("opencode.json", root), "utf8"))
  const plugin = await readFile(new URL(".opencode/plugins/task-series.js", root), "utf8")

  for (const name of ["ornith-series-implementer", "ornith-series-spec-tester", "ornith-series-verifier"]) {
    assert.equal(config.agent[name].mode, "subagent")
  }
  assert.match(plugin, /const STAGES = \["implementation", "tests", "verification"\]/)
  assert.match(plugin, /client\.session\.create\(/)
  assert.match(config.agent["ornith-series-spec-tester"].prompt, /Do not read or execute implementation paths/)
  assert.equal(config.agent["spec-test-writer"], undefined)
})
