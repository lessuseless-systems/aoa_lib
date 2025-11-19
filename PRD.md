Nice — I’ll deliver **Option A: a full architecture / PRD-style document** now (the most useful single next artifact — it covers everything else and makes implementing Options B–D straightforward). I’ll include motivation, use cases, system overview, layer-by-layer spec, an example JSON schema Nickel should output, a sample `workflow.json`, PocketFlow `serde` types, Nickel contract snippet, Nix integration notes, CLI (Nushell) glue example, APIs, and error-handling/resilience guidelines. That should give you a launchable blueprint you can use to start implementing and to hand to LLMs/agents to generate code.

# PRD — Orchestrator Agent Stack (Agent-of-Agents)

> A clear, implementable architecture for an Orchestrator (big-LLM) that generates Nickel configs evaluated into validated JSON consumed by a Rust runtime (PocketFlow) that executes BitNet workers.

---

# 1. Motivation

Large autonomous tasks (feature development, complex document processing, multi-step automation) require decomposition, robust validation, and safe runtime execution. This architecture separates responsibilities:

* Big-LLM: planning, high-level reasoning, reflection.
* Nickel: declarative configuration + contract validation.
* JSON: canonical, portable config.
* PocketFlow (Rust): deterministic, performant runtime.
* BitNet workers: cheap, fast specialist models for subtasks.

Goals:

* Safety: validate configs before execution.
* Auditability: traceable steps and structured logs.
* Extensibility: add new agent types without touching orchestrator internals.
* Reproducibility: Nix + Nickel ensure deterministic builds and configs.

---

# 2. Primary Use Cases

1. **End-to-end feature implementation**: Orchestrator decomposes feature → codegen + test + docs agents compose final PR.
2. **Document pipeline**: ingest → extract → summarize → craft a response.
3. **Data transformation workflows**: collect API data → normalize → run ML inference → generate reports.
4. **Automated triage**: triage incoming issues, assign priority, draft responses.

---

# 3. System Overview (High level)

Flow:

1. User goal → Orchestrator LLM (big model)
2. Orchestrator emits Nickel program (workflow.ncl)
3. Nickel evaluates + enforces contracts → `workflow.json`
4. PocketFlow loads `workflow.json`, builds DAG, executes nodes
5. Node implementation uses BitNet models (local, quantized) or other tools
6. PocketFlow aggregates/returns results; Orchestrator may decide further refinement steps

ASCII diagram (compact):

```
[User Goal]
    ↓
[Orchestrator LLM]
    → emits Nickel (.ncl)
    ↓
[Nickel evaluator & contracts]
    → outputs validated workflow.json
    ↓
[pocketflow (Rust runtime)]
    → build DAG; run nodes (BitNet workers)
    ↓
[Workers / Tools / APIs] ---> results
    ↓
[pocketflow aggregates] → final output
    ↑
[Orchestrator reflection loop] (optional)
```

---

# 4. Layer-by-layer Specification

## Layer 1 — Orchestration & Planning (Big-LLM)

**Responsibilities**

* Receive user intent.
* Determine workflow plan: nodes, data flow, agent types, retry/timeouts.
* Generate Nickel program using templates and domain-specific primitives.
* Optionally do reflection and replan when runtime signals failure.

**Interfaces**

* Input: plain text goal (or structured prompt).
* Output: `workflow.ncl` (Nickel source).

**Notes**

* Keep orchestration deterministic by seeding generation templates and using constrained decoding where possible.
* Include metadata (trace id, orchestrator_version, timestamp).

---

## Layer 2 — Nickel Config + Contracts

**Responsibilities**

* Validate structure with contracts (schemas expressed as Nickel contracts).
* Evaluate expressions, produce canonical JSON/YAML.
* Reject invalid workflows early.

**Contract concerns**

* Node schema, `id`, `type`, `inputs`, `outputs`, `next`, `retry`, `timeout_ms`.
* Agent types allowed & tool policies (e.g., network access).
* Ensure no cycles unless explicitly allowed (or flagged).

**Output**

* `workflow.json` (validated, normalized).

---

## Layer 3 — PocketFlow Runtime (Rust)

**Responsibilities**

* Deserialize `workflow.json` into typed config (serde).
* Build execution graph (DAG).
* Execute nodes with concurrency and respects `next` edges.
* Handle streaming and large outputs.
* Maintain structured logs and events.

**Key features**

* Async runtime (Tokio).
* Node types: `bitnet_model`, `http_call`, `shell`, `custom_rust`.
* Retry and backoff strategies.
* Plugin system for new node types.

---

## Layer 4 — Node Implementations & BitNet Workers

**Responsibilities**

* Run small, specialized tasks.
* Use local quantized BitNet models (e.g., gguf) through bindings (`llama.cpp`-style C or Rust wrappers).
* Validate outputs against expected schema before forwarding.

**Implementation notes**

* Node returns structured JSON: `{ "status": "ok", "output": {...}, "meta": {...} }`
* Provide deterministic seeds for generation when reproducible outputs required.

---

## Layer 5 — Runtime Validation / Guards

**Two-tiered validation**

* **Compile time**: Nickel contracts
* **Runtime**: `garde` or custom validators for LLM outputs and external inputs

**Runtime guard tasks**

* Schema checks
* Safety policy enforcement (no exfiltration)
* Type and size checks
* Rate limiting / circuit breakers

---

# 5. Canonical Workflow JSON Schema (recommended)

Below is a compact JSON Schema (conceptual) and an example `workflow.json`. Use this as Nickel contract basis.

## JSON Schema (conceptual)

```json
{
  "$id": "https://example.org/workflow.schema.json",
  "title": "WorkflowConfig",
  "type": "object",
  "required": ["workflow"],
  "properties": {
    "workflow": {
      "type": "object",
      "required": ["nodes", "settings"],
      "properties": {
        "nodes": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["id","type","inputs"],
            "properties": {
              "id": { "type": "string" },
              "type": { "type": "string" },
              "inputs": { "type": "object" },
              "outputs": { "type": "object" },
              "next": { "type": "array", "items": { "type": "string" } },
              "retries": { "type": "integer", "minimum": 0 },
              "timeout_ms": { "type": "integer", "minimum": 0 },
              "meta": { "type": "object" }
            }
          }
        },
        "settings": {
          "type":"object",
          "properties":{
            "retry_policy":{"type":"string"},
            "concurrency":{"type":"integer"}
          }
        }
      }
    }
  }
}
```

## Example `workflow.json`

```json
{
  "workflow": {
    "nodes": [
      {
        "id": "ingest",
        "type": "http_fetch",
        "inputs": {
          "url": "https://example.com/report.pdf"
        },
        "next": ["extract"],
        "retries": 2,
        "timeout_ms": 30000
      },
      {
        "id": "extract",
        "type": "bitnet_extract",
        "inputs": {
          "src": "ingest.output"
        },
        "next": ["summarize"]
      },
      {
        "id": "summarize",
        "type": "bitnet_summarizer",
        "inputs": {
          "text": "extract.output.text",
          "summary_length": 200
        },
        "next": ["draft"]
      },
      {
        "id": "draft",
        "type": "bitnet_codegen",
        "inputs": {
          "summary": "summarize.output.summary",
          "style": "concise"
        },
        "next": []
      }
    ],
    "settings": {
      "retry_policy": "exponential_backoff",
      "concurrency": 3
    }
  }
}
```

---

# 6. Nickel Contract Snippet (conceptual)

This is a conceptual Nickel contract (Nickel syntax simplified). Use it to enforce shape before exporting JSON.

```nickel
# contracts/workflow.ncl

let Node = {
  id: Str,
  type: Str,
  inputs: { .. },
  next: [Str],
  retries? = 0,
  timeout_ms? = 30000,
  meta?: { .. }
};

let Workflow = {
  nodes: [Node],
  settings: {
    retry_policy?: Str,
    concurrency?: Num
  }
};

let assert_unique_ids = (nodes: [Node]) => /* implement uniqueness check */ true;

let validate = |w| 
  if assert_unique_ids w.nodes then w else error "duplicate node ids";

validate Workflow
```

(When you implement, write Nickel functions to assert `next` values reference existing `id`s and that permitted `type` strings match the allowed agent types.)

---

# 7. PocketFlow — Example Serde structs (Rust)

```rust
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub struct WorkflowConfig {
    pub workflow: Workflow
}

#[derive(Serialize, Deserialize, Debug)]
pub struct Workflow {
    pub nodes: Vec<NodeConfig>,
    pub settings: Option<WorkflowSettings>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct NodeConfig {
    pub id: String,
    pub r#type: String,
    pub inputs: serde_json::Value,
    pub outputs: Option<serde_json::Value>,
    pub next: Option<Vec<String>>,
    pub retries: Option<u32>,
    pub timeout_ms: Option<u64>,
    pub meta: Option<serde_json::Value>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct WorkflowSettings {
    pub retry_policy: Option<String>,
    pub concurrency: Option<usize>,
}
```

PocketFlow should:

* Deserialize with `serde_json::from_str`.
* Validate referenced `next` ids exist.
* Build execution DAG.

---

# 8. Nushell CLI Glue (run.nu)

Example `run.nu` that orchestrates steps (this is a template — adapt paths):

```
# run.nu
# $args[0] is the goal text

let goal = ($args | str join " ")
# Call an orchestrator binary that outputs Nickel code (or the orchestrator LLM interface)
let ncl = (orchestrator --goal $"($goal)")
# save
echo $"($ncl)" > workflow.ncl

# Evaluate Nickel to JSON
nickel eval workflow.ncl --export --format json > workflow.json

# Optionally pretty inspect
open workflow.json | from json | to json

# Run pocketflow
pocketflow run --config workflow.json --trace-id $"(now)".timestamp
```

Note: replace `nickel eval` flags to match your Nickel CLI.

---

# 9. Nix Integration (high-level)

**Goals**: deterministic builds, pinned dependencies, reproducible Nickel and Rust builds.

**Files**

* `flake.nix` to pin inputs (rust toolchain, nickel, tokio, cargo, model artifacts).
* `default.nix` for dev shells.

**Recommendations**

* Pin the Nickel executable version (or build from source in the flake).
* Provide `devShell` with `nickel`, `rustc`, `cargo`, `nushell`.
* Package BitNet model artifacts in the flake as immutable inputs (or reference a cached gguf store).

Example `devShell` snippet (conceptual):

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    rust-overlay.url = "github:mozilla/nixpkgs-mozilla";
  };

  outputs = { self, nixpkgs, ... }: {
    devShells.x86_64-linux.default = pkgs.mkShell {
      buildInputs = with pkgs; [ rustc cargo nickel nushell ];
    };
  };
}
```

---

# 10. APIs & Interfaces

## Orchestrator API (external)

* `POST /plan` body: `{ "goal": "Create a checkout page" }`
* Response: `{ "nickel": "<workflow.ncl>", "trace_id": "..." }`

## PocketFlow CLI / API

* CLI: `pocketflow run --config workflow.json --trace-id <id>`
* HTTP (optional): `POST /run` body: `workflow.json` → returns `run_id` and `status` stream

## Node plugin interface

* `fn execute(node_config, context) -> NodeResult`
* NodeResult:

```json
{
  "status": "ok|error",
  "output": { ... },
  "meta": { "duration_ms": 123, "model": "bitnet-v1" }
}
```

---

# 11. Error Handling & Resilience

## At configuration time

* Nickel rejects invalid structures, unknown agent types, or unsafe tool references.
* Return clear error messages (line & column) for debugging.

## At runtime (PocketFlow)

* Node-level retries: `retries` + exponential backoff.
* Circuit breakers: if external API fails repeatedly, disable dependent branches.
* Timeouts: `timeout_ms` enforced per node.
* Dead-letter queue: failed outputs persisted for later analysis.
* Idempotency: nodes should be re-runnable (stateless or with persisted checkpoints).
* Abort & rollback: orchestrator can choose to abort and trigger compensating tasks.

## Observability

* Structured event logs (JSON lines) with `trace_id` and `node_id`.
* Runtime metrics: success_rate, latency, concurrency, error types.
* Store artifacts (inputs/outputs) to object storage with access controls.

---

# 12. Security & Policy Notes

* Limit which node types the Orchestrator may request (e.g., disallow `shell` nodes in untrusted contexts).
* Use runtime validators to strip secrets from LLM outputs.
* Model sandboxing: run BitNet models in isolated processes, restrict network access unless authorized.
* Maintain an allowlist for external endpoints.

---

# 13. Example End-to-end Trace (toy)

1. User: “Summarize report X and draft a 300-word reply.”
2. Orchestrator LLM → emits Nickel that composes nodes: `fetch -> ocr -> extract -> summarize -> draft`.
3. Nickel validates & outputs `workflow.json`.
4. PocketFlow runs nodes:

   * `fetch` (http)
   * `ocr` (local Tesseract)
   * `extract` (bitnet_extract)
   * `summarize` (bitnet_summarizer)
   * `draft` (bitnet_codegen)
5. Each node returns structured output; if `summarize` fails, runtime retries twice; if still failing, orchestrator receives failure, reflects, modifies plan (maybe use a different summarizer), and re-submits.

---

> # 14. Deliverables I can produce next (pick from these 
> 
> * A. **Full Treecat Project Scaffolding** (Option B) — create the directory skeleton + placeholder files (ready for git).
> * B. **Deep dive Orchestrator design doc** (Option C) — algorithms for decomposition, reflection, confidence scoring, re-plan heuristics, prompt templates, and sample orchestration code.
> * C. **Integration Spec: BitNet worker** (Option D) — model packaging, gguf handling, rust wrapper, deterministic seeding, and a sample node implementation.
> * D. **Nickel contracts + full JSON Schema** — fleshed-out, ready-to-run contracts and schema to use during development.
> * E. **PocketFlow minimal runtime prototype** — a small Rust program that deserializes the example config and executes a mock node graph locally (I can scaffold the code files).
> 
> I already included a solid set of schemas, Nickels snippets, rust types, nushell glue, and Nix tips in this doc. If you want immediate next-code, I suggest generating the **Treecat scaffold** and/or the **BitNet worker spec** — I can do either now.
> 
> Which of the above should I generate right now for you? (I can produce both if you want; I’ll start with your top choice.)
