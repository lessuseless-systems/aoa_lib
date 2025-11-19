# Hierarchical Multi-Agent Prompt Pack + Nickel Module + PocketFlow Example + BitNet-Tuned Templates

## Overview

This document contains four deliverables:

1. **A1 — Hierarchical multi-agent prompt pack** (Decomposer, Validator, Planner, Critic, Meta-controller). JSON-ready prompts with few-shot examples.
2. **A2 — Nickel module** that exports the same prompt pack as a Nickel data module `pocketflow.prompts` for easy import and use in Nickel-generated workflows.
3. **A3 — Complete PocketFlow workflow example** using BitNet inference nodes with state passing (full `workflow.json` example and notes on node configs).
4. **A4 — Templates tuned for extremely small BitNet models** (short prompts, constrained decoding hints, pragmatic strategies).

---

## A1 — Hierarchical Multi-Agent Prompt Pack (JSON)

```json
{
  "decomposer": {
    "system": "You are a Decomposer agent. Given a single user goal, split it into the smallest possible actionable steps. Steps must be tool-addressable, reversible when possible, and explicitly list inputs/outputs. Return compact JSON only.",
    "user_template": "Goal: {{goal}}\nConstraints: {{constraints}}\nReturn: { \"steps\": [{ \"id\": \"s1\", \"desc\": \"...\", \"inputs\": [...], \"outputs\": [...] }], \"assumptions\": [...] }",
    "few_shot": [
      {
        "goal": "Draft a short policy response to a customer complaint email, preserving their privacy.",
        "response": {
          "steps": [
            {"id":"s1","desc":"Fetch complaint email","inputs":["email_id"],"outputs":["email_text"]},
            {"id":"s2","desc":"Redact PII from email_text","inputs":["email_text"],"outputs":["redacted_text"]},
            {"id":"s3","desc":"Summarize redacted_text into problem statement","inputs":["redacted_text"],"outputs":["summary"]},
            {"id":"s4","desc":"Draft policy response using summary","inputs":["summary"],"outputs":["draft_reply"]}
          ],
          "assumptions":["Email is accessible via provided id","Redaction policy: remove names, phone numbers, emails"]
        }
      }
    ]
  },

  "validator": {
    "system": "You are a Validator. You are given a proposed plan (list of steps) and must check for structural problems: missing inputs, disconnected nodes, cycles, unsafe node types, and unclear outputs. Return JSON with 'ok' or a list of issues.",
    "user_template": "Plan: {{plan}}\nReturn: { \"ok\": true|false, \"issues\": [ ... ] }",
    "few_shot": [
      {
        "plan": {"steps":[{"id":"a","desc":"fetch"},{"id":"b","desc":"summarize","inputs":["fetch.output"]}]},
        "response": {"ok":true,"issues":[]}
      },
      {
        "plan": {"steps":[{"id":"x","desc":"summarize","inputs":["missing.output"]}]},
        "response": {"ok":false,"issues":["Step 'summarize' references non-existent input 'missing.output'"]}
      }
    ]
  },

  "planner": {
    "system": "You are the Planner. Given decomposed tasks (atomic steps) and metadata, produce a ranked set of candidate Plans (N variants). Each plan should include nodes, edges, node-type mapping, cost estimates, and per-node confidence. Return JSON array 'plans'.",
    "user_template": "Tasks: {{tasks}}\nConstraints: {{constraints}}\nReturn: { \"plans\": [ { \"id\": \"p1\", \"nodes\": [...], \"edges\": [...], \"est_cost\": 123, \"confidence\": 0.7 } ] }",
    "few_shot": [
      {
        "tasks": [{"id":"t1","desc":"fetch report"},{"id":"t2","desc":"summarize"}],
        "response": {"plans":[{"id":"p1","nodes":[{"id":"n1","type":"http.fetch","confidence":0.9},{"id":"n2","type":"bitnet.summarize","confidence":0.6}],"edges":[{"from":"n1","to":"n2"}],"est_cost":50,"confidence":0.65}]}
      }
    ]
  },

  "critic": {
    "system": "You are the Critic. For each candidate plan, score (0-1) along structure, cost, safety, and expected quality. Return JSON with 'scores' and short rationale for each plan id.",
    "user_template": "Plans: {{plans}}\nReturn: { \"scores\": [{\"plan_id\":\"p1\",\"structure\":0.9,\"cost\":0.6,\"safety\":0.8,\"quality\":0.7,\"rationale\":\"...\" }] }",
    "few_shot": [
      {
        "plans": [{"id":"p1","nodes":[{"id":"n1"},{"id":"n2"}],"est_cost":50}],
        "response": {"scores":[{"plan_id":"p1","structure":0.9,"cost":0.6,"safety":0.95,"quality":0.7,"rationale":"Compact plan, low risk."}]}
      }
    ]
  },

  "meta_controller": {
    "system": "You are the Meta-Controller. You receive outputs from Decomposer, Validator, Planner, and Critic. Your job is to select the final plan, attach trace metadata, choose the Nickel template variant, and set execution parameters (concurrency, retries). Return the final Plan object to be rendered to Nickel.",
    "user_template": "Inputs: {\"decomp\":...,\"validator\":...,\"planner\":...,\"critic\":... }\nReturn: { \"final_plan\": {...}, \"reason\": "..." }",
    "few_shot": [
      {
        "inputs": {"decomp":{},"validator":{},"planner":{},"critic":{}},
        "response": {"final_plan":{"id":"final-1","nodes":[],"edges":[]},"reason":"Highest weighted quality and safety."}
      }
    ]
  }
}
```

---

## A2 — Nickel Module (pocketflow.prompts)

Below is a Nickel module that exposes the prompt pack as a record and can be imported into Nickel templates or used by the orchestrator to store prompt text alongside Nickel templates.

```nickel
/* pocketflow_prompts.ncl */
{
  decomposer = {
    system = "You are a Decomposer agent. Given a single user goal, split it into the smallest possible actionable steps...";
    user_template = "Goal: {{goal}}\nConstraints: {{constraints}}\nReturn: { \"steps\": [... ] }";
  };

  validator = {
    system = "You are a Validator. You are given a proposed plan (list of steps) and must check for structural problems...";
    user_template = "Plan: {{plan}}\nReturn: { \"ok\": true|false, \"issues\": [ ... ] }";
  };

  planner = {
    system = "You are the Planner. Given decomposed tasks and metadata, produce a ranked set of candidate Plans...";
    user_template = "Tasks: {{tasks}}\nConstraints: {{constraints}}\nReturn: { \"plans\": [...] }";
  };

  critic = {
    system = "You are the Critic. For each candidate plan, score (0-1) along structure, cost, safety, and expected quality...";
    user_template = "Plans: {{plans}}\nReturn: { \"scores\": [...] }";
  };

  meta_controller = {
    system = "You are the Meta-Controller. You receive outputs from Decomposer, Validator, Planner, and Critic...";
    user_template = "Inputs: {\"decomp\":...,\"validator\":...,\"planner\":...,\"critic\":... }\nReturn: { \"final_plan\": {...} }";
  };
}
```

Save this file as `nickel/contracts/pocketflow_prompts.ncl` and import it in templates with `let prompts = import "../contracts/pocketflow_prompts.ncl"`.

---

## A3 — Complete PocketFlow Workflow Example (JSON)

This example demonstrates a real end-to-end `workflow.json` for: "Summarize a PDF report, extract action items, draft an email reply." It uses BitNet nodes and shows state passing.

```json
{
  "metadata": { "name": "report-summary-and-reply", "version": "0.1", "description": "Fetch report, OCR, summarize, extract actions, draft reply" },

  "nodes": [
    {
      "id": "fetch",
      "type": "http.fetch",
      "config": { "url": "https://example.com/report.pdf", "method": "GET" },
      "outputs": { "file_path": "string" }
    },

    {
      "id": "ocr",
      "type": "local.ocr",
      "config": { "engine": "tesseract", "lang": "eng" },
      "inputs": { "file_path": "fetch.outputs.file_path" },
      "outputs": { "text": "string" }
    },

    {
      "id": "chunk",
      "type": "preprocess.chunker",
      "config": { "chunk_size": 1500, "overlap": 200 },
      "inputs": { "text": "ocr.outputs.text" },
      "outputs": { "chunks": "array[string]" }
    },

    {
      "id": "summarize_map",
      "type": "bitnet.batch_summarizer",
      "config": { "model": "bitnet-tiny-v1", "max_tokens": 256, "temperature": 0.2 },
      "inputs": { "chunks": "chunk.outputs.chunks" },
      "outputs": { "chunk_summaries": "array[string]" }
    },

    {
      "id": "summarize_reduce",
      "type": "bitnet.reducer",
      "config": { "model": "bitnet-tiny-v1", "method": "concat_then_summarize" },
      "inputs": { "summaries": "summarize_map.outputs.chunk_summaries" },
      "outputs": { "summary": "string" }
    },

    {
      "id": "extract_actions",
      "type": "bitnet.extractor",
      "config": { "model": "bitnet-tiny-v1", "schema": { "type":"array","items":{"type":"object","properties":{"action":{"type":"string"},"owner":{"type":"string"},"due":{"type":"string"}}}} },
      "inputs": { "summary": "summarize_reduce.outputs.summary" },
      "outputs": { "actions": "array[object]" }
    },

    {
      "id": "draft_reply",
      "type": "bitnet.codegen",
      "config": { "model": "bitnet-tiny-v1", "max_tokens": 400, "style": "concise, professional" },
      "inputs": { "summary": "summarize_reduce.outputs.summary", "actions": "extract_actions.outputs.actions" },
      "outputs": { "draft": "string" }
    }
  ],

  "edges": [
    { "from": {"node":"fetch","port":"file_path"}, "to": {"node":"ocr","port":"file_path"} },
    { "from": {"node":"ocr","port":"text"}, "to": {"node":"chunk","port":"text"} },
    { "from": {"node":"chunk","port":"chunks"}, "to": {"node":"summarize_map","port":"chunks"} },
    { "from": {"node":"summarize_map","port":"chunk_summaries"}, "to": {"node":"summarize_reduce","port":"summaries"} },
    { "from": {"node":"summarize_reduce","port":"summary"}, "to": {"node":"extract_actions","port":"summary"} },
    { "from": {"node":"summarize_reduce","port":"summary"}, "to": {"node":"draft_reply","port":"summary"} },
    { "from": {"node":"extract_actions","port":"actions"}, "to": {"node":"draft_reply","port":"actions"} }
  ],

  "settings": { "retry_policy": "exponential_backoff", "concurrency": 2, "trace_id": "auto" }
}
```

### Notes on the workflow example

* `bitnet.batch_summarizer` should support map-reduce pattern — run summarization on each chunk in parallel.
* `bitnet.reducer` concatenates chunk summaries and runs a final summarization pass.
* Node `config.model` refers to a local gguf model (packaged in `bitnet-workers/models/`).
* Outputs use stable keys like `outputs.summary` to wire nodes.

---

## A4 — Templates Tuned for Extremely Small BitNet Models

Principles:

* Keep prompts extremely short (max 120 tokens).
* Use explicit instructions for output structure (JSON schema), and limit generation length.
* Use constrained decoding (low temperature 0.0–0.2, nucleus sampling p=0.6 if available).
* Avoid chain-of-thought; use direct step answers.
* Where possible, transform a task into multiple cheap operations (map-reduce).

### Example compact summarization prompt (for a chunk)

```
SYSTEM: You are a compact summarizer. Output a single-sentence summary (max 30 words) as JSON: {"summary":"..."}.
USER: Text: "{{chunk_text}}"
ASSISTANT:
```

### Example compact extractor prompt (for action items)

```
SYSTEM: Extract action items from the text. Return JSON array of objects: [{"action":"...","owner":"...","due":"..."}]. If none, return [].
USER: Summary: "{{summary_text}}"
ASSISTANT:
```

### Decoding and runtime settings (recommendations)

* `max_tokens` = 64 for summarizer; 128 for codegen/extraction.
* `temperature` = 0.0 — deterministic.
* `top_p` = 0.7 (if supported).
* `repetition_penalty` = 1.1
* Use `n` = 3 and ensemble-agreement if confidence is needed (vote on identical JSON keys).

### Short reflection prompt (for tiny models)

Keep reflection minimal — use only when validator detects schema mismatch.

```
SYSTEM: You are a quick validator. Given output and expected schema, say 'ok' or list up to 3 issues. Return JSON: {"ok":true|false,"issues":[...]}
USER: Output: {{output}}
Schema: {{schema}}
ASSISTANT:
```

---

## Usage & Integration Tips

* Store these prompts centrally (Nickel module) and version them alongside Nickel templates.
* Use the Planner + Critic to choose when to run tiny models vs escalate to larger LLMs.
* Always validate BitNet outputs with a lightweight JSON schema validator before passing downstream.
* For long documents, always chunk and map-reduce.

---

