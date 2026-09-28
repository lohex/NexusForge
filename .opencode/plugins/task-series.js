import { access, mkdir, readFile, realpath, rename, stat, writeFile } from "node:fs/promises"
import { createHash, randomUUID } from "node:crypto"
import { relative, resolve, sep, dirname } from "node:path"

import { tool } from "@opencode-ai/plugin"

const MAX_SERIES = 24
const MAX_TASK_BYTES = 128 * 1024
const MAX_REPORT_CHARS = 4000
const PHASE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/
const TASK_PATTERN = /^plans\/[^/]+\/tasks\/T\d{2}-[^/]+\.md$/

const PROFILES = {
  granite: {
    concurrency: 3,
    model: { providerID: "llama-granite", modelID: "granite-4.2-3b-multi" },
    agents: {
      implementation: "granite-implementer",
      tests: "granite-spec-tester",
      verification: "granite-verifier",
    },
  },
  ornith: {
    concurrency: 1,
    model: { providerID: "llama-ornith", modelID: "ornith-1.5-9b-orchestrator" },
    agents: {
      implementation: "ornith-series-implementer",
      tests: "ornith-series-spec-tester",
      verification: "ornith-series-verifier",
    },
  },
}

const STAGES = ["implementation", "tests", "verification"]

function unwrap(result) {
  return result?.data?.data ?? result?.data
}

function errorMessage(result, fallback) {
  const detail = result?.error?.data?.message ?? result?.error?.message ?? result?.error?.data
  return detail ? `${fallback}: ${String(detail)}` : fallback
}

function isWithin(root, target) {
  const path = relative(root, target)
  return path !== "" && path !== ".." && !path.startsWith(`..${sep}`) && !path.includes(`${sep}.git${sep}`)
}

function abortError(signal) {
  if (signal?.reason instanceof Error) return signal.reason
  return new DOMException("The task series was cancelled.", "AbortError")
}

function throwIfAborted(signal) {
  if (!signal?.aborted) return
  if (typeof signal.throwIfAborted === "function") signal.throwIfAborted()
  throw abortError(signal)
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex")
}

function parseManifest(source, taskFile) {
  if (!source.startsWith("---\n")) throw new Error(`Task Markdown has no JSON frontmatter: ${taskFile}`)
  const end = source.indexOf("\n---\n", 4)
  if (end < 0) throw new Error(`Task Markdown frontmatter is unterminated: ${taskFile}`)
  let manifest
  try {
    manifest = JSON.parse(source.slice(4, end).trim())
  } catch (error) {
    throw new Error(`Invalid task manifest: ${taskFile}`, { cause: error })
  }
  const allowed = new Set([
    "schema_version", "task_id", "phase", "attempt", "execution_profile",
    "plan_file", "implementation_roots", "test_roots", "tester_reference_roots",
    "report_file", "implementation_checks", "verification_commands",
  ])
  for (const key of Object.keys(manifest)) {
    if (!allowed.has(key)) throw new Error(`Unknown manifest field ${key}: ${taskFile}`)
  }
  return { manifest, body: source.slice(end + 5), digest: sha256(source) }
}

function normalizeRepoPath(path, label) {
  if (typeof path !== "string" || !path || path.includes("\\") || path.startsWith("/")) {
    throw new Error(`${label} must be a repository-relative POSIX path.`)
  }
  const parts = path.split("/")
  if (parts.some((part) => !part || part === "." || part === "..")) {
    throw new Error(`${label} contains an invalid path segment: ${path}`)
  }
  return path
}

async function ensureInside(worktree, path, label, allowMissing = false) {
  const candidate = resolve(worktree, normalizeRepoPath(path, label))
  if (await stat(candidate).then(() => true, () => false)) {
    const canonical = await realpath(candidate)
    if (!isWithin(worktree, canonical)) throw new Error(`${label} resolves outside the worktree: ${path}`)
    return canonical
  }
  if (!allowMissing) throw new Error(`${label} does not exist: ${path}`)
  let parent = dirname(candidate)
  while (parent !== worktree && !(await stat(parent).then(() => true, () => false))) parent = dirname(parent)
  const canonicalParent = await realpath(parent)
  if (canonicalParent !== worktree && !isWithin(worktree, canonicalParent)) {
    throw new Error(`${label} resolves outside the worktree: ${path}`)
  }
  return candidate
}

function overlaps(a, b) {
  return a === b || a.startsWith(`${b}/`) || b.startsWith(`${a}/`)
}

async function validateTask(task, phase, context) {
  const taskFile = normalizeRepoPath(String(task?.task_file ?? "").replaceAll("\\", "/"), "task_file")
  const description = String(task?.description ?? "").trim()
  if (!TASK_PATTERN.test(taskFile)) throw new Error(`Invalid task_file: ${taskFile}`)
  if (description.length < 3 || description.length > 120) throw new Error(`Invalid description for ${taskFile}`)
  const worktree = await realpath(context.worktree)
  const taskPath = await ensureInside(worktree, taskFile, "task_file")
  const details = await stat(taskPath)
  if (!details.isFile() || details.size > MAX_TASK_BYTES) throw new Error(`Invalid task file: ${taskFile}`)
  const parsed = parseManifest(await readFile(taskPath, "utf8"), taskFile)
  const m = parsed.manifest
  if (m.schema_version !== 1 || !/^T\d{2}$/.test(m.task_id) || m.phase !== phase) {
    throw new Error(`Manifest identity does not match ${taskFile}`)
  }
  if (!Number.isInteger(m.attempt) || m.attempt < 1) throw new Error(`Invalid attempt in ${taskFile}`)
  if (!Object.hasOwn(PROFILES, m.execution_profile)) throw new Error(`Invalid execution_profile in ${taskFile}`)
  await ensureInside(worktree, m.plan_file, "plan_file")
  const lists = ["implementation_roots", "test_roots", "tester_reference_roots"]
  for (const key of lists) {
    if (!Array.isArray(m[key])) throw new Error(`${key} must be an array: ${taskFile}`)
    for (const path of m[key]) await ensureInside(worktree, path, key, key !== "tester_reference_roots")
  }
  if (!Array.isArray(m.verification_commands) || m.verification_commands.length === 0) {
    throw new Error(`verification_commands must not be empty: ${taskFile}`)
  }
  if (!Array.isArray(m.implementation_checks)) throw new Error(`implementation_checks must be an array: ${taskFile}`)
  normalizeRepoPath(m.report_file, "report_file")
  if (!m.report_file.startsWith(`plans/${taskFile.split("/")[1]}/reports/${phase}/`)) {
    throw new Error(`report_file must be inside the phase report directory: ${taskFile}`)
  }
  await ensureInside(worktree, m.report_file, "report_file", true)
  try {
    await access(resolve(worktree, m.report_file))
    throw new Error(`Report already exists: ${m.report_file}`)
  } catch (error) {
    if (error?.message?.startsWith("Report already exists")) throw error
  }
  return { ...task, task_file: taskFile, description, manifest: m, digest: parsed.digest }
}

function validateOwnership(items) {
  const seenTasks = new Set()
  const implementation = []
  const tests = []
  const reports = new Set()
  for (const item of items) {
    if (seenTasks.has(item.task_file)) throw new Error(`Task Markdown is duplicated: ${item.task_file}`)
    seenTasks.add(item.task_file)
    const m = item.manifest
    if (reports.has(m.report_file)) throw new Error(`Report is duplicated: ${m.report_file}`)
    reports.add(m.report_file)
    for (const path of m.implementation_roots) {
      for (const other of implementation) if (overlaps(path, other)) throw new Error(`Implementation ownership overlaps: ${path}`)
      implementation.push(path)
    }
    for (const path of m.test_roots) {
      for (const other of tests) if (overlaps(path, other)) throw new Error(`Test ownership overlaps: ${path}`)
      tests.push(path)
      for (const owned of implementation) if (overlaps(path, owned)) throw new Error(`Implementation/test ownership overlaps: ${path}`)
    }
  }
}

function stagePrompt(item, stage, profile, peerSessions = {}) {
  const m = item.manifest
  const base = [
    `You are the ${stage} worker in the ${profile} task-series profile.`,
    `Read ${item.task_file} and its linked plan before acting.`,
    `Phase: ${m.phase}; task: ${m.task_id}; attempt: ${m.attempt}.`,
  ]
  if (stage === "implementation") return [...base,
    `Write only within: ${m.implementation_roots.join(", ")}.`,
    `Do not edit tests: ${m.test_roots.join(", ")}.`,
    `Run these implementation checks: ${m.implementation_checks.join(" | ") || "none"}.`,
    "Do not delegate or redesign the task. Return a concise report with changed files, checks, deviations and blockers.",
  ].join("\n")
  if (stage === "tests") return [...base,
    `Write only tests within: ${m.test_roots.join(", ")}.`,
    `Do not read, search, execute or infer from implementation paths: ${m.implementation_roots.join(", ")}.`,
    `Allowed reference paths: ${m.tester_reference_roots.join(", ") || "none"}.`,
    "Derive black-box tests only from the observable contract. Do not run the new tests. Return covered cases and specification gaps.",
  ].join("\n")
  return [...base,
    `Implementation session: ${peerSessions.implementation ?? "unknown"}. Test session: ${peerSessions.tests ?? "unknown"}.`,
    `Run verification commands in order: ${m.verification_commands.join(" | ")}.`,
    "Do not modify production or test files. Return JSON only with status, summary, changed_files, checks, findings, deviations and blockers.",
  ].join("\n")
}

function extractText(result, childID) {
  if (result?.error) throw new Error(errorMessage(result, `Child ${childID} failed`))
  const response = unwrap(result)
  if (!response?.info) throw new Error(errorMessage(result, `Child ${childID} returned no message`))
  if (response.info.error) throw new Error(`Child ${childID} model error`)
  const text = response.parts?.findLast?.((part) => part.type === "text")?.text?.trim()
  if (!text) throw new Error(`Child ${childID} returned no text`)
  return text.slice(0, MAX_REPORT_CHARS)
}

function parseVerification(text) {
  try {
    const value = JSON.parse(text)
    if (!["passed", "failed", "blocked_spec", "infrastructure_error"].includes(value.status)) throw new Error("invalid status")
    return value
  } catch {
    return { status: "stage_error", summary: "Verifier returned invalid JSON.", raw: text.slice(0, 1000) }
  }
}

async function writeReport(item, context, result) {
  const path = resolve(context.worktree, item.manifest.report_file)
  await mkdir(dirname(path), { recursive: true })
  const body = [
    `# ${item.manifest.task_id} – Task-Series Report`, "",
    `- Phase: \`${item.manifest.phase}\``,
    `- Attempt: \`${item.manifest.attempt}\``,
    `- Execution profile: \`${item.manifest.execution_profile}\``,
    `- Task: \`${item.task_file}\``,
    `- Status: \`${result.status}\``, "",
    "## Summary", "", result.summary ?? result.error ?? "No summary.", "",
    "## Changed files", "", ...(result.changed_files ?? []).map((file) => `- ${file}`), "",
    "## Checks", "", ...(result.checks ?? []).map((check) => `- ${check.command ?? check}: ${check.status ?? "unknown"}`), "",
    "## Findings", "", ...(result.findings ?? []).map((finding) => `- ${finding}`), "",
    "## Deviations", "", ...(result.deviations ?? []).map((deviation) => `- ${deviation}`), "",
    "## Blockers", "", ...(result.blockers ?? []).map((blocker) => `- ${blocker}`), "",
  ].join("\n")
  await writeFile(path, body, { encoding: "utf8", flag: "wx" })
  return item.manifest.report_file
}

async function runTaskSeries(item, runtime) {
  const profile = PROFILES[item.manifest.execution_profile]
  const sessions = {}
  const stageReports = {}
  for (const stage of STAGES) {
    throwIfAborted(runtime.signal)
    const current = { ...item, stage }
    runtime.update(item, stage)
    const created = await runtime.client.session.create({
      body: { parentID: runtime.parentID, title: `${item.description} (${stage}, ${item.manifest.execution_profile})` },
      query: runtime.directory ? { directory: runtime.directory } : undefined,
      signal: runtime.signal,
      throwOnError: false,
      responseStyle: "fields",
    })
    const child = unwrap(created)
    if (created?.error || !child?.id) throw new Error(errorMessage(created, `Could not create ${stage} session`))
    sessions[stage] = child.id
    runtime.childIDs.add(child.id)
    const prompted = await runtime.client.session.prompt({
      path: { id: child.id },
      query: runtime.directory ? { directory: runtime.directory } : undefined,
      body: {
        agent: profile.agents[stage],
        model: profile.model,
        parts: [{ type: "text", text: stagePrompt(current, stage, item.manifest.execution_profile, sessions) }],
      },
      signal: runtime.signal,
      throwOnError: false,
      responseStyle: "fields",
    })
    stageReports[stage] = extractText(prompted, child.id)
  }
  const verification = parseVerification(stageReports.verification)
  const reportFile = await writeReport(item, runtime.context, {
    ...verification,
    sessions,
    implementation_report: stageReports.implementation,
    test_report: stageReports.tests,
  })
  return { ...item, status: verification.status === "passed" ? "passed" : "failed", report_file: reportFile, sessions }
}

function publishProgress(context, state) {
  const completed = state.passed + state.failed + state.stageErrors
  context.metadata({
    title: `Pool ${state.phase} · ${state.currentLane ?? "done"} · ${completed}/${state.total} done · ${state.active.length} active`,
    metadata: {
      kind: "task-series-pool",
      phase: state.phase,
      current_lane: state.currentLane,
      total: state.total,
      queued: state.queued,
      passed: state.passed,
      failed: state.failed,
      stage_errors: state.stageErrors,
      active: state.active.slice(0, 3).map((item) => ({ task_id: item.taskID, profile: item.profile, stage: item.stage })),
      updated_at: new Date().toISOString(),
    },
  })
  void writeStatusSnapshot(context, state).catch(() => {})
}

function writeStatusSnapshot(context, state) {
  const snapshot = {
    phase: state.phase,
    state: state.state,
    current_lane: state.currentLane,
    total: state.total,
    queued: state.queued,
    passed: state.passed,
    failed: state.failed,
    stage_errors: state.stageErrors,
    active: state.active.slice(0, 3).map((item) => ({
      task_id: item.taskID,
      profile: item.profile,
      stage: item.stage,
      session_id: item.sessionID,
    })),
    updated_at: new Date().toISOString(),
  }
  const root = resolve(context.worktree, ".cache/task-series-pool", sha256(context.sessionID))
  const target = resolve(root, `${state.phase}.json`)
  state.statusWrites ??= Promise.resolve()
  state.statusWrites = state.statusWrites.catch(() => {}).then(async () => {
    await mkdir(root, { recursive: true })
    const temporary = resolve(root, `.${state.phase}.${randomUUID()}.tmp`)
    await writeFile(temporary, `${JSON.stringify(snapshot, null, 2)}\n`, { encoding: "utf8", flag: "wx" })
    await rename(temporary, target)
  })
  return state.statusWrites
}

async function validateInput(input, context, single = false) {
  if (!context.sessionID || !context.worktree) throw new Error("Task-Series requires a primary session and worktree.")
  const phase = String(input.phase ?? "")
  if (!PHASE_PATTERN.test(phase)) throw new Error("Invalid phase.")
  const raw = single ? [{ task_file: input.task_file, description: input.description }] : input.series
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_SERIES) throw new Error(`Expected 1-${MAX_SERIES} series.`)
  const items = []
  for (const task of raw) items.push(await validateTask(task, phase, context))
  validateOwnership(items)
  const profiles = new Set(items.map((item) => item.manifest.execution_profile))
  const laneOrder = single ? undefined : input.lane_order
  if (profiles.size > 1 && !["granite_first", "ornith_first"].includes(laneOrder)) throw new Error("Mixed profiles require lane_order.")
  if (profiles.size === 1 && laneOrder !== undefined) throw new Error("Homogeneous profiles must omit lane_order.")
  return { phase, items, laneOrder, profiles }
}

function makeRuntime(client, context, state, childIDs) {
  return {
    client,
    context,
    signal: context.abort,
    parentID: context.sessionID,
    directory: context.directory,
    childIDs,
    update(item, stage) {
      const active = state.active.find((entry) => entry.index === item.index)
      if (active) active.stage = stage
      state.updatedAt = Date.now()
      publishProgress(context, state)
    },
  }
}

async function runLane(items, concurrency, runtime, state) {
  const results = new Array(items.length)
  let next = 0
  async function worker() {
    while (true) {
      const index = next++
      if (index >= items.length) return
      const item = { ...items[index], index }
      const active = { index, taskID: item.manifest.task_id, profile: item.manifest.execution_profile, stage: "queued" }
      state.active.push(active)
      state.queued = Math.max(0, state.queued - 1)
      publishProgress(runtime.context, state)
      try {
        results[index] = await runTaskSeries(item, runtime)
        state.passed += results[index].status === "passed" ? 1 : 0
        state.failed += results[index].status === "failed" ? 1 : 0
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error)
        let reportFile
        try {
          reportFile = await writeReport(item, runtime.context, {
            status: "stage_error",
            summary: message,
            blockers: [message],
          })
        } catch (reportError) {
          reportFile = item.manifest.report_file
        }
        results[index] = { ...item, status: "stage_error", error: message, report_file: reportFile }
        state.stageErrors += 1
      } finally {
        state.active = state.active.filter((entry) => entry.index !== index)
        publishProgress(runtime.context, state)
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, () => worker()))
  return results
}

async function executePool(input, context, client, single = false) {
  throwIfAborted(context.abort)
  const validated = await validateInput(input, context, single)
  const state = { phase: validated.phase, state: "running", currentLane: null, total: validated.items.length, queued: validated.items.length, passed: 0, failed: 0, stageErrors: 0, active: [], updatedAt: Date.now() }
  const childIDs = new Set()
  const agents = [...new Set([...validated.profiles].flatMap((profile) => Object.values(PROFILES[profile].agents)))]
  await context.ask({ permission: "task", patterns: agents, always: ["*"], metadata: { description: `Run ${validated.items.length} task series`, phase: validated.phase, profiles: [...validated.profiles] } })
  const heartbeat = setInterval(() => publishProgress(context, state), 30_000)
  const abortChildren = () => {
    for (const id of childIDs) void client.session.abort({ path: { id }, query: context.directory ? { directory: context.directory } : undefined, throwOnError: false, responseStyle: "fields" }).catch(() => {})
  }
  context.abort?.addEventListener("abort", abortChildren, { once: true })
  try {
    const laneResults = []
    const lanes = validated.laneOrder === "ornith_first" ? ["ornith", "granite"] : ["granite", "ornith"]
    for (const lane of lanes) {
      const items = validated.items.filter((item) => item.manifest.execution_profile === lane)
      if (!items.length) continue
      state.currentLane = lane
      publishProgress(context, state)
      const completed = await runLane(items, PROFILES[lane].concurrency, makeRuntime(client, context, state, childIDs), state)
      laneResults.push(...completed)
    }
    const byTask = new Map(laneResults.map((result) => [result.task_file, result]))
    const results = validated.items.map((item) => byTask.get(item.task_file))
    state.currentLane = null
    state.state = "completed"
    publishProgress(context, state)
    await state.statusWrites
    return { title: `Task-series pool ${validated.phase}: ${state.passed}/${state.total} passed`, output: `Task-series pool ${validated.phase} finished: ${state.passed}/${state.total} passed.`, metadata: { phase: validated.phase, total: state.total, passed: state.passed, failed: state.failed, stage_errors: state.stageErrors, results } }
  } catch (error) {
    state.state = context.abort?.aborted ? "cancelled" : "failed"
    state.currentLane = null
    publishProgress(context, state)
    await state.statusWrites
    throw error
  } finally {
    clearInterval(heartbeat)
    context.abort?.removeEventListener("abort", abortChildren)
  }
}

export const TaskSeriesPlugin = async ({ client }) => ({
  tool: {
    task_series: tool({
      description: "Run one complete Task-Series with fresh implementation, spec-test and verification subagent sessions.",
      args: {
        phase: tool.schema.string().min(1),
        task_file: tool.schema.string().min(1),
        description: tool.schema.string().min(3).max(120),
      },
      async execute(input, context) {
        return executePool(input, context, client, true)
      },
    }),
    task_series_pool: tool({
      description: "Run independent Task-Series entries through Granite and/or serial Ornith lanes.",
      args: {
        phase: tool.schema.string().min(1),
        lane_order: tool.schema.enum(["granite_first", "ornith_first"]).optional(),
        series: tool.schema.array(tool.schema.object({
          task_file: tool.schema.string().min(1),
          description: tool.schema.string().min(3).max(120),
        })).min(1).max(MAX_SERIES),
      },
      async execute(input, context) {
        return executePool(input, context, client, false)
      },
    }),
  },
})
