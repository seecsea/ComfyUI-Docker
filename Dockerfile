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
RUN apt-get update --yes && \
    apt-get upgrade --yes && \
	apt-get autoremove -y && apt-get clean && rm -rf /var/cache/apt/archives/*

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Install essential packages
RUN apt-get install --yes --no-install-recommends \
        git git-lfs wget curl aria2 bash nginx-light rsync sudo binutils ffmpeg lshw nano tzdata file build-essential cmake nvtop locales \
        libgl1 libglib2.0-0 clang libomp-dev ninja-build fonts-dejavu-core net-tools jq screen htop libssl-dev libffi-dev libsqlite3-0 python3-tk \
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
RUN pip install --no-cache-dir -U \
    pip setuptools wheel \
    jupyterlab jupyterlab_widgets ipykernel ipywidgets \
    huggingface_hub hf_transfer \
    numpy scipy matplotlib pandas scikit-learn seaborn requests tqdm pillow pyyaml \
    triton ninja \
    torch==${TORCH_VERSION} torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/${CUDA_VERSION}

# Install SageAttention and flash_attn
RUN git clone https://github.com/thu-ml/SageAttention.git && \
    git clone https://github.com/thu-ml/SpargeAttn.git && \
    wget https://github.com/mjun0812/flash-attention-prebuild-wheels/releases/download/v0.7.16/flash_attn-2.8.3+cu130torch2.9-cp313-cp313-linux_x86_64.whl && \
	pip install --no-cache-dir flash_attn-2.8.3+cu130torch2.9-cp313-cp313-linux_x86_64.whl && \
	rm -f flash_attn-2.8.3+cu130torch2.9-cp313-cp313-linux_x86_64.whl

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
        find /ComfyUI/custom_nodes -name "requirements.txt" -exec sh -c 'echo "Installing requirements from: $1" && pip install --no-cache-dir -r "$1"' _ {} \; && \
        find /ComfyUI/custom_nodes -name "install.py" -exec sh -c 'echo "Running install script: $1" && python "$1"' _ {} \; && \
        git clone --recursive https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git; \
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
	code-server --install-extension tencent-cloud.coding-copilot && \
	rm -rf $HOME/.cache/code-server/* /root/.config/code-server/logs

# --- VSCode 配置: 禁用预览、设置启动编辑器、禁用 Copilot 欢迎消息 ---
# 修改开始: 专门优化文件打开行为
# "workbench.editor.enablePreview": false  <-- 此行是关键，彻底禁用预览模式，让单击文件总是在新标签页打开
# "workbench.editor.showTabs": "multiple"  <-- 此行为辅助，确保多标签页模式总是开启（通常是默认值，但显式设置更保险）
RUN mkdir -p /root/.local/share/code-server/User \
    && echo '{ \
        "workbench.startupEditor": "readme", \
        "workbench.editor.enablePreview": false, \
        "github.copilot.chat.welcomeMessage": "never", \
        "workbench.editor.showTabs": "multiple" \
    }' > /root/.local/share/code-server/User/settings.json
# 修改结束

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
