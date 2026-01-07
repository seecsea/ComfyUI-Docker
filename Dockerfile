# Set the base image
ARG BASE_IMAGE=nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04
FROM ${BASE_IMAGE}

# Set the shell and enable pipefail for better error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set basic environment variables
ARG PYTHON_VERSION
ARG TORCH_VERSION
ARG CUDA_VERSION
ARG SKIP_CUSTOM_NODES

# Set basic environment variables
ENV SHELL=/bin/bash 
ENV PYTHONUNBUFFERED=True 
ENV DEBIAN_FRONTEND=noninteractive

# Set the default workspace directory
ENV RP_WORKSPACE=/workspace

# Override the default huggingface cache directory.
ENV HF_HOME="${RP_WORKSPACE}/.cache/huggingface/"

# Faster transfer of models from the hub to the container
ENV HF_HUB_ENABLE_HF_TRANSFER=1
ENV HF_XET_HIGH_PERFORMANCE=1

# Shared python package cache
ENV VIRTUALENV_OVERRIDE_APP_DATA="${RP_WORKSPACE}/.cache/virtualenv/"
ENV PIP_CACHE_DIR="${RP_WORKSPACE}/.cache/pip/"
ENV UV_CACHE_DIR="${RP_WORKSPACE}/.cache/uv/"

# modern pip workarounds
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV PIP_ROOT_USER_ACTION=ignore

# Set TZ and Locale
ENV TZ=Etc/UTC

# Set working directory
WORKDIR /

# Update and upgrade
RUN sed -i 's|^URIs:.*archive.ubuntu.com.*|URIs: https://mirrors.cloud.tencent.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources && \
    apt-get update --yes && \
    apt-get upgrade --yes

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Install essential packages
RUN apt-get install --yes --no-install-recommends \
        git git-lfs wget curl aria2 bash nginx-light rsync sudo binutils ffmpeg lshw nano tzdata file build-essential cmake nvtop \
        libgl1 libglib2.0-0 clang libomp-dev ninja-build fonts-dejavu-core net-tools \
        openssh-server ca-certificates && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install the UV tool from astral-sh
ADD https://astral.sh/uv/install.sh /uv-installer.sh
RUN sh /uv-installer.sh && rm /uv-installer.sh
ENV PATH="/root/.local/bin/:$PATH"

# Install Python and create virtual environment
RUN uv python install ${PYTHON_VERSION} --default --preview && \
    uv venv --seed /venv
ENV PATH="/workspace/venv/bin:/venv/bin:$PATH"

# Install essential Python packages and dependencies
# torch==${TORCH_VERSION} torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/${CUDA_VERSION}
RUN pip config set global.index-url https://mirrors.cloud.tencent.com/pypi/simple/ && \
    pip install --no-cache-dir -U \
    pip setuptools wheel \
    jupyterlab jupyterlab_widgets ipykernel ipywidgets \
    huggingface_hub hf_transfer \
    numpy scipy matplotlib pandas scikit-learn seaborn requests tqdm pillow pyyaml \
    triton \
    torch==${TORCH_VERSION} torchvision torchaudio --extra-index-url https://mirrors.nju.edu.cn/pytorch/whl/${CUDA_VERSION}

# Install ComfyUI and ComfyUI Manager
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install --no-cache-dir -r requirements.txt && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager && \
    cd custom_nodes/ComfyUI-Manager && \
    pip install --no-cache-dir -r requirements.txt

COPY custom_nodes.txt /custom_nodes.txt

RUN if [ -z "$SKIP_CUSTOM_NODES" ]; then \
        cd /ComfyUI/custom_nodes && \
        xargs -n 1 git clone --recursive < /custom_nodes.txt && \
        find /ComfyUI/custom_nodes -name "requirements.txt" -exec pip install --no-cache-dir -r {} \; && \
        find /ComfyUI/custom_nodes -name "install.py" -exec python {} \; ; \
    else \
        echo "Skipping custom nodes installation because SKIP_CUSTOM_NODES is set"; \
    fi

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh && \
    code-server --install-extension cnbcool.cnb-welcome && \
	code-server --install-extension redhat.vscode-yaml && \
	code-server --install-extension waderyan.gitblame && \
	code-server --install-extension mhutchie.git-graph && \
	code-server --install-extension donjayamanne.githistory && \
	code-server --install-extension cloudstudio.live-server && \
	code-server --install-extension tencent-cloud.coding-copilot

EXPOSE 22 3000 8080 8888

# NGINX Proxy
COPY proxy/nginx.conf /etc/nginx/nginx.conf
COPY proxy/snippets /etc/nginx/snippets
COPY proxy/readme.html /usr/share/nginx/html/readme.html

# Remove existing SSH host keys
RUN rm -f /etc/ssh/ssh_host_*

# Copy the README.md
COPY README.md /usr/share/nginx/html/README.md

# Start Scripts
COPY --chmod=755 scripts/start.sh /
COPY --chmod=755 scripts/pre_start.sh /
COPY --chmod=755 scripts/post_start.sh /

COPY --chmod=755 scripts/download_presets.sh /
COPY --chmod=755 scripts/install_custom_nodes.sh /

# Welcome Message
COPY logo/logo.txt /etc/logo.txt
RUN echo 'cat /etc/logo.txt' >> /root/.bashrc
RUN echo 'echo -e "\nFor detailed documentation and guides, please visit:\n\033[1;34mhttps://cnb.cool/itgay\033[0m and \033[1;34mhttps://cnb.cool/itgay\033[0m\n\n"' >> /root/.bashrc

# Set entrypoint to the start script
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

CMD ["/start.sh"]
