---
name: qwen-long-context
description: Temporarily use the local Qwen long-context model to read a long document or file, extract information required by the current request, and return the findings to the original model. Use when the relevant input is too large for the current model's context window.
---

# Qwen Long-Context Handoff

This workflow requires the `switch_model` plugin and the NexusForge llama.cpp router.
The canonical long-context launcher is `serving/serve_qwen_long_context.sh`;
it replaces the former `serve_qwen_long_context_new.sh` name.

Use this workflow only for the long document or file that triggered the skill.

1. Resolve the repository root, then run its
   `serving/serve_qwen_long_context.sh --check`. Stop and report its error if
   the model, configuration, or llama-server is unavailable. Do not launch the
   standalone server without `--check` during a router-backed OpenCode session
   because both processes would compete for port 8080.
2. Call `switch_model` with:
   - `model`: `llama-long/qwen3.5-4b-long-context`
   - `temporary`: `true`
   - `reason`: a short statement that long-context document analysis is needed
   - `handoff`: the file path or document identity, the user's exact information need, and any required output constraints
3. In the Qwen continuation, retain the exact `Previous model before this switch` identifier from the synthetic handoff. Read the requested source and extract only information relevant to the original request. Preserve useful source locations such as headings, page numbers, or line numbers.
4. Before returning, prepare a compact handoff containing:
   - the requested findings and supporting source locations;
   - uncertainties or missing information;
   - any remaining action the original model must perform.
5. Call `switch_model` again with the recorded previous model as `model`, `temporary: false`, a reason stating that extraction is complete, and the prepared findings as `handoff`.
6. In the original-model continuation, use the handed-off findings to finish the user's request. Re-read the large source only when the handoff identifies a specific gap.

If the previous model is already `llama-long/qwen3.5-4b-long-context`, analyze the source directly and do not perform a return switch. If a switch fails, report the error once and do not retry in a loop.
