import assert from "node:assert/strict"
import { access, readFile } from "node:fs/promises"
import { test } from "node:test"

const root = new URL("../../", import.meta.url)
const skillUrl = new URL(".opencode/skills/long-context/SKILL.md", root)

test("long-context skill delegates to a child without switching the primary model", async () => {
  const skill = await readFile(skillUrl, "utf8")

  assert.match(skill, /^name: long-context$/m)
  assert.match(skill, /Task\(subagent_type="long-context", \.\.\.\)/)
  assert.match(skill, /primary session keeps its original agent and\s+configured model/)
  assert.match(skill, /automatically reloads the original\s+orchestrator model/)
  assert.match(skill, /Do not call `switch_model` before or after delegation/)
  await assert.rejects(
    access(new URL(".opencode/skills/qwen-long-context/SKILL.md", root)),
    { code: "ENOENT" },
  )
})

test("long-context agent is a read-only subagent available to every primary orchestrator", async () => {
  const config = JSON.parse(await readFile(new URL("opencode.json", root), "utf8"))
  const child = config.agent["long-context"]

  assert.equal(child.mode, "subagent")
  assert.equal(child.model, "llama-long/qwen3.5-4b-long-context")
  assert.equal(child.permission.edit, "deny")
  assert.equal(child.permission.bash, "deny")
  assert.equal(child.permission.task, "deny")
  assert.equal(child.permission.switch_model, "deny")

  for (const name of ["qwen-orchestrator", "ornith-orchestrator", "granite-orchestrator"]) {
    assert.equal(config.agent[name].permission.task["long-context"], "allow")
  }
})
