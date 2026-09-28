import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { test } from "node:test"

const root = new URL("../../", import.meta.url)
function sections(text) {
  const result = {}
  let section
  for (const raw of text.split("\n")) {
    const line = raw.trim()
    if (!line || line.startsWith(";")) continue
    if (line.startsWith("[")) { section = line.slice(1, -1); result[section] = {}; continue }
    if (!section) continue
    const i = line.indexOf("=")
    result[section][line.slice(0, i).trim()] = line.slice(i + 1).trim()
  }
  return result
}

test("shared router preserves existing profiles and matches all OpenCode context limits", async () => {
  const standard = sections(await readFile(new URL("config/router-models.ini", root), "utf8"))
  const shared = sections(await readFile(new URL("config/router-models-bonsai.ini", root), "utf8"))
  for (const [id, values] of Object.entries(standard)) assert.deepEqual(shared[id], values, id)
  const config = JSON.parse(await readFile(new URL("opencode.json", root), "utf8"))
  for (const provider of Object.values(config.provider)) {
    for (const [id, model] of Object.entries(provider.models)) {
      assert.ok(shared[id], `Missing preset: ${id}`)
      const profile = { ...shared["*"], ...shared[id] }
      assert.equal(Number(profile["ctx-size"]) / Number(profile.parallel), model.limit.context, id)
    }
  }
  assert.equal(shared["bonsai-2-27b-ternary"]["min-p"], "0.05")
  assert.equal(shared["bonsai-2-27b-ternary"]["fit-target"], "768")
  assert.equal(shared["bonsai-2-27b-ternary"]["cache-type-k"], "q4_0")
  assert.equal(shared["bonsai-2-27b-ternary"]["cache-type-v"], "q4_0")
  assert.equal(shared["qwen3-vl-4b-instruct"]["cache-type-k"], "q8_0")
  assert.equal(shared["qwen3-vl-4b-instruct"]["cache-type-v"], "q8_0")
  assert.equal(shared["qwen3-vl-4b-instruct"]["n-gpu-layers"], undefined)
  for (const values of Object.values(shared)) assert.notEqual(values["load-on-startup"], "true")
  assert.equal(standard["bonsai-2-27b-ternary"], undefined)
})

test("router selects runtime and presets together from any working directory", () => {
  const script = fileURLToPath(new URL("serving/serve_router.sh", root))
  for (const backend of ["bonsai", "standard"]) {
    const result = spawnSync("bash", [script, "--dry-run"], {
      cwd: "/tmp", encoding: "utf8",
      env: { ...process.env, NEXUSFORGE_LLAMA_BACKEND: backend, BONSAI_LLAMA_DIR: "/tmp/custom-fork", PORT: "8099" },
    })
    assert.equal(result.status, 0, result.stderr)
    assert.ok(result.stdout.includes(backend === "bonsai" ? "/tmp/custom-fork/build/bin/llama-server" : "/llama.cpp/build/bin/llama-server"))
    assert.ok(result.stdout.includes(backend === "bonsai" ? "router-models-bonsai.ini" : "router-models.ini"))
    assert.match(result.stdout, /--models-max 1 --models-autoload/)
    assert.match(result.stdout, /--port 8099/)
    assert.doesNotMatch(result.stdout, /--ctx-size|--min-p|--fit-target/)
  }
  const invalid = spawnSync("bash", [script, "--dry-run"], {
    encoding: "utf8", env: { ...process.env, NEXUSFORGE_LLAMA_BACKEND: "typo" },
  })
  assert.equal(invalid.status, 2)
})
