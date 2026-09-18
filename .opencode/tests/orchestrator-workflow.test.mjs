import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

const root = new URL("../../", import.meta.url)

test("orchestrator delegates directly without switching the primary model", async () => {
  const skill = await readFile(new URL(".opencode/skills/orchestrator/SKILL.md", root), "utf8")

  assert.match(skill, /Task\(subagent_type="granite-multi", \.\.\.\)/)
  assert.match(skill, /emit all independent Task calls in the same assistant\s+turn/)
  assert.match(skill, /primary session remains on its current\s+orchestrator agent and model/)
  assert.match(skill, /subagents are less capable than the primary orchestrator/)
  assert.match(skill, /split it into multiple Task Markdown files first/)
  assert.match(skill, /router\s+unloads the physically active orchestrator model and loads Granite/)
  assert.match(skill, /primary\s+session itself is only waiting for tool results/)
  assert.match(skill, /router to unload Granite and reload that model automatically/)
  assert.match(skill, /Do not call `switch_model` before or after Granite delegation/)
  assert.doesNotMatch(skill, /temporary: false|recorded previous orchestrator model|Load the multi model/)
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
