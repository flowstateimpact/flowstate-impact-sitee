# Flowstate AI Platform — Architecture & Setup Plan

_Last researched: 22 Sep 2026. Prices and recipes move fast; re-check before committing spend._

## 0. What this covers

You asked for one setup that does all of the following:

| # | Need | Decision (short) |
|---|------|------------------|
| 1 | Kimi K3 for 5 internal users, "4x optimised" | **API, not self-host.** Route through LiteLLM to Moonshot + Fireworks (fastest) with fallback. Self-hosting K3 needs a minimum of 8× B300; it only pays off past ~10B tokens/month. |
| 2 | Claude Opus-class + Fable 20x plan | Humans keep using the **Max 20x** plan in Claude Code / Claude app. Everything programmatic (gateway, custom UI, client agents) uses **API keys** on Commercial Terms: `claude-opus-5` default, `claude-fable-5-1` for the hardest work. |
| 3 | Hermes "attached to" Kimi K3 | Run **Hermes Agent** (Nous, MIT) as the agent runtime, pointed at the LiteLLM gateway so it uses Kimi K3 (or Opus) as its brain. Optionally self-host **Hermes 4.3 36B** on one GPU as a cheap open model. |
| 4 | LTX + Wan video, image gen, ComfyUI | One **media GPU box** (H200 141 GB, or H100 80 GB with quantized weights) running ComfyUI in multi-user mode: LTX-2.5, Wan 2.2 (open) + Wan 3.0 (API nodes), FLUX.2 / Qwen-Image / HiDream for images. |
| 5 | Custom UI + agents + HuggingFace models | **LibreChat** on top of LiteLLM. HF models via HF Inference Providers (through LiteLLM) or self-hosted vLLM. |
| 6 | Client agentic setups on subscription, in cloud | Multi-tenant: one LiteLLM virtual key per client (budget + rate limit), one Hermes Agent container per client, or Claude Managed Agents for Claude-native agents. Stripe for billing, LiteLLM spend logs for metering. |

Everything below is deployable from `infra/ai-stack/` (docker compose). Start on **one CPU control-plane VM + one rented GPU box**, and add GPUs only when spend data says so.

---

## 1. Kimi K3: API vs hardware

### Facts (Sep 2026)

- 2.8T-parameter MoE (16 experts active), 1M-token context, native vision. Weights released 27 Jul 2026 in native 4-bit (MXFP4). Licence is a "modified MIT": attribution required only above 100M MAU or $20M/month revenue; selling it as model-as-a-service needs a Moonshot agreement above $20M/year.
- **API pricing is flat everywhere:** $3.00/M input, $0.30/M cached input, $15.00/M output. Providers differ only on speed. Fireworks is the fastest of the mainstream providers (~69 tok/s sustained); Moonshot's own endpoint is ~30 tok/s. Some newer providers (Nebius, Inco) list 200+ tok/s on Artificial Analysis.
- **Self-hosting floor:** ~594 GB to load. vLLM's smallest single-node recipe is **8× B300** (or 8× MI355X). H200 needs **2 nodes × 8 GPUs** (TP=16). H100 needs 32 GPUs. There is no 4-GPU Kimi K3 config; 4× B300 with TP=4 is a published recipe only for **Kimi K2.6-NVFP4**.

### Cost math for 5 users

Assume a heavy agentic month per user of 20M input tokens (70% cache hits) and 2M output tokens.

| Option | Monthly cost | Notes |
|--------|-------------:|-------|
| Kimi K3 API (5 users) | **~$300–450** | 5 × (6M miss × $3 + 14M hit × $0.30 + 2M × $15) ≈ $5 × 52 ≈ $260 + headroom |
| Self-host, 2× (8× H200) @ ~$4.59/GPU/hr | ~$53,000 | 16 GPUs × 24/7 |
| Self-host, 16× B200 @ ~$6.79/GPU/hr | ~$79,000 | B300 pricing is quote-only, expect higher |

Break-even versus the API is roughly **10B+ tokens/month** at sustained utilisation. Five people cannot generate that. Even a client business at 50 tenants is usually still cheaper on the API.

### "4x optimised" — what you can actually do

1. **Speed:** route to the fastest provider (Fireworks / Nebius) with Moonshot as fallback. LiteLLM config in `infra/ai-stack/litellm/config.yaml` does this.
2. **Cost:** keep system prompts and tool definitions stable so Moonshot's cache hits (10× cheaper input) fire. Use `kimi-k3:batch` on OpenRouter for offline jobs.
3. **Latency for agents:** Kimi K3 supports tool calling and reasoning natively; enable the `kimi_k3` tool/reasoning parser where you self-host, and pass `tools` through LiteLLM unchanged.
4. **If you must own GPUs later:** the reference `vllm serve` for 8× B300 is in `infra/ai-stack/vllm/serve-kimi-k3.sh`. Do not buy this until the gateway's spend logs show >$25k/month on Kimi.

---

## 2. Claude: Max 20x vs API keys

- Your **Max 20x plan** ($200/mo) is for the 5 humans: Claude Code, Claude app, Claude Desktop. Keep using it there.
- **Do not** wire Max OAuth tokens into LiteLLM, LibreChat, Hermes Agent, or client agents. Anthropic patched the auth path in Feb 2026 and it is a Consumer-Terms violation. Non-interactive Agent SDK usage from a plan still draws from the plan's session limits, and the promised separate SDK credit was paused.
- For everything programmatic, create an **Anthropic Console org** (Commercial Terms, pay-as-you-go) and put the key in LiteLLM.

| Model | ID | $/M in | $/M out | Use for |
|-------|----|-------:|--------:|---------|
| Claude Fable 5.1 | `claude-fable-5-1` | 10 | 50 | Hardest reasoning / long-horizon agent runs. Thinking always on; control depth with `output_config.effort`. |
| Claude Opus 5 | `claude-opus-5` | 5 | 25 | **Default** for agents and the custom UI. Adaptive thinking on by default. |
| Claude Sonnet 5 | `claude-sonnet-5` | 2 | 10 | Sub-agents, bulk extraction, client tiers with tight margins. |
| Claude Haiku 4.5 | `claude-haiku-4-5` | 1 | 5 | Routing / classification. |

Where you use Claude-specific features (Managed Agents, server-side web search, code execution, prompt caching breakpoints, Files API), call the **Anthropic SDK directly** rather than through the OpenAI-compatible gateway; the gateway is for chat completions and tool calls that must be model-agnostic.

---

## 3. Hermes

Two different things share the name:

1. **Hermes 4 / 4.3 open models** (Nous Research). Sizes 14B, 36B, 70B, 405B. **Hermes 4.3 36B** (Apache 2.0, Dec 2025) is the best self-host value: nearly 70B quality, fits one 80 GB GPU in BF16 (~72 GB) or one 48 GB card in FP8. Also on OpenRouter if you'd rather not host.
2. **Hermes Agent** (MIT, v0.21.x as of Sep 2026): an open agent runtime with persistent memory, skill creation, desktop app, and "Bot Mode" multi-agent groups. It talks to **any OpenAI-compatible endpoint**, so pointing it at the LiteLLM gateway gives you "Hermes running on Kimi K3" or "Hermes running on Opus 5" with one env var change.

**Recommendation:** use Hermes Agent as the runtime for client agents where you want an open, self-hostable loop. Set `OPENAI_BASE_URL=http://litellm:4000/v1` and `MODEL=kimi-k3` (or `claude-opus-5`). Self-host Hermes 4.3 36B only if you want a zero-per-token open model for cheap client tiers (`infra/ai-stack/vllm/serve-hermes.sh`).

---

## 4. Media generation: LTX, Wan, images, ComfyUI

### Models (open weights, commercial-usable)

| Model | Weights | Licence | VRAM | Notes |
|-------|---------|---------|------|-------|
| **LTX-2.5** (11 Aug 2026) | `Lightricks/LTX-2.5` | LTX-2 Community License (check revenue caps) | ~66 GB BF16, 30–35 GB quantized | Video + synced audio in one pass. Needs CUDA 13.2+. Use the distilled checkpoint below H100. Nodes: `Lightricks/ComfyUI-LTXVideo`. |
| LTX-2.3 FP8 | `Lightricks/LTX-2.3-fp8` | same | 16–32 GB | Fallback for smaller GPUs. |
| **Wan 2.2** | `Wan-AI/Wan2.2-T2V-A14B`, `-I2V-A14B`, `-TI2V-5B`; Comfy-repackaged: `Comfy-Org/Wan_2.2_ComfyUI_Repackaged` | Apache 2.0 | 5B: 24 GB; A14B fp8: ~40 GB; full: 80 GB | Last fully-open Wan with native ComfyUI support. |
| Wan 2.7 | ModelScope (official), HF community mirrors | check card | 80 GB+ | Community nodes only; treat as experimental. |
| Wan 3.0 | **API only** | per-call | none | Available as ComfyUI API nodes (30 s single-pass, 20-reference omni). Billed per resolution tier. |
| FLUX.2 [klein] 4B | `black-forest-labs/FLUX.2-klein` | Apache 2.0 | 12 GB | Fast images. |
| Qwen-Image-2512 | `Qwen/Qwen-Image-2512` | Apache 2.0 | 40 GB bf16 / 20 GB fp8 | Best text rendering (posters, UI mockups). |
| HiDream (8B, May 2026) | `HiDream-ai/HiDream` | MIT | 20 GB | Pixel-native, no external VAE. |

### Hardware

- **Preferred:** 1× **H200 141 GB** ($3.59–4.59/hr on RunPod; ~$2.6–3.3k/month 24/7, or ~$800/month if you only run it 8h × 22 days). Fits LTX-2.5 full + Wan 2.2 A14B fp8 + FLUX.2 resident at once.
- **Budget:** 1× H100 80 GB ($2–3/hr) with LTX-2.5 distilled/quantized and Wan 2.2 fp8. Model swapping costs ~30–60 s.
- **Not recommended:** consumer 24 GB cards for LTX-2.5; you'd be stuck on FP8 LTX-2.3.

### Multi-user ComfyUI for 5 people

- Run ComfyUI with `--multi-user` (per-user workflows/settings) behind Caddy with auth (basic auth to start; Authentik/OIDC later).
- One GPU serialises jobs; that is fine for 5 people. If queues get long, add a second identical box and put a queue in front (ComfyUI's `/prompt` API + Redis) rather than sharing one bigger GPU.
- For client-facing generation, never expose the UI. Call ComfyUI's JSON-workflow API from your app with a saved workflow per product feature.

---

## 5. Custom UI, agents, HuggingFace

**Gateway: LiteLLM** (OpenAI-compatible, 140+ providers). One endpoint, virtual keys, per-key budgets, rate limits, fallbacks, spend logs in Postgres. This is the multi-tenant control point for everything below.

**UI: LibreChat.** Chosen over Open WebUI because it ships agents, MCP servers, code interpreter, artifacts, OIDC/LDAP, and per-user model permissions without extra middleware. Point it at LiteLLM as a single "custom endpoint". (Open WebUI is fine if you prefer its RAG/web-search built-ins; the compose file lets you swap.)

**HuggingFace models:**
- Hosted: LiteLLM's `huggingface/` provider routes to HF Inference Providers (Together, Fireworks, Nebius etc.) with your HF token. Add any model as a line in `config.yaml`.
- Self-hosted: `vllm serve <hf-repo>` on the GPU box (template in `infra/ai-stack/vllm/`). Register it in LiteLLM as `openai/<name>` with `api_base` pointing at the vLLM container.
- Gradio/Spaces demos: run as extra compose services; LibreChat can embed them via its plugin/MCP surface.

**Agent runtimes available on this stack:**

| Runtime | Best for | Hosting |
|---------|----------|---------|
| LibreChat Agents + MCP | Internal team, quick agents with tools | control-plane VM |
| Hermes Agent | Open, persistent-memory agents per client | one container per tenant |
| Claude Managed Agents | Claude-native agents with hosted sandbox, scheduled runs, outcome grading | Anthropic-hosted, you own the config |
| Own code (Anthropic SDK tool runner / OpenAI-compat via LiteLLM) | Product-embedded agents with custom tools | your app |

---

## 6. Client agentic setups on subscription

Model each client as a **tenant**:

1. `POST /key/generate` on LiteLLM with `team_id=<client>`, `max_budget`, `rpm_limit`, `models=[...]` (script: `infra/ai-stack/tenants/create-tenant.sh`). This is the only credential the client's agents hold. Provider keys never leave the gateway.
2. Spin one Hermes Agent container (or a LibreChat workspace, or a Managed Agent) with that key.
3. Stripe subscription -> webhook -> raise/lower `max_budget` on the key. Overage = LiteLLM returns 429 and you email them.
4. Metering: LiteLLM's `spend_logs` table (Postgres) gives per-key/per-model tokens and dollars; export to your dashboard.

**Pricing guardrail:** at Opus 5 rates, a client agent that does 5M in / 500k out per month costs you ~$37; on Kimi K3 ~$25; on Sonnet 5 ~$15. Price tiers at 3–5× COGS and cap with `max_budget`.

**Cloud layout (phase 1, this month):**

```
Control-plane VM (8 vCPU / 32 GB, Hetzner/AWS)        GPU box (RunPod/Lambda, on-demand)
 ├─ Caddy (TLS, auth)                                   ├─ ComfyUI --multi-user  (LTX-2.5, Wan 2.2, FLUX.2)
 ├─ LiteLLM gateway  :4000  ──► Moonshot / Fireworks    └─ vLLM (optional: Hermes 4.3 36B / any HF model)
 │                             Anthropic API
 │                             OpenRouter / HF Inference
 ├─ LibreChat        :3080
 ├─ Hermes Agent (one per tenant)
 ├─ Postgres + Redis + MongoDB (LibreChat)
 └─ MinIO (S3 for generated media)
```

**Phase 2 (when >20 tenants or >$5k/month spend):** move control plane to Kubernetes (k3s is enough), one namespace per tenant, LiteLLM in HA with Redis, GPU workers as a separate node pool with autoscaling to zero, S3 instead of MinIO, Grafana on LiteLLM's Prometheus metrics.

**Phase 3 (only if spend logs justify):** dedicated 8× B300 for Kimi K3 at ~$25k+/month sustained Kimi spend; until then the API is strictly cheaper.

---

## 7. What to do this week

1. Create accounts: Anthropic Console (API), Moonshot, Fireworks, OpenRouter, HuggingFace (token), RunPod.
2. `cp infra/ai-stack/.env.example infra/ai-stack/.env`, fill in keys, `docker compose up -d` on the control-plane VM.
3. Rent one H200 pod, run `infra/ai-stack/comfyui/download-models.sh`, start ComfyUI, confirm an LTX-2.5 and a Wan 2.2 render.
4. Create 5 internal LiteLLM keys (one per person) so you can see who spends what.
5. Onboard one pilot client with `create-tenant.sh` and a Hermes Agent container.
6. After 30 days, read `spend_logs` and decide on GPU purchases with data instead of guesses.

## 8. Things to verify before spending money

WebFetch to several primary sources was blocked from this environment, so these came from secondary write-ups and should be re-checked on the primary page:

- vLLM Kimi-K3 recipe flags per GPU type: https://recipes.vllm.ai/moonshotai/Kimi-K3
- LTX-2.5 licence revenue caps and exact file names: https://huggingface.co/Lightricks/LTX-2.5
- Kimi K3 licence text: https://github.com/MoonshotAI/Kimi-K3/blob/main/LICENSE
- Agent SDK plan-usage rules: https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan
- GPU prices on the day: https://lambda.ai/pricing, https://www.runpod.io/pricing

## Sources

- Kimi K3 pricing/specs: https://openrouter.ai/moonshotai/kimi-k3 , https://benchlm.ai/moonshot/api-pricing , https://merchmindai.net/blog/en/post/kimi-k3-release-api-pricing-user-feedback
- Kimi K3 self-hosting: https://northflank.com/blog/what-is-kimi-k3-self-hosting , https://www.spheron.network/blog/deploy-kimi-k3-gpu-cloud/ , https://vllm.ai/blog/2026-07-27-k3 , https://vllm.ai/blog/2026-09-13-kimi-k3-performance-optimization , https://docs.nvidia.com/dynamo/v1.4.2/recipes/kimi-k3
- Kimi K3 providers/speed: https://artificialanalysis.ai/models/kimi-k3/providers , https://medium.com/@2100015853sxk/i-compared-every-kimi-k3-provider-so-you-dont-have-to-8e011d79ed51
- Kimi K3 licence: https://venturebeat.com/technology/kimi-k3s-full-weights-are-here-but-theyre-open-with-a-caveat-what-enterprises-should-know , https://kingy.ai/ai/ai-guides/kimi-k3-license-commercial-use-open-source/
- Claude plans vs API: https://www.theregister.com/software/2026/02/20/anthropic-clarifies-ban-on-third-party-tool-access-to-claude/5014546 , https://www.totalum.app/blog/claude-agent-sdk-totalum-2026
- Hermes: https://vantaige.io/blog/nous-hermes-4-self-hosted-setup-vs-closed-agents-2026 , https://github.com/nousresearch/hermes-agent , https://openrouter.ai/nousresearch
- LTX-2.5 / 2.3: https://www.mindstudio.ai/blog/ltx-2-5-comfyui-install-guide , https://www.thundercompute.com/blog/ltx-2-3-comfyui , https://github.com/Lightricks/ComfyUI-LTXVideo/
- Wan: https://www.atlascloud.ai/blog/tips/is-wan-3.0-open-source , https://comfyui-wiki.com/en/news/2026-09-05-wan3-comfyui-api-nodes , https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged , https://wan27.org/blog/wan-2-7-open-source-guide
- Image models: https://www.thundercompute.com/blog/best-open-source-image-generation-models , https://presenc.ai/research/best-open-weight-image-generation-models-2026
- GPU pricing: https://www.thundercompute.com/blog/nvidia-h200-pricing , https://intuitionlabs.ai/articles/h100-rental-prices-cloud-comparison , https://www.spheron.network/blog/runpod-h100-pricing-2026/
- Gateway/UI: https://docs.litellm.ai/docs/simple_proxy , https://docs.litellm.ai/docs/tutorials/openweb_ui , https://blog.elest.io/librechat-vs-openwebui-vs-lobe-chat-which-to-self-host-in-2026/
