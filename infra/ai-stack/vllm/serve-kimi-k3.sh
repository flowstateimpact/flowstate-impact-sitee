#!/usr/bin/env bash
# Reference self-host of Kimi K3. DO NOT run this for 5 users: the API is ~100x cheaper.
# Minimum hardware: one node with 8x B300 (or 8x MI355X). H200 needs 2 nodes x 8 (TP=16).
# Verify current flags at https://recipes.vllm.ai/moonshotai/Kimi-K3 before use.
set -euo pipefail
docker run --gpus all --ipc=host -p 8001:8000 \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  -e HF_TOKEN="${HF_TOKEN:?}" \
  vllm/vllm-openai:nightly \
  --model moonshotai/Kimi-K3 \
  --served-model-name kimi-k3 \
  --tensor-parallel-size 8 \
  --trust-remote-code \
  --load-format fastsafetensors \
  --enable-prefix-caching \
  --kv-cache-dtype fp8 \
  --max-model-len 262144 \
  --enable-auto-tool-choice --tool-call-parser kimi_k3 \
  --reasoning-parser kimi_k3
# 4-GPU alternative (Kimi K2.6, not K3): nvidia/Kimi-K2.6-NVFP4 --tensor-parallel-size 4 on 4x B300.
