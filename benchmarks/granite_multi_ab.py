#!/usr/bin/env python3
"""A/B benchmark for NexusForge's parallel Granite 4.2 3B setup.

The script owns the llama-server processes it starts, runs the same three
main-agent/background-agent scenarios against every variant, prints every model
response to the terminal, and stops each server before starting the next one.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SERVER_SCRIPT = PROJECT_ROOT / "serving" / "serve_granite_3b_multi.sh"
MODEL_ALIAS = "granite-4.2-3b-multi"


@dataclass(frozen=True)
class AgentPrompt:
    role: str
    task_file: str
    target_file: str
    task: str


@dataclass(frozen=True)
class Scenario:
    title: str
    prompts: tuple[AgentPrompt, AgentPrompt, AgentPrompt]


@dataclass(frozen=True)
class Variant:
    key: str
    label: str
    slots: int
    cache_type: str


@dataclass
class RequestResult:
    prompt: AgentPrompt
    elapsed_seconds: float
    prompt_tokens: int = 0
    predicted_tokens: int = 0
    prompt_tokens_per_second: float | None = None
    predicted_tokens_per_second: float | None = None
    finish_reason: str | None = None
    reasoning: str = ""
    content: str = ""
    error: str | None = None


@dataclass
class RoundResult:
    title: str
    wall_seconds: float
    requests: list[RequestResult]

    @property
    def predicted_tokens(self) -> int:
        return sum(item.predicted_tokens for item in self.requests)

    @property
    def aggregate_tokens_per_second(self) -> float:
        return self.predicted_tokens / self.wall_seconds if self.wall_seconds else 0.0


@dataclass
class VariantResult:
    variant: Variant
    rounds: list[RoundResult] = field(default_factory=list)
    idle_vram_mib: int | None = None
    peak_vram_mib: int | None = None
    free_vram_mib: int | None = None
    error: str | None = None


SCENARIOS = (
    Scenario(
        title="Configuration and output pipeline",
        prompts=(
            AgentPrompt(
                role="main-agent",
                task_file="plans/config-output/tasks/T00-integrate-cli.md",
                target_file="src/cli.py",
                task=(
                    "Wire the already agreed load_config(path, environ) and "
                    "render_records(records, output_format) interfaces into the CLI. "
                    "Preserve exit codes 0/2, keep argparse construction testable, "
                    "and return a unified diff for src/cli.py only."
                ),
            ),
            AgentPrompt(
                role="background-agent-a",
                task_file="plans/config-output/tasks/T01-config-loader.md",
                target_file="src/config.py",
                task=(
                    "Implement load_config(path, environ): parse a UTF-8 TOML file, "
                    "apply APP_TIMEOUT and APP_OUTPUT environment overrides, validate "
                    "timeout > 0 and output in {'table','json'}, and raise ConfigError "
                    "with actionable messages. Return a unified diff for src/config.py only."
                ),
            ),
            AgentPrompt(
                role="background-agent-b",
                task_file="plans/config-output/tasks/T02-record-formatting.md",
                target_file="src/formatting.py",
                task=(
                    "Implement render_records(records, output_format) with stable column "
                    "ordering, deterministic JSON, correct empty input handling, and no "
                    "terminal color when stdout is not a TTY. Return a unified diff for "
                    "src/formatting.py only."
                ),
            ),
        ),
    ),
    Scenario(
        title="HTTP retries and contract tests",
        prompts=(
            AgentPrompt(
                role="main-agent",
                task_file="plans/http-retries/tasks/T00-integrate-client.md",
                target_file="src/http/client.py",
                task=(
                    "Integrate a RetryPolicy dependency into AsyncHttpClient without "
                    "changing its public request() signature. Cancellation must propagate "
                    "immediately and response bodies must always be closed. Return a unified "
                    "diff for src/http/client.py only."
                ),
            ),
            AgentPrompt(
                role="background-agent-a",
                task_file="plans/http-retries/tasks/T01-retry-policy.md",
                target_file="src/http/retry.py",
                task=(
                    "Implement immutable RetryPolicy with capped exponential backoff and "
                    "optional jitter injection. Retry only 429, 502, 503, and 504; honor an "
                    "integer Retry-After header; make delay calculation deterministic under "
                    "tests. Return a unified diff for src/http/retry.py only."
                ),
            ),
            AgentPrompt(
                role="background-agent-b",
                task_file="plans/http-retries/tasks/T02-retry-tests.md",
                target_file="tests/test_retry.py",
                task=(
                    "Write pytest tests against the agreed RetryPolicy interface covering "
                    "the retryable status set, backoff cap, Retry-After, injected jitter, and "
                    "invalid constructor values. Do not edit implementation files. Return a "
                    "unified diff for tests/test_retry.py only."
                ),
            ),
        ),
    ),
    Scenario(
        title="Job state and observability",
        prompts=(
            AgentPrompt(
                role="main-agent",
                task_file="plans/job-observability/tasks/T00-runner-integration.md",
                target_file="src/jobs/runner.py",
                task=(
                    "Update JobRunner to use the agreed JobStateStore and JobTelemetry "
                    "interfaces. A failed telemetry emission must never change the job result, "
                    "and state transitions must remain atomic. Return a unified diff for "
                    "src/jobs/runner.py only."
                ),
            ),
            AgentPrompt(
                role="background-agent-a",
                task_file="plans/job-observability/tasks/T01-state-store.md",
                target_file="src/jobs/state.py",
                task=(
                    "Implement a thread-safe in-memory JobStateStore with compare-and-set "
                    "transitions queued -> running -> succeeded|failed, immutable snapshots, "
                    "and explicit InvalidTransition errors. Return a unified diff for "
                    "src/jobs/state.py only."
                ),
            ),
            AgentPrompt(
                role="background-agent-b",
                task_file="plans/job-observability/tasks/T02-telemetry.md",
                target_file="src/jobs/telemetry.py",
                task=(
                    "Implement JobTelemetry that records duration and terminal status through "
                    "an injected metrics sink. Sanitize job-type labels, use a monotonic clock, "
                    "and swallow sink failures after logging them. Return a unified diff for "
                    "src/jobs/telemetry.py only."
                ),
            ),
        ),
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare Granite 3B with 2x32K/Q8 and 3x32K/Q4. Every variant "
            "runs three repetitions containing one main agent and two background agents."
        )
    )
    parser.add_argument(
        "--include-three-slot-q8",
        action="store_true",
        help="also run an optional 3x32K/Q8 variant (it may exceed 8 GB VRAM)",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=512,
        help="maximum generated tokens per agent request (default: 512)",
    )
    parser.add_argument(
        "--reasoning-effort",
        choices=("auto", "none", "low", "medium", "high"),
        default="auto",
        help="reasoning mode sent to llama.cpp; auto leaves the server default unchanged",
    )
    parser.add_argument(
        "--request-timeout",
        type=float,
        default=180.0,
        help="timeout in seconds for one inference request (default: 180)",
    )
    parser.add_argument(
        "--startup-timeout",
        type=float,
        default=90.0,
        help="timeout in seconds while loading a server variant (default: 90)",
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    if args.max_tokens <= 0:
        parser.error("--max-tokens must be positive")
    if args.request_timeout <= 0 or args.startup_timeout <= 0:
        parser.error("timeouts must be positive")
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    return args


def separator(character: str = "=", width: int = 88) -> None:
    print(character * width, flush=True)


def http_json(
    base_url: str,
    path: str,
    *,
    payload: dict[str, Any] | None = None,
    timeout: float = 5.0,
) -> dict[str, Any] | list[Any]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url}{path}",
        data=data,
        headers={"Content-Type": "application/json"} if data is not None else {},
        method="POST" if data is not None else "GET",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def port_is_open(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.5):
            return True
    except OSError:
        return False


def read_gpu_memory() -> tuple[int, int] | None:
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=memory.used,memory.free",
                "--format=csv,noheader,nounits",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        first_line = result.stdout.splitlines()[0]
        used, free = (int(value.strip()) for value in first_line.split(",")[:2])
        return used, free
    except (FileNotFoundError, IndexError, OSError, subprocess.SubprocessError, ValueError):
        return None


class GpuMonitor:
    def __init__(self) -> None:
        self.samples: list[tuple[int, int]] = []
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=2)

    def _run(self) -> None:
        while not self._stop.is_set():
            sample = read_gpu_memory()
            if sample is not None:
                self.samples.append(sample)
            self._stop.wait(0.2)

    @property
    def peak_used_mib(self) -> int | None:
        return max((used for used, _ in self.samples), default=None)


def tail_server_log(log_file: Any, lines: int = 30) -> str:
    log_file.flush()
    log_file.seek(0)
    return "".join(log_file.readlines()[-lines:]).rstrip()


def start_server(
    variant: Variant,
    args: argparse.Namespace,
    log_file: Any,
) -> tuple[subprocess.Popen[str], dict[str, Any]]:
    environment = os.environ.copy()
    environment.update(
        {
            "PARALLEL": str(variant.slots),
            "CTX_PER_SLOT": "32768",
            "CACHE_TYPE_K": variant.cache_type,
            "CACHE_TYPE_V": variant.cache_type,
            "HOST": args.host,
            "PORT": str(args.port),
        }
    )
    process = subprocess.Popen(
        [str(SERVER_SCRIPT)],
        cwd=PROJECT_ROOT,
        env=environment,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    base_url = f"http://{args.host}:{args.port}"
    deadline = time.monotonic() + args.startup_timeout
    last_error = "server did not answer"
    try:
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(
                    f"server exited with code {process.returncode}\n{tail_server_log(log_file)}"
                )
            try:
                health = http_json(base_url, "/health", timeout=2)
                if isinstance(health, dict) and health.get("status") == "ok":
                    props = http_json(base_url, "/props", timeout=5)
                    if not isinstance(props, dict):
                        raise RuntimeError("/props did not return a JSON object")
                    return process, props
            except (OSError, TimeoutError, urllib.error.URLError, ValueError) as error:
                last_error = str(error)
            time.sleep(0.25)
        raise RuntimeError(
            f"server was not ready after {args.startup_timeout:.0f}s: {last_error}\n"
            f"{tail_server_log(log_file)}"
        )
    except BaseException:
        stop_server(process)
        raise


def stop_server(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGINT)
        process.wait(timeout=15)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def request_payload(prompt: AgentPrompt, args: argparse.Namespace, seed: int) -> dict[str, Any]:
    role_instruction = (
        "You are the primary implementation agent. Keep the integration contract stable "
        "while two background agents work concurrently on their separately owned files."
        if prompt.role == "main-agent"
        else "You are a bounded background implementation agent. Do not redesign interfaces or edit any path except the assigned file."
    )
    user_message = (
        f"Task Markdown: {prompt.task_file}\n"
        f"Owned file: {prompt.target_file}\n\n"
        f"{prompt.task}\n\n"
        "This is a synthetic benchmark fixture: if the current file body is not shown, "
        "return a self-contained proposed replacement instead of refusing the task. "
        "Respect the established interfaces, mention assumptions briefly, and produce an actionable result."
    )
    payload: dict[str, Any] = {
        "model": MODEL_ALIAS,
        "messages": [
            {"role": "system", "content": role_instruction},
            {"role": "user", "content": user_message},
        ],
        "stream": False,
        "temperature": 0,
        "seed": seed,
        "max_tokens": args.max_tokens,
    }
    if args.reasoning_effort != "auto":
        payload["reasoning_effort"] = args.reasoning_effort
    return payload


def run_agent_request(
    base_url: str,
    prompt: AgentPrompt,
    args: argparse.Namespace,
    seed: int,
    barrier: threading.Barrier,
) -> RequestResult:
    barrier.wait(timeout=10)
    started = time.monotonic()
    try:
        body = http_json(
            base_url,
            "/v1/chat/completions",
            payload=request_payload(prompt, args, seed),
            timeout=args.request_timeout,
        )
        if not isinstance(body, dict):
            raise RuntimeError("response was not a JSON object")
        message = body.get("choices", [{}])[0].get("message", {})
        timings = body.get("timings", {})
        usage = body.get("usage", {})
        return RequestResult(
            prompt=prompt,
            elapsed_seconds=time.monotonic() - started,
            prompt_tokens=int(usage.get("prompt_tokens", timings.get("prompt_n", 0)) or 0),
            predicted_tokens=int(
                usage.get("completion_tokens", timings.get("predicted_n", 0)) or 0
            ),
            prompt_tokens_per_second=timings.get("prompt_per_second"),
            predicted_tokens_per_second=timings.get("predicted_per_second"),
            finish_reason=body.get("choices", [{}])[0].get("finish_reason"),
            reasoning=message.get("reasoning_content", "") or "",
            content=message.get("content", "") or "",
        )
    except Exception as error:  # keep the other two concurrent results visible
        return RequestResult(
            prompt=prompt,
            elapsed_seconds=time.monotonic() - started,
            error=f"{type(error).__name__}: {error}",
        )


def warm_up(base_url: str, args: argparse.Namespace) -> None:
    payload: dict[str, Any] = {
        "model": MODEL_ALIAS,
        "messages": [{"role": "user", "content": "Reply with only: ready"}],
        "stream": False,
        "temperature": 0,
        "max_tokens": 8,
    }
    if args.reasoning_effort != "auto":
        payload["reasoning_effort"] = args.reasoning_effort
    http_json(
        base_url,
        "/v1/chat/completions",
        payload=payload,
        timeout=args.request_timeout,
    )


def print_request_result(result: RequestResult) -> None:
    separator("-")
    print(
        f"{result.prompt.role} | {result.prompt.target_file} | "
        f"{result.elapsed_seconds:.2f}s | prompt={result.prompt_tokens} | "
        f"generated={result.predicted_tokens} | finish={result.finish_reason}"
    )
    if result.predicted_tokens_per_second is not None:
        print(f"decode: {result.predicted_tokens_per_second:.2f} tok/s")
    if result.error:
        print(f"ERROR: {result.error}")
        return
    if result.reasoning:
        print("\n[reasoning]")
        print(result.reasoning.rstrip())
    if result.content:
        print("\n[answer]")
        print(result.content.rstrip())
    if not result.reasoning and not result.content:
        print("\n[empty model output]")


def run_scenario(
    scenario: Scenario,
    repetition: int,
    base_url: str,
    args: argparse.Namespace,
) -> RoundResult:
    separator()
    print(f"Repetition {repetition}/3: {scenario.title}", flush=True)
    barrier = threading.Barrier(3)
    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=3, thread_name_prefix="granite-agent") as executor:
        futures = [
            executor.submit(
                run_agent_request,
                base_url,
                prompt,
                args,
                repetition * 100 + index,
                barrier,
            )
            for index, prompt in enumerate(scenario.prompts)
        ]
        results = [future.result() for future in futures]
    wall_seconds = time.monotonic() - started
    round_result = RoundResult(scenario.title, wall_seconds, results)
    for result in results:
        print_request_result(result)
    separator("-")
    print(
        f"Repetition result: wall={wall_seconds:.2f}s | "
        f"generated={round_result.predicted_tokens} | "
        f"aggregate={round_result.aggregate_tokens_per_second:.2f} tok/s",
        flush=True,
    )
    return round_result


def run_variant(variant: Variant, args: argparse.Namespace) -> VariantResult:
    result = VariantResult(variant=variant)
    process: subprocess.Popen[str] | None = None
    monitor = GpuMonitor()
    base_url = f"http://{args.host}:{args.port}"
    separator("#")
    print(f"Variant {variant.key}: {variant.label}")
    print(
        f"slots={variant.slots}, context/slot=32768, "
        f"KV={variant.cache_type.upper()}, URL={base_url}"
    )
    with tempfile.TemporaryFile(mode="w+t", encoding="utf-8") as log_file:
        monitor.start()
        try:
            process, props = start_server(variant, args, log_file)
            reported_slots = int(props.get("total_slots", -1))
            generation_settings = props.get("default_generation_settings", {})
            context_per_slot = int(
                generation_settings.get(
                    "n_ctx",
                    generation_settings.get("params", {}).get("n_ctx", -1),
                )
            )
            if reported_slots != variant.slots or context_per_slot != 32768:
                raise RuntimeError(
                    "server reported unexpected topology: "
                    f"slots={reported_slots}, context/slot={context_per_slot}"
                )
            memory = read_gpu_memory()
            if memory is not None:
                result.idle_vram_mib, result.free_vram_mib = memory
                print(
                    f"Server ready: VRAM used={result.idle_vram_mib} MiB, "
                    f"free={result.free_vram_mib} MiB"
                )
            else:
                print("Server ready: nvidia-smi metrics unavailable")
            warm_up(base_url, args)
            for repetition, scenario in enumerate(SCENARIOS, start=1):
                result.rounds.append(
                    run_scenario(scenario, repetition, base_url, args)
                )
        except Exception as error:
            result.error = f"{type(error).__name__}: {error}"
            print(f"VARIANT FAILED: {result.error}", file=sys.stderr)
            log_tail = tail_server_log(log_file)
            if log_tail:
                print("\n[server log tail]", file=sys.stderr)
                print(log_tail, file=sys.stderr)
        finally:
            if process is not None:
                stop_server(process)
            monitor.stop()
            result.peak_vram_mib = monitor.peak_used_mib
            deadline = time.monotonic() + 10
            while port_is_open(args.host, args.port) and time.monotonic() < deadline:
                time.sleep(0.1)
            print(f"Variant {variant.key} server stopped.", flush=True)
    return result


def mean_or_none(values: list[float]) -> float | None:
    return statistics.mean(values) if values else None


def print_summary(results: list[VariantResult]) -> None:
    separator("#")
    print("FINAL SUMMARY")
    separator("#")
    print(
        f"{'Variant':<22} {'Success':>9} {'Mean wall':>12} "
        f"{'Mean agg.':>12} {'Idle VRAM':>12} {'Peak VRAM':>12}"
    )
    for item in results:
        successful = sum(
            1 for round_result in item.rounds for request in round_result.requests if not request.error
        )
        total = sum(len(round_result.requests) for round_result in item.rounds)
        mean_wall = mean_or_none([round_result.wall_seconds for round_result in item.rounds])
        mean_aggregate = mean_or_none(
            [round_result.aggregate_tokens_per_second for round_result in item.rounds]
        )
        print(
            f"{item.variant.key + ' ' + item.variant.cache_type.upper():<22} "
            f"{f'{successful}/{total}':>9} "
            f"{f'{mean_wall:.2f}s' if mean_wall is not None else '-':>12} "
            f"{f'{mean_aggregate:.2f}' if mean_aggregate is not None else '-':>12} "
            f"{f'{item.idle_vram_mib} MiB' if item.idle_vram_mib is not None else '-':>12} "
            f"{f'{item.peak_vram_mib} MiB' if item.peak_vram_mib is not None else '-':>12}"
        )
        if item.error:
            print(f"  error: {item.error}")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)
        sys.stderr.reconfigure(line_buffering=True)
    args = parse_args()
    if not SERVER_SCRIPT.is_file():
        print(f"ERROR: server launcher not found: {SERVER_SCRIPT}", file=sys.stderr)
        return 2
    if port_is_open(args.host, args.port):
        print(
            f"ERROR: {args.host}:{args.port} is already in use. Stop the router or "
            "standalone server before running the benchmark.",
            file=sys.stderr,
        )
        return 2

    variants = [
        Variant("A", "2 slots x 32K with Q8 KV", 2, "q8_0"),
        Variant("B", "3 slots x 32K with Q4 KV", 3, "q4_0"),
    ]
    if args.include_three_slot_q8:
        variants.append(Variant("C", "3 slots x 32K with Q8 KV", 3, "q8_0"))

    print("NexusForge Granite 4.2 3B multi-agent A/B benchmark")
    print(f"Model alias: {MODEL_ALIAS}")
    print(f"Repetitions per variant: {len(SCENARIOS)}")
    print(f"Concurrent requests per repetition: 3")
    print(f"Max tokens per request: {args.max_tokens}")
    print(f"Reasoning effort: {args.reasoning_effort}")
    results = [run_variant(variant, args) for variant in variants]
    print_summary(results)
    return 1 if any(item.error for item in results) else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nBenchmark interrupted; owned server process was stopped.", file=sys.stderr)
        raise SystemExit(130)
