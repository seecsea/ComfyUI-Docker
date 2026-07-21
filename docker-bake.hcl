variable "DOCKERHUB_REPO_NAME" {
    default = "seecsea/comfyui"
}

variable "PYTHON_VERSION" {
    default = "3.12"
}
variable "TORCH_VERSION" {
    default = "2.9.1"
}
variable "TORCH_VISION_VERSION" {
    default = "0.24.1"
}
variable "TORCH_AUDIO_VERSION" {
    default = "2.9.1"
}
variable "COMFYUI_VERSION" {
    default = "0.28.2"
}
variable "CODESERVER_VERSION" {
    default = "4.128.0"
}

variable "EXTRA_TAG" {
    default = ""
}

function "tag" {
    params = [tag, cuda]
    result = ["${DOCKERHUB_REPO_NAME}:${tag}-torch${TORCH_VERSION}-${cuda}-py${PYTHON_VERSION}-${COMFYUI_VERSION}"]
}

target "_common" {
    dockerfile = "Dockerfile"
    context = "."
    args = {
        PYTHON_VERSION       = PYTHON_VERSION
        TORCH_VERSION        = TORCH_VERSION
        TORCH_VISION_VERSION = TORCH_VISION_VERSION
        TORCH_AUDIO_VERSION  = TORCH_AUDIO_VERSION
        COMFYUI_VERSION      = COMFYUI_VERSION
        CODESERVER_VERSION   = CODESERVER_VERSION
    }
}

target "_cu126" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE         = "nvidia/cuda:12.6.3-cudnn-devel-ubuntu24.04"
        CUDA_VERSION       = "cu126"
    }
}

target "_cu128" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE         = "nvidia/cuda:12.8.2-cudnn-devel-ubuntu24.04"
        CUDA_VERSION       = "cu128"
    }
}

target "_cu130" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE         = "nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04"
        CUDA_VERSION       = "cu130"
    }
}

target "_cu131" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE         = "nvidia/cuda:13.1.2-cudnn-devel-ubuntu24.04"
        CUDA_VERSION       = "cu131"
    }
}

target "_cu132" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE         = "nvidia/cuda:13.2.1-cudnn-devel-ubuntu24.04"
        CUDA_VERSION       = "cu132"
    }
}

target "_no_custom_nodes" {
    args = {
        SKIP_CUSTOM_NODES = "1"
    }
}

target "base-12-6" {
    inherits = ["_cu126"]
    tags = tag("base", "cu126")
}

target "base-12-8" {
    inherits = ["_cu128"]
    tags = tag("base", "cu128")
}

target "base-13-0" {
    inherits = ["_cu130"]
    tags = tag("base", "cu130")
}

target "base-13-1" {
    inherits = ["_cu131"]
    tags = tag("base", "cu131")
}

target "base-13-2" {
    inherits = ["_cu132"]
    tags = tag("base", "cu132")
}

target "slim-12-6" {
    inherits = ["_cu126", "_no_custom_nodes"]
    tags = tag("slim", "cu126")
}

target "slim-12-8" {
    inherits = ["_cu128", "_no_custom_nodes"]
    tags = tag("slim", "cu128")
}

target "slim-13-0" {
    inherits = ["_cu130", "_no_custom_nodes"]
    tags = tag("slim", "cu130")
}

target "slim-13-1" {
    inherits = ["_cu131", "_no_custom_nodes"]
    tags = tag("slim", "cu131")
}

target "slim-13-2" {
    inherits = ["_cu132", "_no_custom_nodes"]
    tags = tag("slim", "cu132")
}
