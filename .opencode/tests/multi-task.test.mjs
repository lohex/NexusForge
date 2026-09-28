import assert from "node:assert/strict"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import { createOpencodeClient } from "@opencode-ai/sdk"

import { MultiTaskPlugin } from "../plugins/multi-task.js"

async function makeFixture(count = 3) {
  const worktree = await mkdtemp(join(tmpdir(), "nexusforge-multi-task-"))
  const taskDir = join(worktree, "plans", "fan-out", "tasks")
  await mkdir(taskDir, { recursive: true })
  const tasks = []
  for (let index = 1; index <= count; index += 1) {
    const number = String(index).padStart(2, "0")
    const task_file = `plans/fan-out/tasks/T${number}-worker-${index}.md`
    await writeFile(join(worktree, task_file), `# Worker ${index}\n`, "utf8")
    tasks.push({ task_file, description: `Worker ${index}` })
  }
  return { worktree, tasks }
}

function makeContext(worktree, controller = new AbortController()) {
  const permissions = []
  const metadata = []
  return {
    context: {
      sessionID: "ses_primary",
      messageID: "msg_primary",
      agent: "ornith-orchestrator",
      directory: worktree,
      worktree,
      abort: controller.signal,
      ask: async (request) => { permissions.push(request) },
      metadata: (value) => { metadata.push(value) },
    },
    permissions,
    metadata,
  }
}

async function setupWithFetch(fetch) {
  const client = createOpencodeClient({
    baseUrl: "http://opencode.test",
    headers: { Authorization: "Bearer test-only" },
    fetch,
  })
  return (await MultiTaskPlugin({ client })).tool.multi_task
}

test("fans three Task Markdown files out concurrently to fixed Granite child sessions", async () => {
  const fixture = await makeFixture()
  try {
    const creates = []
    const prompts = []
    let nextChild = 0
    let releasePrompts
    const promptGate = new Promise((resolve) => { releasePrompts = resolve })

    const tool = await setupWithFetch(async (request) => {
      const url = new URL(request.url)
      const body = await request.json()
      assert.equal(request.headers.get("Authorization"), "Bearer test-only")
      if (url.pathname === "/session") {
        const id = `ses_child_${++nextChild}`
        creates.push({ body, directory: url.searchParams.get("directory"), id })
        return Response.json({ id })
      }
      const match = url.pathname.match(/^\/session\/(ses_child_\d+)\/message$/)
      if (match) {
        prompts.push({ body, directory: url.searchParams.get("directory"), id: match[1] })
        if (prompts.length === fixture.tasks.length) releasePrompts()
        await promptGate
        return Response.json({
          info: { id: `msg_${match[1]}`, role: "assistant" },
          parts: [{ type: "text", text: `Completed ${match[1]}` }],
        })
      }
      return Response.json({ message: "Unexpected request" }, { status: 404 })
    })
    const state = makeContext(fixture.worktree)
    let timeout
    const result = await Promise.race([
      tool.execute({ tasks: fixture.tasks }, state.context),
      new Promise((_, reject) => {
        timeout = setTimeout(() => reject(new Error("fan-out did not run concurrently")), 2000)
      }),
    ]).finally(() => clearTimeout(timeout))

    assert.equal(creates.length, 3)
    assert.equal(prompts.length, 3)
    assert.deepEqual(creates.map((item) => item.body.parentID), Array(3).fill("ses_primary"))
    assert.ok(creates.every((item) => item.directory === fixture.worktree))
    assert.ok(prompts.every((item) => item.directory === fixture.worktree))
    for (const prompt of prompts) {
      assert.equal(prompt.body.agent, "granite-multi")
      assert.deepEqual(prompt.body.model, {
        providerID: "llama-granite",
        modelID: "granite-4.2-3b-multi",
      })
      assert.match(prompt.body.parts[0].text, /Read plans\/fan-out\/tasks\/T\d{2}-worker-\d\.md/)
    }
    assert.equal(state.permissions.length, 1)
    assert.equal(state.permissions[0].permission, "task")
    assert.deepEqual(state.permissions[0].patterns, ["granite-multi"])
    assert.equal(result.metadata.total, 3)
    assert.equal(result.metadata.succeeded, 3)
    assert.equal(result.metadata.failed, 0)
    assert.match(result.output, /Granite fan-out finished: 3\/3 tasks completed/)
    assert.equal(state.context.agent, "ornith-orchestrator")
  } finally {
    await rm(fixture.worktree, { recursive: true, force: true })
  }
})

test("validates bounded repository Task Markdown paths before asking permission", async () => {
  const fixture = await makeFixture(1)
  try {
    let requests = 0
    const tool = await setupWithFetch(async () => {
      requests += 1
      return Response.json({ message: "No request expected" }, { status: 500 })
    })
    const state = makeContext(fixture.worktree)

    await assert.rejects(
      tool.execute({ tasks: [fixture.tasks[0], fixture.tasks[0]] }, state.context),
      /duplicated/,
    )
    await assert.rejects(
      tool.execute({ tasks: [{ task_file: "README.md", description: "Wrong path" }] }, state.context),
      /plans\/<slug>\/tasks/,
    )
    await assert.rejects(
      tool.execute({ tasks: Array(4).fill(fixture.tasks[0]) }, state.context),
      /between 1 and 3/,
    )
    assert.equal(state.permissions.length, 0)
    assert.equal(requests, 0)
  } finally {
    await rm(fixture.worktree, { recursive: true, force: true })
  }
})

test("returns successful reports together with an isolated child failure", async () => {
  const fixture = await makeFixture()
  try {
    let nextChild = 0
    const tool = await setupWithFetch(async (request) => {
      const url = new URL(request.url)
      if (url.pathname === "/session") return Response.json({ id: `ses_child_${++nextChild}` })
      if (url.pathname === "/session/ses_child_2/message") {
        return Response.json({ message: "worker crashed" }, { status: 500 })
      }
      const id = url.pathname.split("/")[2]
      return Response.json({
        info: { id: `msg_${id}`, role: "assistant" },
        parts: [{ type: "text", text: `Completed ${id}` }],
      })
    })
    const state = makeContext(fixture.worktree)
    const result = await tool.execute({ tasks: fixture.tasks }, state.context)

    assert.equal(result.metadata.succeeded, 2)
    assert.equal(result.metadata.failed, 1)
    assert.equal(result.metadata.tasks[1].status, "failed")
    assert.match(result.output, /Granite fan-out finished: 2\/3 tasks completed/)
    assert.match(result.output, /worker crashed/)
  } finally {
    await rm(fixture.worktree, { recursive: true, force: true })
  }
})

test("aborts every created child when the primary tool call is cancelled", async () => {
  const fixture = await makeFixture(2)
  try {
    const controller = new AbortController()
    const aborted = []
    let nextChild = 0
    let started = 0
    let releaseStarted
    const allStarted = new Promise((resolve) => { releaseStarted = resolve })
    const client = {
      session: {
        create: async () => ({ data: { id: `ses_child_${++nextChild}` } }),
        prompt: async ({ signal }) => new Promise((resolve, reject) => {
          started += 1
          if (started === fixture.tasks.length) releaseStarted()
          signal.addEventListener("abort", () => reject(signal.reason), { once: true })
        }),
        abort: async ({ path }) => { aborted.push(path.id) },
      },
    }
    const tool = (await MultiTaskPlugin({ client })).tool.multi_task
    const state = makeContext(fixture.worktree, controller)
    const execution = tool.execute({ tasks: fixture.tasks }, state.context)
    await allStarted
    controller.abort()

    await assert.rejects(execution, { name: "AbortError" })
    assert.deepEqual(aborted.sort(), ["ses_child_1", "ses_child_2"])
  } finally {
    await rm(fixture.worktree, { recursive: true, force: true })
  }
})
