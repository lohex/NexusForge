---
name: long-context
description: Delegate reading and evidence extraction from a document or file that is too large for the primary orchestrator's context window to the configured long-context subagent. Use for focused source analysis; keep synthesis and final decisions in the primary session.
---

# Long-Context Subagent

Use this workflow only for the oversized source that triggered the skill. The
primary orchestrator owns the question, interpretation, synthesis, and final
answer. The weaker long-context subagent is a focused reader: give it one precise
information need, not an open-ended research or implementation task.

The canonical model check is `serving/serve_qwen_long_context.sh --check`. It
validates the model, configuration, and llama-server without starting the
standalone server that would conflict with the NexusForge router on port 8080.

## Workflow

1. Resolve the repository root and run
   `serving/serve_qwen_long_context.sh --check`. Stop and report the error if the
   check fails. Do not start the standalone server in a router-backed session.
2. Make the source accessible to the child by a concrete file path, URL, or other
   stable identifier. Do not paste the entire oversized source into the Task
   prompt when the child can read it directly.
3. While the primary orchestrator model is active, emit one Task call:

   `Task(subagent_type="long-context", ...)`

   The prompt must include the source location, the exact information to extract,
   relevant terminology, required source locations such as headings, pages, or
   line numbers, and the desired report format. Tell the child to report findings,
   evidence locations, uncertainties, and missing information without editing
   files or attempting the final synthesis.
4. OpenCode creates a child session whose configured model is
   `llama-long/qwen3.5-4b-long-context`. Its first inference request causes the
   one-model-at-a-time router to unload the physically active orchestrator model
   and load Qwen Long Context. The primary session keeps its original agent and
   configured model while it waits for the Task result.
5. Run only one long-context child at a time because the router preset provides
   one long-context slot. When the child returns, OpenCode resumes the unchanged
   primary session; its next inference request automatically reloads the original
   orchestrator model.
6. Review the child report against the original request, fill only identified
   gaps with another narrowly scoped Task if necessary, and produce the final
   synthesis in the primary orchestrator.

Do not call `switch_model` before or after delegation. The Task child selects its
configured model, and the router performs physical model loading in response to
the child and parent inference requests.
