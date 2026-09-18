import assert from "node:assert/strict"
import { test } from "node:test"
import { createOpencodeClient } from "@opencode-ai/sdk"
import { SwitchModelPlugin } from "../plugins/switch-model.js"

const context = { sessionID: "ses_test", agent: "build", abort: new AbortController().signal }

async function setup(handler) {
  const client = createOpencodeClient({
    baseUrl: "http://opencode.test",
    headers: { Authorization: "Bearer test-only" },
    fetch: handler,
  })
  return (await SwitchModelPlugin({ client })).tool.switch_model
}

test("switches each supported target in the current session using the authenticated transport", async () => {
  const requests = []
  const tool = await setup(async (request) => {
    requests.push({
      url: request.url,
      method: request.method,
      auth: request.headers.get("Authorization"),
      body: request.method === "GET" ? undefined : await request.json(),
    })
    if (request.method === "GET") {
      return Response.json({
        data: { model: { providerID: "llama-ornith", id: "ornith-1.5-9b-orchestrator" } },
      })
    }
    return request.url.endsWith("/model")
      ? new Response(null, { status: 204 })
      : Response.json({ info: { id: "msg_handoff" }, parts: [] })
  })
  assert.deepEqual(tool.args.model.options, [
    "llama-main/qwen3.5-9b-orchestrator",
    "llama-granite/granite-4.2-3b-multi",
    "llama-granite/granite-4.2-8b-orchestrator",
    "llama-ornith/ornith-1.5-9b-orchestrator",
    "llama-long/qwen3.5-4b-long-context",
  ])
  for (const model of tool.args.model.options) {
    const result = await tool.execute({
      model,
      reason: "Requested by user",
      temporary: true,
      handoff: "Extract the requested evidence from the long document.",
    }, context)
    assert.equal(result.metadata.model, model)
    assert.equal(result.metadata.previousModel, "llama-ornith/ornith-1.5-9b-orchestrator")
    assert.equal(result.metadata.temporary, true)
    const [providerID, id] = model.split("/")
    assert.deepEqual(requests.at(-3), {
      url: "http://opencode.test/api/session/ses_test",
      method: "GET",
      auth: "Bearer test-only",
      body: undefined,
    })
    assert.deepEqual(requests.at(-2), {
      url: "http://opencode.test/api/session/ses_test/model",
      method: "POST",
      auth: "Bearer test-only",
      body: { model: { providerID, id } },
    })
    const handoff = requests.at(-1)
    assert.equal(handoff.url, "http://opencode.test/session/ses_test/message")
    assert.equal(handoff.auth, "Bearer test-only")
    assert.equal(handoff.method, "POST")
    assert.equal(handoff.body.noReply, true, "must not start a concurrent agent loop")
    assert.equal(handoff.body.agent, "build")
    assert.deepEqual(handoff.body.model, { providerID, modelID: id })
    assert.equal(handoff.body.parts[0].synthetic, true)
    assert.ok(handoff.body.parts[0].text.includes(model))
    assert.ok(handoff.body.parts[0].text.includes(
      "Previous model before this switch: llama-ornith/ornith-1.5-9b-orchestrator",
    ))
    assert.ok(handoff.body.parts[0].text.includes(
      "return to llama-ornith/ornith-1.5-9b-orchestrator",
    ))
    assert.ok(handoff.body.parts[0].text.includes("Extract the requested evidence"))
  }
  assert.equal(requests.length, 15)
})

test("rejects an unknown model or missing session before making a request", async () => {
  const tool = await setup(() => assert.fail("No request expected"))
  await assert.rejects(tool.execute({ model: "external/unknown" }, context), /Unsupported/)
  await assert.rejects(
    tool.execute({ model: "llama-main/qwen3.5-9b-orchestrator" }, {}),
    /current session/,
  )
})

test("does not switch after the current tool call is cancelled", async () => {
  const controller = new AbortController()
  controller.abort()
  const tool = await setup(() => assert.fail("No request expected"))
  await assert.rejects(
    tool.execute({ model: "llama-main/qwen3.5-9b-orchestrator" }, { ...context, abort: controller.signal }),
    { name: "AbortError" },
  )
})

test("reports API errors and rejects an HTML fallback", async () => {
  for (const status of [400, 401, 404, 500, 200]) {
    const tool = await setup(async () => status === 200
      ? new Response("<html>Not an API route</html>", { status, headers: { "Content-Type": "text/html" } })
      : Response.json({ message: "Switch rejected" }, { status }))
    await assert.rejects(
      tool.execute({ model: "llama-granite/granite-4.2-3b-multi", reason: "Test" }, context),
      new RegExp(`Model switch failed \\(HTTP ${status}\\)`),
    )
  }
})

test("reports transport errors and incompatible SDKs", async () => {
  const tool = await setup(async () => { throw new Error("Connection unavailable") })
  await assert.rejects(
    tool.execute({ model: "llama-main/qwen3.5-9b-orchestrator" }, context),
    /Model switch failed|Connection unavailable/,
  )
  const incompatible = (await SwitchModelPlugin({ client: {} })).tool.switch_model
  await assert.rejects(
    incompatible.execute({ model: "llama-main/qwen3.5-9b-orchestrator" }, context),
    /transport/,
  )
})

test("reports a partial switch when the continuation cannot be queued", async () => {
  const tool = await setup(async (request) => request.url.endsWith("/model")
    ? new Response(null, { status: 204 })
    : Response.json({ message: "Failed to queue" }, { status: 500 }))
  await assert.rejects(
    tool.execute({ model: "llama-main/qwen3.5-9b-orchestrator", reason: "Test" }, context),
    /Session model was set.*continuation could not be queued/,
  )
})

test("does not start a temporary handoff if the original model cannot be recorded", async () => {
  const requests = []
  const tool = await setup(async (request) => {
    requests.push(request)
    return Response.json({ message: "Session unavailable" }, { status: 503 })
  })
  await assert.rejects(
    tool.execute({
      model: "llama-long/qwen3.5-4b-long-context",
      reason: "Read a long file",
      temporary: true,
    }, context),
    /current model could not be recorded/,
  )
  assert.equal(requests.length, 1)
  assert.equal(requests[0].method, "GET")
})
