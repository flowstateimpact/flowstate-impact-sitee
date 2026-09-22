#!/usr/bin/env bash
# Pull the open-weight media models into ComfyUI's model dirs.
# Usage: HF_TOKEN=... download-models [all|ltx|wan|image]
set -euo pipefail
M=${COMFY_MODELS_DIR:-/opt/ComfyUI/models}
HF="/venv/bin/hf download"
what=${1:-all}

ltx() {
  # LTX-2.5 (Aug 2026). Split, Comfy-aligned pack. ~66 GB full; use distilled on <80 GB cards.
  $HF Lightricks/LTX-2.5 --local-dir "$M/ltx/LTX-2.5"
  # Fallback for smaller GPUs
  $HF Lightricks/LTX-2.3-fp8 --local-dir "$M/ltx/LTX-2.3-fp8"
}
wan() {
  # Wan 2.2 (Apache 2.0). Comfy repackaged fp8 diffusion models + VAE + text encoder.
  $HF Comfy-Org/Wan_2.2_ComfyUI_Repackaged --local-dir "$M/wan/Wan2.2" \
     --include "split_files/diffusion_models/wan2.2_t2v_*fp8*" \
               "split_files/diffusion_models/wan2.2_i2v_*fp8*" \
               "split_files/diffusion_models/wan2.2_ti2v_5B*" \
               "split_files/vae/*" "split_files/text_encoders/*"
  # Wan 2.7: official weights are on ModelScope (community HF mirrors only). Add manually.
  # Wan 3.0: API-only; use ComfyUI API nodes (billed per call).
}
image() {
  $HF black-forest-labs/FLUX.2-klein --local-dir "$M/diffusion_models/FLUX.2-klein"
  $HF Qwen/Qwen-Image-2512 --local-dir "$M/diffusion_models/Qwen-Image-2512"
  $HF HiDream-ai/HiDream --local-dir "$M/diffusion_models/HiDream"
}
case "$what" in
  all) ltx; wan; image ;;
  ltx) ltx ;; wan) wan ;; image) image ;;
  *) echo "usage: download-models [all|ltx|wan|image]"; exit 1 ;;
esac
echo "Models in $M. Point LTX/Wan nodes at the split files; see each repo card for the exact file names."
