import { tool } from "@opencode-ai/plugin"

// These are OpenCode provider/model IDs; the router receives only the model ID.
const models = [
  "llama-main/qwen3.5-9b-orchestrator",
  "llama-granite/granite-4.2-8b-orchestrator",
  "llama-ornith/ornith-1.5-9b-orchestrator",
]

async function getCurrentModel(transport, sessionID, signal) {
  try {
    const result = await transport.get({
      url: "/api/session/{sessionID}",
      path: { sessionID },
      signal,
      throwOnError: false,
      responseStyle: "fields",
    })
    if (result.response?.status !== 200) return undefined
    const session = result.data?.data ?? result.data
    const providerID = session?.model?.providerID
    const id = session?.model?.id
    return providerID && id ? `${providerID}/${id}` : undefined
  } catch {
    return undefined
  }
}

export const SwitchModelPlugin = async ({ client }) => ({
  tool: {
    switch_model: tool({
      description:
        "Switch the primary OpenCode session to a local NexusForge primary-session model for subsequent model calls. " +
        "Use only when the user explicitly requests a primary-session model change. " +
        "This tool changes only the primary-session model; subagent-only models are selected by the Task tool from the chosen subagent configuration. " +
        "Only orchestrator models are valid targets. " +
        "The conversation is retained; before switching to a smaller context window, compact it if needed. " +
        "The llama.cpp router must be running and handles loading on the next request. " +
        "Avoid repeatedly switching models within the same task.",
      args: {
        model: tool.schema.enum(models).describe("Target OpenCode provider/model ID"),
        reason: tool.schema.string().min(1).max(500).describe("Why this model is needed"),
        temporary: tool.schema.boolean().optional().describe(
          "Require the current model to be recorded so the target can return to it",
        ),
        handoff: tool.schema.string().max(16000).optional().describe(
          "Task context or extracted findings that the target model needs to continue",
        ),
      },
      async execute({ model, reason, temporary = false, handoff }, context) {
        if (!models.includes(model)) throw new Error(`Unsupported local model: ${model}`)
        if (!context.sessionID) throw new Error("Cannot switch models without a current session.")
        context.abort?.throwIfAborted()

        // OpenCode 1.18.30 injects the legacy SDK client into V1 plugins.
        // Its transport preserves the in-process fetch and authentication; the
        // model-switch route belongs to V2 and is not on client.session.
        const transport = client?._client
        if (typeof transport?.post !== "function") {
          throw new Error("switch_model requires the OpenCode 1.18.x plugin client transport.")
        }

        const previousModel = await getCurrentModel(transport, context.sessionID, context.abort)
        if (temporary && !previousModel) {
          throw new Error("Cannot start a temporary model switch because the current model could not be recorded.")
        }

        const [providerID, id] = model.split("/")
        const result = await transport.post({
          url: "/api/session/{sessionID}/model",
          path: { sessionID: context.sessionID },
          body: { model: { providerID, id } },
          headers: { "Content-Type": "application/json" },
          signal: context.abort,
          throwOnError: false,
          responseStyle: "fields",
        })

        // The switchModel API returns 204. Reject errors and HTML fallbacks from
        // incompatible servers instead of falsely reporting a successful switch.
        if (result.response?.status !== 204) {
          const detail = result.error?.message ?? result.error?.data?.message
          throw new Error(
            `Model switch failed (HTTP ${result.response?.status ?? "unknown"})` +
              (detail ? `: ${detail}` : ". Check that the target model is enabled in OpenCode."),
          )
        }

        // The 1.18.x loop resolves its model from the latest user message.
        // Updating session.model alone only affects later user prompts. Queue
        // a synthetic handoff without starting a second, concurrent agent loop.
        const continuation = [
          `The switch_model tool selected ${model}. Continue the existing task with this model.`,
          previousModel ? `Previous model before this switch: ${previousModel}.` : undefined,
          temporary
            ? `This switch is temporary. After completing the delegated work, call switch_model to return to ${previousModel}.`
            : undefined,
          `Switch reason: ${reason}`,
          handoff ? `Handoff context:\n${handoff}` : undefined,
          "Do not repeat the completed switch.",
        ].filter(Boolean).join("\n")
        const queued = await client.session.prompt({
          path: { id: context.sessionID },
          body: {
            noReply: true,
            agent: context.agent,
            model: { providerID, modelID: id },
            parts: [{
              type: "text",
              synthetic: true,
              text: continuation,
            }],
          },
          signal: context.abort,
          throwOnError: false,
          responseStyle: "fields",
        })
        if (queued.error || !queued.data?.info?.id) {
          throw new Error(
            `Session model was set to ${model}, but the continuation could not be queued. ` +
              "Send a new message to continue with the selected model.",
          )
        }

        return {
          title: `Model selected: ${model}`,
          output:
            `Session model set to ${model} for subsequent model calls. ` +
            `Previous model: ${previousModel ?? "unknown"}. Reason: ${reason}`,
          metadata: { model, previousModel, temporary, reason },
        }
      },
    }),
  },
})
