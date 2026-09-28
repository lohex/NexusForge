import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

const root = new URL("../../", import.meta.url)

test("Ornith is the default orchestrator and Qwen text is knowledge-only", async () => {
  const config = JSON.parse(await readFile(new URL("opencode.json", root), "utf8"))

  assert.equal(config.model, "llama-ornith/ornith-1.5-9b-orchestrator")
  assert.equal(config.default_agent, "ornith-orchestrator")
  assert.equal(config.agent["ornith-orchestrator"].mode, "primary")
  assert.equal(config.agent["qwen-orchestrator"], undefined)

  const knowledge = config.agent["qwen-knowledge"]
  assert.equal(knowledge.mode, "subagent")
  assert.equal(knowledge.model, "llama-main/qwen3.5-9b-orchestrator")
  assert.equal(config.provider["llama-main"].models["qwen3.5-9b-orchestrator"].limit.context, 32768)
  assert.equal(knowledge.permission.edit, "allow")
  assert.equal(knowledge.permission.bash, "deny")
  assert.equal(knowledge.permission.task, "deny")
  assert.equal(config.agent["ornith-orchestrator"].permission.task["qwen-knowledge"], "allow")

  const router = await readFile(new URL("config/router-models.ini", root), "utf8")
  const preset = router.match(/\[qwen3\.5-9b-orchestrator\]([\s\S]*?)(?=\n\[|$)/)?.[1]
  assert.ok(preset, "Qwen 9B router preset must exist")
  assert.match(preset, /^ctx-size = 32768$/m)
  assert.match(preset, /^cache-type-k = q4_0$/m)
  assert.match(preset, /^cache-type-v = q4_0$/m)
  assert.doesNotMatch(preset, /^n-gpu-layers\s*=/m)
})

test("Qwen Vision is a routed image-capable read-only subagent", async () => {
  const config = JSON.parse(await readFile(new URL("opencode.json", root), "utf8"))
  const model = config.provider["llama-vision"].models["qwen3-vl-4b-instruct"]
  const agent = config.agent["qwen-vision"]

  assert.equal(model.attachment, true)
  assert.deepEqual(model.modalities.input, ["text", "image"])
  assert.deepEqual(model.modalities.output, ["text"])
  assert.equal(agent.mode, "subagent")
  assert.equal(agent.model, "llama-vision/qwen3-vl-4b-instruct")
  assert.equal(agent.permission.edit, "deny")
  assert.equal(agent.permission.bash, "deny")
  assert.equal(agent.permission.task, "deny")
  assert.equal(config.agent["ornith-orchestrator"].permission.task["qwen-vision"], "allow")

  const router = await readFile(new URL("config/router-models.ini", root), "utf8")
  const preset = router.match(/\[qwen3-vl-4b-instruct\]([\s\S]*?)(?=\n\[|$)/)?.[1]
  assert.ok(preset, "Qwen Vision router preset must exist")
  assert.match(preset, /^model = models\/qwen-vl-4b\/Qwen3VL-4B-Instruct-Q4_K_M\.gguf$/m)
  assert.match(preset, /^mmproj = models\/qwen-vl-4b\/mmproj-Qwen3VL-4B-Instruct-F16\.gguf$/m)
  assert.match(preset, /^ctx-size = 32768$/m)
})


test("Bonsai is a selectable primary agent with the existing delegation permissions", async () => {
  const config = JSON.parse(await readFile(new URL("opencode.json", root), "utf8"))
  const provider = config.provider["llama-bonsai"]
  const agent = config.agent["bonsai-orchestrator"]
  assert.equal(provider.options.baseURL, "http://127.0.0.1:8080/v1")
  assert.equal(agent.mode, "primary")
  assert.equal(agent.model, "llama-bonsai/bonsai-2-27b-ternary")
  assert.deepEqual(agent.permission.task, config.agent["ornith-orchestrator"].permission.task)

  const model = provider.models["bonsai-2-27b-ternary"]
  const launcher = await readFile(new URL("serving/serve_bonsai_2_27b.sh", root), "utf8")
  assert.ok(launcher.includes(`--alias ${agent.model.split("/")[1]}`))
  assert.ok(launcher.includes('CTX_SIZE="${CTX_SIZE:-' + model.limit.context + '}"'))
  assert.ok(model.limit.output < model.limit.context)
})
