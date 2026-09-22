# infra/ai-stack

Deployable scaffold for the plan in `docs/ai-platform/architecture.md`.

| Path | What |
|------|------|
| `docker-compose.yml` | Control plane (Caddy, LiteLLM, LibreChat, Postgres, Redis, Mongo, MinIO) + `gpu` profile (ComfyUI, vLLM Hermes) + `tenants` profile (example Hermes Agent). |
| `litellm/config.yaml` | Model routing: Kimi K3 across Fireworks/Moonshot/OpenRouter, Claude via API keys, Hermes, HF Inference Providers, client tier aliases. |
| `librechat.yaml` | LibreChat pointed at the gateway. |
| `Caddyfile` | TLS + basic auth in front of chat / api / ComfyUI. |
| `comfyui/` | ComfyUI image (CUDA 13.2, LTX + Wan nodes) and model downloader. |
| `vllm/` | Serve scripts: Hermes 4.3 36B (1 GPU) and a reference Kimi K3 (8x B300, not recommended yet). |
| `tenants/create-tenant.sh` | One command per client: budgeted, rate-limited virtual key. |

## Bring-up

```bash
cp .env.example .env            # fill in keys
docker compose up -d            # control plane on the CPU VM
# on the GPU host:
docker compose --profile gpu build comfyui
docker compose --profile gpu run --rm comfyui /usr/local/bin/download-models all
docker compose --profile gpu up -d comfyui vllm-hermes
# first internal key for the UI:
LITELLM_MASTER_KEY=... tenants/create-tenant.sh internal 500 pro   # put key in LIBRECHAT_GATEWAY_KEY
```

Smoke test the gateway:

```bash
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H 'Content-Type: application/json' \
  -d '{"model":"kimi-k3","messages":[{"role":"user","content":"ping"}]}'
```
