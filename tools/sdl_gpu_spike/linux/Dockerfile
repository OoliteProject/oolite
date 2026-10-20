# Linux test environment for the SDL_GPU spike: Mesa's lavapipe (Vulkan) for
# SDL_GPU and llvmpipe (OpenGL compatibility profile, under Xvfb) for the GL
# reference renders. Both are software drivers, independent of Apple's stack.
#
#   docker build -t oolite-gpu-spike tools/sdl_gpu_spike/linux
#   docker run --rm -v $PWD:/src:ro -v <corpus dir>:/corpus oolite-gpu-spike \
#       /src/tools/sdl_gpu_spike/linux/run-tests.sh
FROM debian:trixie

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential meson ninja-build pkg-config python3 \
        libsdl3-dev glslang-dev libspirv-cross-c-shared-dev spirv-tools \
        libgl-dev mesa-vulkan-drivers libgl1-mesa-dri libglx-mesa0 libvulkan1 \
        xvfb xauth mesa-utils \
    && rm -rf /var/lib/apt/lists/*
