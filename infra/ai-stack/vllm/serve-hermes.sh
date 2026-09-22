#!/usr/bin/env bash
# Hermes 4.3 36B (Apache 2.0) on one 80 GB GPU. Registered in LiteLLM as hermes-4.3-36b.
set -euo pipefail
docker run --gpus all --ipc=host -p 8000:8000 \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  -e HF_TOKEN="${HF_TOKEN:?}" \
  vllm/vllm-openai:latest \
  --model NousResearch/Hermes-4.3-36B \
  --served-model-name hermes-4.3-36b \
  --max-model-len 65536 \
  --gpu-memory-utilization 0.92 \
  --enable-auto-tool-choice --tool-call-parser hermes
