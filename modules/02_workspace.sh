#!/usr/bin/env bash
set -euo pipefail

# =========[ MODUŁ 02: WORKSPACE DIRS ]=========
WORKDIR="${WORKDIR:-/workspace}"

# Główne katalogi
mkdir -p "${WORKDIR}/input" \
         "${WORKDIR}/output" \
         "${WORKDIR}/workflows" \
         "${WORKDIR}/logs"

# Katalogi na modele (uniwersalne pod ComfyUI)
for d in checkpoints clip diffusion_models vae unet lora text_encoders; do
  mkdir -p "${WORKDIR}/models/${d}"
done

# Miejsce na ComfyUI (kod) i custom_nodes
mkdir -p "${WORKDIR}/ComfyUI/custom_nodes" \
         "${WORKDIR}/ComfyUI/models"

# Podlinkuj modele z /workspace/models -> ComfyUI/models
for d in checkpoints clip diffusion_models vae unet lora text_encoders; do
  mkdir -p "${WORKDIR}/ComfyUI/models/${d}"
  ln -sfn "${WORKDIR}/models/${d}" "${WORKDIR}/ComfyUI/models/${d}"
done

echo "[workspace] przygotowano katalogi w ${WORKDIR}"
# =========[ /MODUŁ 02 ]=========
