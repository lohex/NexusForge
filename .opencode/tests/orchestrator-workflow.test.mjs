import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

const root = new URL("../../", import.meta.url)

test("orchestrator uses one bounded fan-out call without switching the primary model", async () => {
  const skill = await readFile(new URL(".opencode/skills/orchestrator/SKILL.md", root), "utf8")

  assert.match(skill, /Use this skill only when the user explicitly asks/)
  assert.match(skill, /Do not select\s+it automatically/)
  assert.match(skill, /invoke the `multi_task` tool exactly once/)
  assert.match(skill, /Do not make multiple `multi_task` calls in the same assistant\s+turn/)
  assert.match(skill, /creates one child session per\s+file, and starts all child prompts concurrently/)
  assert.match(skill, /fixed to the\s+configured `granite-multi` agent/)
  assert.match(skill, /primary session remains on its current\s+orchestrator agent and model/)
  assert.match(skill, /subagents are less capable than the primary orchestrator/)
  assert.match(skill, /split it into multiple Task Markdown files first/)
  assert.match(skill, /router to unload the physically active orchestrator\s+model and load Granite once/)
  assert.match(skill, /primary session's\s+agent and configured model never change/)
  assert.match(skill, /router to unload\s+Granite and reload that model automatically/)
  assert.match(skill, /Keep the primary model unchanged before\s+and after Granite delegation/)
  assert.doesNotMatch(
    skill,
    /Task\(subagent_type="granite-multi"|temporary: false|recorded previous orchestrator model|Load the multi model/,
  )
})

test("Granite 3B remains a three-slot subagent-only model", async () => {
  const config = JSON.parse(await readFile(new URL("opencode.json", root), "utf8"))
  const granite = config.agent["granite-multi"]
  assert.equal(granite.mode, "subagent")
  assert.equal(granite.model, "llama-granite/granite-4.2-3b-multi")

  const router = await readFile(new URL("config/router-models.ini", root), "utf8")
  const section = router.match(/\[granite-4\.2-3b-multi\]([\s\S]*?)(?=\n\[|$)/)?.[1]
  assert.ok(section, "Granite 3B router section must exist")
  assert.match(section, /^parallel = 3$/m)
  assert.match(section, /^ctx-size = 98304$/m)
})
