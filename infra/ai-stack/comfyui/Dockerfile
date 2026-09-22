# ComfyUI + LTX + Wan + image model nodes. Build on the GPU host.
FROM nvidia/cuda:13.2.0-runtime-ubuntu24.04
ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip git ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /opt
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /opt/ComfyUI
RUN python3 -m venv /venv && /venv/bin/pip install -U pip && \
    /venv/bin/pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130 && \
    /venv/bin/pip install -r requirements.txt huggingface_hub[cli]
# Custom nodes
RUN cd custom_nodes && \
    git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-WanVideoWrapper.git && \
    for d in */; do [ -f "$d/requirements.txt" ] && /venv/bin/pip install -r "$d/requirements.txt" || true; done
COPY download-models.sh /usr/local/bin/download-models
RUN chmod +x /usr/local/bin/download-models
EXPOSE 8188
ENTRYPOINT ["/venv/bin/python", "main.py"]
