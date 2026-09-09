# NexusForge

<p align="center">
  <img src="nexusforge.png" alt="NexusForge logo" width="320">
</p>

NexusForge is a local multi-agent coding system designed for efficient software development on consumer hardware.

It uses a larger language model as an **orchestrator** and smaller specialized models as parallel **implementation agents**.

## Architecture

```text
User
  │
  ▼
Qwen3.5-9B
Orchestrator
  │
  ├── Granite 4.2 3B → implementation task A
  ├── Granite 4.2 3B → implementation task B
  │
  ▼
Qwen3.5-9B
Review and integration
```

The orchestrator is responsible for:

* understanding the repository and user request
* decomposing work into independent tasks
* defining interfaces and constraints
* assigning tasks to implementation agents
* reviewing and integrating their results

The implementation agents focus on narrowly scoped coding tasks such as feature implementation, refactoring, testing, and debugging.

## Initial Setup

The initial configuration targets an NVIDIA GPU with 8 GB VRAM:

* **Orchestrator:** Qwen3.5-9B, Q4_K_M
* **Implementers:** Granite 4.2 3B, Q4_K_M
* **Inference:** llama.cpp / llama-server
* **Agent interface:** OpenCode
* **Development environment:** VS Code

Multiple Granite agents can share the same loaded model while operating in separate contexts and Git worktrees.

## Goals

NexusForge explores whether a relatively capable local orchestrator can coordinate multiple lightweight coding agents efficiently enough to provide a practical fully local software-engineering workflow.

Planned areas include:

* parallel task execution
* Git worktree isolation
* automated testing
* structured task delegation
* model switching based on task complexity
* integration and review by the orchestrator
