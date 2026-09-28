# NexusForge

<p align="center">
  <img src="nexusforge.png" alt="NexusForge logo" width="320">
</p>

NexusForge is a local OpenCode environment for running several specialized
language models on consumer hardware. The current setup targets an NVIDIA GPU
with 8 GB VRAM and uses llama.cpp as an OpenAI-compatible inference server.

The llama.cpp router keeps at most one model in VRAM. OpenCode can therefore
retain one conversation while switching between coding, reasoning, and
long-context models.

## Repository layout

```text
NexusForge/
├── installations/       model, llama.cpp, and OpenCode installers
├── serving/             router and standalone serving scripts
├── config/              llama.cpp router and long-context settings
├── models/              downloaded GGUF models
├── llama.cpp/           local llama.cpp checkout and build
├── .opencode/
│   ├── plugins/         primary model switching and Granite fan-out plugins
│   ├── skills/          OpenCode skills
│   └── tests/           plugin tests
├── opencode.json        local provider and model definitions
└── opencode.sh          project-local OpenCode launcher with Exa enabled
```

Installation and serving scripts resolve the repository root from their own
location. They can therefore be invoked through an absolute path or from the
repository root without depending on the current working directory.

## Models

| Model | OpenCode ID | Context | Intended use |
|---|---|---:|---|
| Ornith 1.5 9B | `llama-ornith/ornith-1.5-9b-orchestrator` | 128K | default reasoning and coding orchestrator |
| Qwen3.5 9B | `llama-main/qwen3.5-9b-orchestrator` | 32K | subagent-only knowledge and research questions |
| Qwen3-VL 4B | `llama-vision/qwen3-vl-4b-instruct` | 32K | subagent-only image and screenshot analysis |
| Granite 4.2 8B | `llama-granite/granite-4.2-8b-orchestrator` | 16K | optional orchestrator |
| Qwen3.5 4B | `llama-long/qwen3.5-4b-long-context` | 512K | subagent-only large-source extraction |
| Granite 4.2 3B | `llama-granite/granite-4.2-3b-multi` | 32K per slot | subagent-only parallel implementation |

Ornith owns planning and integration by default. The older Qwen 9B model ID
retains its `-orchestrator` suffix for router compatibility but is exposed only
through the `qwen-knowledge` subagent. `-long-context` is used for large-source
extraction, and `-multi` models execute small bounded tasks. Granite 3B uses
three 32K subagent slots by default and is never selected as the primary-session
model. Qwen Long Context is likewise selected only through its `long-context`
subagent, while Qwen3-VL is selected through `qwen-vision`.
It keeps its quantized KV cache in system RAM to make the 512K context practical
on an 8 GB GPU.

## Installation

The main installer sets up the project-local Hugging Face CLI and OpenCode,
downloads Qwen3.5 9B and Granite 3B, builds llama.cpp with CUDA, and keeps its
caches below the repository:

```bash
./installations/install.sh
```

Install optional models separately:

```bash
./installations/install_granite_8b.sh
./installations/install_ornith.sh
./installations/install_qwen_long_context.sh
./installations/install_gemma4-26B-a4b.sh
# Qwen3-VL-4B (Vision/Language, router subagent and optional standalone server)
./installations/install_qwen_vl_4b.sh
# Qianfan-OCR (Vision/OCR, vLLM)
./installations/install_qianfan_ocr.sh
```

The installers are resumable and skip model files that already pass their size
or checksum validation. Gemma 4 26B A4B is currently an optional standalone
experiment and is not registered in the OpenCode router configuration.

Qwen3-VL-4B is registered in the model router with both its language-model GGUF
and image projector (`mmproj`), so OpenCode can invoke it through the
`qwen-vision` subagent. For direct standalone experiments, stop the router and
start its OpenAI-compatible vision server with:

```bash
./serving/serve_qwen_vl_4b.sh
```

Use `./serving/serve_qwen_vl_4b.sh --check` to validate both files without
starting the server. The default endpoint is `http://127.0.0.1:8080/v1`.

Qianfan-OCR uses the official `ggml-org/Qianfan-OCR-GGUF` quantization with
llama.cpp. Install its GGUF model files with
`./installations/install_qianfan_ocr.sh`, then start
`./serving/serve_qianfan_ocr.sh`. Its default OpenAI-compatible endpoint is
`http://127.0.0.1:8080/v1`.

## Recommended operation: router plus OpenCode

A plain `./opencode.sh` starts the router if needed. For a manual start:

```bash
./serving/serve_router.sh
```

The router uses the PrismML runtime in `llama.cpp-bonsai/` and reads
[config/router-models-bonsai.ini](config/router-models-bonsai.ini). It loads
models on demand, and unloads the previous model when another one is requested.
It exposes all configured models through `http://127.0.0.1:8080/v1` while
keeping at most one model loaded.

In a second terminal, start OpenCode with a configured orchestrator profile:

```bash
./opencode.sh --agent ornith-orchestrator
```

To work in another repository while retaining the NexusForge providers, agents,
skills, and plugins, pass that repository as the first positional argument:

```bash
/home/lorenz/Environments/NexusForge/opencode.sh /path/to/target-repo \
  --agent ornith-orchestrator
```

If the positional path is omitted, OpenCode uses the shell's current working
directory. The wrapper exports `OPENCODE_CONFIG`, `OPENCODE_CONFIG_DIR`, and
`NEXUSFORGE_HOME`; configuration from the target repository is still discovered
and merged by OpenCode.

`opencode.sh` checks `http://127.0.0.1:8080/models` when starting an
interactive session, `run`, `serve` or `web`. If the selected NexusForge router
is absent, it starts `serving/serve_router.sh` in the background, waits until
ready, and writes a log under `.cache/router/`. A compatible running router is
reused. An incompatible server on port 8080 stops the launch with an error;
no process is killed. `NEXUSFORGE_ROUTER_AUTOSTART=0` disables this behavior
(for example, for a remote model API). `--help`, `debug`, `agent` and similar
management commands never start the router. The default backend is Bonsai;
`NEXUSFORGE_LLAMA_BACKEND=standard` selects the original llama.cpp router.
The router does not stop automatically when OpenCode exits.

`opencode.sh` uses the project-local OpenCode installation and enables Exa web
search for the local providers. Use `/models` inside OpenCode for an interactive
primary-session model change.
The `ornith-orchestrator` profile is the default primary agent. Qwen 9B and
Qwen3-VL are available as the `qwen-knowledge` and `qwen-vision` subagents;
Granite 8B remains an optional primary orchestrator selectable with the Tab key.

Inspect the router without loading a model:

```bash
curl -s http://127.0.0.1:8080/models
```

Loading another model and rebuilding its prompt cache takes time. Wait for an
active response to finish before manually switching. Compact a long conversation
before moving to a model whose context window is smaller than the conversation.

## Router backend selection

Install Bonsai and its runtime with `./installations/install_bonsai_2_27b.sh`.
Rerun it for an existing installation to apply and build the bundled scheduler
fix for overlapping requests to different models. Verified weights are reused.
The default `./serving/serve_router.sh` serves Bonsai plus all six existing
models on port 8080. Existing model weights must already be installed.
`BONSAI_LLAMA_DIR` can override the fork directory; model paths are in the INI.

```bash
./serving/serve_router.sh --check
./serving/serve_router.sh --dry-run
./serving/serve_router.sh
# In another terminal:
./opencode.sh --agent bonsai-orchestrator
```

To use the original runtime with the six original models, stop the running
router and start:

```bash
NEXUSFORGE_LLAMA_BACKEND=standard ./serving/serve_router.sh
```

This fallback reads `config/router-models.ini`; Bonsai requires the fork and is
unavailable on the standard backend. There is no automatic backend fallback.
Runtime test results and remaining limitations are recorded in
[TODO/bonsai-router-verifikation.md](TODO/bonsai-router-verifikation.md).
The standalone `serve_bonsai_2_27b.sh` is useful for diagnosis; cross-model
agent workflows use the shared router. Both runtime clones remain installed.
All profiles load on demand, including Ornith. Vision uses Q8 K/V cache at 32K
and automatic GPU fitting to fit the 8 GiB GPU.
Keep the existing profiles synchronized in both INI files; the router backend
tests check their equality and their per-slot OpenCode context limits.

## Model router configuration

Each section in [config/router-models-bonsai.ini](config/router-models-bonsai.ini) matches the
model ID portion used in [opencode.json](opencode.json). The total context in a
router preset is divided between its parallel slots and must remain consistent
with the corresponding OpenCode limit.

To experiment with three Granite 3B instances at 32K each, change its preset to:

```ini
parallel = 3
ctx-size = 98304
cache-type-k = q4_0
cache-type-v = q4_0
```

Restart the router after changing a preset. Three large contexts can still be
tight on an 8 GB card, so actual capacity depends on GPU offload and runtime
overhead.

The Ornith preset uses a 4096-token reasoning budget and passes
`reasoning_effort: medium` to the chat template as a soft effort target. The
standalone launcher accepts a different hard budget through an environment
variable:

```bash
ORNITH_REASONING_BUDGET=2048 ./serving/serve_ornith.sh
```

## Model selection

Use `/models` to change the primary-session model. The selected agent role
remains unchanged. Subagent models are selected from their agent configuration;
the router handles loading the requested models during delegation.

## Orchestrator skill

[.opencode/skills/orchestrator/SKILL.md](.opencode/skills/orchestrator/SKILL.md)
defines the planning and delegation workflow for the three `-orchestrator`
models. It requires the orchestrator to create a durable plan before
implementation:

```text
plans/<task-slug>/
├── implementation-plan.md
└── tasks/
    ├── T01-<task-slug>.md
    └── T02-<task-slug>.md
```

The implementation plan records the architecture, interfaces, task graph,
ownership boundaries, and final validation. Each small independent task gets a
self-contained Task Markdown that links back to the plan and specifies exact
paths, constraints, acceptance criteria, and checks.

The skill is opt-in: use it only when the user explicitly requests the
`orchestrator` skill or its plan-and-Granite workflow. For delegated work, the
orchestrator makes one `multi_task` call containing one to three independent
Task Markdown paths. [.opencode/plugins/multi-task.js](.opencode/plugins/multi-task.js)
creates one child session per path and starts their prompts concurrently with
the fixed `granite-multi` agent and
`llama-granite/granite-4.2-3b-multi` model. The tool waits for the complete batch
and returns all reports together, so the one-model router loads Granite once and
reloads the primary model only after the batch. The primary session never
switches models.

`multi_task` accepts only repository-relative
`plans/<slug>/tasks/TNN-<slug>.md` files from the active worktree, limits a batch
to the router's three Granite slots, and asks for the normal `granite-multi`
task permission. The original orchestrator performs architecture, review,
integration, cross-cutting edits, and final validation. Tasks with dependencies
or overlapping owned paths belong in separate batches.

### Task-Series plugin

[`.opencode/plugins/task-series.js`](.opencode/plugins/task-series.js) exposes
two tools from one plugin: `task_series` runs one complete series through fresh
implementation, specification-test, and verification sessions;
`task_series_pool` schedules multiple independent series. Granite series may
use three parallel workers, while the `ornith` profile is strictly serial.
Granite and Ornith are never inferred concurrently. A mixed phase declares
`lane_order` explicitly; this is an execution choice, not a replacement for a
real task dependency. Durable reports and compact live pool metadata keep the
primary orchestrator informed while child models are active.

The phased workflow is defined by
[`.opencode/skills/task-series-orchestrator/SKILL.md`](.opencode/skills/task-series-orchestrator/SKILL.md).
It is opt-in, enforces phase barriers and reviews every pool result before the
next phase or an explicit retry.

## Long-context skill

[.opencode/skills/long-context/SKILL.md](.opencode/skills/long-context/SKILL.md)
handles documents or files that exceed the useful context of the current model.
Its workflow is:

1. Validate the canonical launcher with
   `serving/serve_qwen_long_context.sh --check`.
2. Emit `Task(subagent_type="long-context", ...)` with the source location and
   one precise extraction request.
3. Let the child session read the source with its configured
   `llama-long/qwen3.5-4b-long-context` model.
4. Review the returned findings and perform synthesis in the unchanged primary
   orchestrator session.

`serving/serve_qwen_long_context.sh` is the canonical replacement for the old
`serve_qwen_long_context_new.sh` name. During a router-backed OpenCode session,
the skill uses only its `--check` mode: starting the standalone server would
compete with the router for port 8080. The router loads Qwen for the child request
and reloads the primary orchestrator model for the next parent inference; the
primary session's configured model never changes.

Restart OpenCode after changing or installing a plugin or skill because these
files are loaded during startup.

## Standalone serving

The scripts in `serving/` can run individual models without the router:

```bash
./serving/serve_qwen.sh
./serving/serve_granite_3b_multi.sh
./serving/serve_granite_8b.sh
./serving/serve_ornith.sh
./serving/serve_qwen_long_context.sh
./serving/serve_geamm4_26_B_A4B.sh
```

Do not run a standalone server on port 8080 at the same time as the router.
Automatic model switching requires router mode.

## Validation

Check all shell scripts without starting a server:

```bash
for script in installations/*.sh serving/*.sh; do bash -n "$script"; done
```

Validate the long-context installation:

```bash
./serving/serve_qwen_long_context.sh --check
```

Run the plugin tests:

```bash
node .opencode/tests/multi-task.test.mjs
```

Run the subagent workflow tests:

```bash
node .opencode/tests/orchestrator-workflow.test.mjs
node .opencode/tests/long-context-workflow.test.mjs
```

Run the Granite 3B multi-agent A/B benchmark. It starts each test server,
executes three repetitions with one main-agent request and two concurrent
background-agent requests, prints every response, and stops the server again:

```bash
python3 benchmarks/granite_multi_ab.py
```

Add the potentially VRAM-heavy three-slot Q8 variant with:

```bash
python3 benchmarks/granite_multi_ab.py --include-three-slot-q8
```

Port 8080 must be free. Use `--reasoning-effort none` when the benchmark should
measure visible implementation output without spending tokens on reasoning.

## Goals

NexusForge explores whether capable local models can coordinate specialized,
lightweight coding agents efficiently enough for a practical fully local
software-engineering workflow. Planned areas include parallel implementation,
Git worktree isolation, automated testing, structured delegation, dynamic model
selection, and final review by the orchestrator.


## Bonsai 2 27B orchestrator

Install the official ternary model and build the PrismML llama.cpp fork:

```bash
./installations/install_bonsai_2_27b.sh
```

Start the shared router in one terminal, then select Bonsai in another:

```bash
./serving/serve_router.sh
./opencode.sh --agent bonsai-orchestrator
```

Stop another server on port 8080 before starting the router. In OpenCode,
Bonsai is also available in the primary-agent selector and as
`llama-bonsai/bonsai-2-27b-ternary` in `/models`. Changing the model does not change
the agent role.
Ornith remains the default agent. Restart OpenCode to load the new configuration.

The Bonsai profile uses the standalone server's default 32,768-token context and
an output limit of 4,096 tokens. Large tool prompts or conversations may need more
context; adjust the server and OpenCode limits together after checking memory use.
The standalone Bonsai server serves only Bonsai. Delegation to Granite, Qwen or
Ornith requires the shared-router integration described in
[the migration TODO](TODO/bonsai-router-opencode-integration.md).


## Language servers (LSP)

Install the shared Bash, Python, and JavaScript/TypeScript language servers:

```bash
./installations/install_lsp.sh
```

Requires Node.js >= 22.22.2 and npm. Packages are installed locally under
`.tools/lsp/`; the installer pins TypeScript 5.9.3 because the language server
needs its JavaScript `tsserver`. `opencode.sh` adds the commands to PATH and
enables `OPENCODE_EXPERIMENTAL_LSP_TOOL`. The `lsp` section in `opencode.json`
configures the three servers, with `permission.lsp` allowing tool access.
Restart OpenCode after installation. Language servers start on demand when
supported files are accessed, including in another repository opened through
`opencode.sh`. They run on the CPU and do not require a model server.

For Python projects, activate the project's virtual environment before launching
OpenCode or configure Pyright's environment in the project. Optional ShellCheck
adds richer Bash diagnostics; it is not installed by this script.
