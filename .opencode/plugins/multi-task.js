import { realpath, stat } from "node:fs/promises"
import { isAbsolute, relative, resolve, sep } from "node:path"

import { tool } from "@opencode-ai/plugin"

const SUBAGENT = "granite-multi"
const MODEL = {
  providerID: "llama-granite",
  modelID: "granite-4.2-3b-multi",
}
const MAX_TASKS = 3
const MAX_TASK_FILE_BYTES = 128 * 1024
const MAX_REPORT_CHARS = 6000
const TASK_FILE_PATTERN = /^plans\/[^/]+\/tasks\/T\d{2}-[^/]+\.md$/

function abortError(signal) {
  if (signal?.reason instanceof Error) return signal.reason
  return new DOMException("The multi_task batch was cancelled.", "AbortError")
}

function throwIfAborted(signal) {
  if (!signal?.aborted) return
  if (typeof signal.throwIfAborted === "function") signal.throwIfAborted()
  throw abortError(signal)
}

function unwrap(result) {
  return result?.data?.data ?? result?.data
}

function errorMessage(result, fallback) {
  const detail = result?.error?.data?.message
    ?? result?.error?.message
    ?? result?.error?.data
  const status = result?.response?.status
  if (detail) return `${fallback}: ${String(detail)}`
  if (status && (status < 200 || status >= 300)) return `${fallback} (HTTP ${status})`
  return fallback
}

function isWithin(root, target) {
  const path = relative(root, target)
  return path !== "" && path !== ".." && !path.startsWith(`..${sep}`) && !isAbsolute(path)
}

async function validateTaskFiles(tasks, context) {
  if (!Array.isArray(tasks) || tasks.length < 1 || tasks.length > MAX_TASKS) {
    throw new Error(`multi_task requires between 1 and ${MAX_TASKS} tasks.`)
  }
  if (!context.sessionID) throw new Error("multi_task requires a current primary session.")
  if (!context.worktree) throw new Error("multi_task requires the current worktree path.")

  const worktree = await realpath(context.worktree)
  const seen = new Set()
  return Promise.all(tasks.map(async (task, index) => {
    const number = index + 1
    const taskFile = task?.task_file?.trim()
    const description = task?.description?.trim()
    if (!taskFile || !description) {
      throw new Error(`Task ${number} requires task_file and description.`)
    }
    if (isAbsolute(taskFile) || !TASK_FILE_PATTERN.test(taskFile.replaceAll("\\", "/"))) {
      throw new Error(
        `Task ${number} must reference plans/<slug>/tasks/TNN-<slug>.md with a repository-relative path.`,
      )
    }
    if (seen.has(taskFile)) throw new Error(`Task Markdown is duplicated: ${taskFile}`)
    seen.add(taskFile)

    const candidate = resolve(worktree, taskFile)
    let canonical
    let details
    try {
      ;[canonical, details] = await Promise.all([realpath(candidate), stat(candidate)])
    } catch (error) {
      throw new Error(`Task Markdown does not exist or cannot be read: ${taskFile}`, { cause: error })
    }
    if (!isWithin(worktree, canonical)) {
      throw new Error(`Task Markdown resolves outside the current worktree: ${taskFile}`)
    }
    if (!details.isFile()) throw new Error(`Task Markdown is not a regular file: ${taskFile}`)
    if (details.size > MAX_TASK_FILE_BYTES) {
      throw new Error(`Task Markdown is too large (${details.size} bytes): ${taskFile}`)
    }

    return { task_file: taskFile.replaceAll("\\", "/"), description }
  }))
}

function taskPrompt(task) {
  return [
    `Execute exactly one bounded implementation task as the ${SUBAGENT} subagent.`,
    `Read ${task.task_file} and its linked implementation plan before acting.`,
    "Treat the Task Markdown as authoritative. Stay within its owned paths and do not redesign interfaces, integrate other tasks, or delegate further.",
    "Run the validation required by the Task Markdown.",
    "Return one concise report (at most 1000 words) containing changed files, checks run and their results, deviations, and blockers.",
  ].join("\n")
}

function extractReport(result, childID) {
  if (result?.error) throw new Error(errorMessage(result, `Granite child ${childID} failed`))
  const response = unwrap(result)
  if (!response?.info) throw new Error(errorMessage(result, `Granite child ${childID} returned no message`))
  if (response.info.error) {
    const detail = response.info.error?.data?.message ?? response.info.error?.name ?? "unknown model error"
    throw new Error(`Granite child ${childID} failed: ${detail}`)
  }
  const toolError = response.parts?.findLast?.(
    (part) => part.type === "tool" && part.state?.status === "error",
  )
  if (toolError) throw new Error(`Granite child ${childID} failed: ${toolError.state.error}`)
  const report = response.parts?.findLast?.((part) => part.type === "text")?.text?.trim()
  if (!report) throw new Error(`Granite child ${childID} returned no final text report.`)
  if (report.length <= MAX_REPORT_CHARS) return { report, truncated: false }
  return {
    report: `${report.slice(0, MAX_REPORT_CHARS)}\n\n[Report truncated by multi_task; inspect child session ${childID} for the remainder.]`,
    truncated: true,
  }
}

function formatOutput(results) {
  const succeeded = results.filter((result) => result.status === "completed").length
  const sections = results.map((result, index) => {
    const heading = `## Task ${index + 1}: ${result.description}`
    const details = [
      `- State: ${result.status}`,
      `- Task Markdown: ${result.task_file}`,
      `- Child session: ${result.sessionID ?? "not created"}`,
    ]
    if (result.truncated) details.push("- Report truncated: yes")
    return [heading, ...details, "", result.report ?? result.error].join("\n")
  })
  return {
    succeeded,
    output: [
      `Granite fan-out finished: ${succeeded}/${results.length} tasks completed.`,
      "Review the child changes and run integration validation in the unchanged primary session.",
      "",
      ...sections,
    ].join("\n"),
  }
}

export const MultiTaskPlugin = async ({ client }) => ({
  tool: {
    multi_task: tool({
      description:
        "Run one to three independent, bounded Task Markdown files concurrently in granite-multi child sessions. " +
        "Use this only while following the explicitly requested orchestrator skill, after the primary orchestrator has completed architecture and task decomposition. " +
        "This tool never changes the primary-session agent or model: it waits for the complete Granite batch, then returns all reports together. " +
        "Tasks must have disjoint owned paths and no unresolved dependencies. Do not use it for architecture, cross-cutting work, integration, review, or final validation.",
      args: {
        tasks: tool.schema.array(tool.schema.object({
          task_file: tool.schema.string().min(1).describe(
            "Repository-relative plans/<slug>/tasks/TNN-<slug>.md path",
          ),
          description: tool.schema.string().min(3).max(120).describe(
            "Short description of this bounded task",
          ),
        })).min(1).max(MAX_TASKS).describe("Independent Granite tasks to run concurrently"),
      },
      async execute({ tasks }, context) {
        throwIfAborted(context.abort)
        const validated = await validateTaskFiles(tasks, context)
        throwIfAborted(context.abort)

        await context.ask({
          permission: "task",
          patterns: [SUBAGENT],
          always: ["*"],
          metadata: {
            description: `Run ${validated.length} bounded Granite task${validated.length === 1 ? "" : "s"}`,
            subagent_type: SUBAGENT,
            task_files: validated.map((task) => task.task_file),
          },
        })
        throwIfAborted(context.abort)

        const childIDs = new Set()
        const abortChildren = () => {
          for (const id of childIDs) {
            void client.session.abort({
              path: { id },
              query: context.directory ? { directory: context.directory } : undefined,
              throwOnError: false,
              responseStyle: "fields",
            }).catch(() => {})
          }
        }
        context.abort?.addEventListener("abort", abortChildren, { once: true })

        context.metadata({
          title: `Granite fan-out (${validated.length})`,
          metadata: { subagent: SUBAGENT, model: `${MODEL.providerID}/${MODEL.modelID}` },
        })

        const runTask = async (task) => {
          throwIfAborted(context.abort)
          const created = await client.session.create({
            body: {
              parentID: context.sessionID,
              title: `${task.description} (@${SUBAGENT} subagent)`,
            },
            query: context.directory ? { directory: context.directory } : undefined,
            signal: context.abort,
            throwOnError: false,
            responseStyle: "fields",
          })
          const child = unwrap(created)
          if (created?.error || !child?.id) {
            throw new Error(errorMessage(created, `Could not create child session for ${task.task_file}`))
          }
          childIDs.add(child.id)
          throwIfAborted(context.abort)

          const prompted = await client.session.prompt({
            path: { id: child.id },
            query: context.directory ? { directory: context.directory } : undefined,
            body: {
              agent: SUBAGENT,
              model: MODEL,
              parts: [{ type: "text", text: taskPrompt(task) }],
            },
            signal: context.abort,
            throwOnError: false,
            responseStyle: "fields",
          })
          const extracted = extractReport(prompted, child.id)
          return { ...task, sessionID: child.id, status: "completed", ...extracted }
        }

        let settled
        try {
          settled = await Promise.allSettled(validated.map((task) => runTask(task)))
          throwIfAborted(context.abort)
        } finally {
          context.abort?.removeEventListener("abort", abortChildren)
        }

        const results = settled.map((result, index) => result.status === "fulfilled"
          ? result.value
          : {
              ...validated[index],
              status: "failed",
              error: result.reason instanceof Error ? result.reason.message : String(result.reason),
            })
        const formatted = formatOutput(results)
        const metadata = {
          subagent: SUBAGENT,
          model: `${MODEL.providerID}/${MODEL.modelID}`,
          total: results.length,
          succeeded: formatted.succeeded,
          failed: results.length - formatted.succeeded,
          tasks: results.map((result) => ({
            task_file: result.task_file,
            description: result.description,
            sessionID: result.sessionID,
            status: result.status,
            truncated: result.truncated ?? false,
          })),
        }
        context.metadata({
          title: `Granite fan-out: ${formatted.succeeded}/${results.length} completed`,
          metadata,
        })
        return {
          title: `Granite fan-out: ${formatted.succeeded}/${results.length} completed`,
          output: formatted.output,
          metadata,
        }
      },
    }),
  },
})
