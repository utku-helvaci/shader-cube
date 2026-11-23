# SPDX-License-Identifier: MIT
# Build environment for the shader-cube AppImage.  Ubuntu 22.04 (glibc 2.35)
# so the AppImage runs on distributions from 2022 on.  Use it through
# tools/appimage/build.sh, which passes the pinned versions in versions.sh.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG CUDA_VERSION
ARG CMAKE_VERSION
ARG GLFW_VERSION
ARG GLFW_SHA256
ARG SHADERC_VERSION
ARG APPIMAGETOOL_URL
ARG APPIMAGETOOL_SHA256
ARG RUNTIME_URL
ARG RUNTIME_SHA256
ARG DEBIAN_FRONTEND=noninteractive

# GCC 12 is 22.04's newest and its libstdc++ is 22.04's, so the result needs
# no C++ runtime newer than the target system's own.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip file patchelf binutils pkg-config make \
        python3 python3-pip ninja-build gcc-12 g++-12 libc6-dev \
        libepoxy-dev libvulkan-dev libpng-dev zlib1g-dev \
        libwayland-dev libwayland-bin libxkbcommon-dev \
        libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libxext-dev \
        desktop-file-utils \
    && rm -rf /var/lib/apt/lists/*
ENV CC=gcc-12 CXX=g++-12 CUDAHOSTCXX=g++-12
RUN python3 -m pip install --no-cache-dir "cmake==${CMAKE_VERSION}"

# nvcc + CUDA runtime, for the PhysX GPU module.
RUN curl -fsSLo /tmp/keyring.deb \
        https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i /tmp/keyring.deb && rm /tmp/keyring.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends "cuda-nvcc-$(echo "${CUDA_VERSION}" | tr . -)" \
    && rm -rf /var/lib/apt/lists/*
ENV PATH=/usr/local/cuda-${CUDA_VERSION}/bin:$PATH CUDACXX=/usr/local/cuda-${CUDA_VERSION}/bin/nvcc

# GLFW, static: picks Wayland or X11 at runtime and loads their client
# libraries from the host.  (22.04's GLFW 3.3 is X11-only.)
RUN curl -fsSLo /tmp/glfw.zip "https://github.com/glfw/glfw/releases/download/${GLFW_VERSION}/glfw-${GLFW_VERSION}.zip" \
    && echo "${GLFW_SHA256}  /tmp/glfw.zip" | sha256sum -c - \
    && unzip -q /tmp/glfw.zip -d /tmp \
    && cmake -S "/tmp/glfw-${GLFW_VERSION}" -B /tmp/glfw-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/deps -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF \
        -DGLFW_BUILD_X11=ON -DGLFW_BUILD_WAYLAND=ON \
    && cmake --build /tmp/glfw-build && cmake --install /tmp/glfw-build \
    && install -D -m 644 "/tmp/glfw-${GLFW_VERSION}/LICENSE.md" "/opt/deps/share/licenses/GLFW ${GLFW_VERSION}.txt" \
    && rm -rf /tmp/glfw*

# shaderc + glslang + SPIRV-Tools as one static library.  The license texts
# of everything linked statically are kept in /opt/deps/share/licenses.
RUN git clone --depth 1 --branch "${SHADERC_VERSION}" https://github.com/google/shaderc /tmp/shaderc \
    && cd /tmp/shaderc && ./utils/git-sync-deps \
    && cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
        -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON -DENABLE_GLSLANG_BINARIES=OFF -DGLSLANG_TESTS=OFF \
    && cmake --build build --target shaderc_combined \
    && install -D -m 644 build/libshaderc/libshaderc_combined.a /opt/deps/lib/libshaderc_combined.a \
    && cp -r libshaderc/include/shaderc /opt/deps/include/ \
    && L=/opt/deps/share/licenses && v() { git -C "$1" describe --tags --always; } \
    && install -m 644 LICENSE "$L/shaderc ${SHADERC_VERSION}.txt" \
    && install -m 644 third_party/glslang/LICENSE.txt "$L/glslang $(v third_party/glslang).txt" \
    && install -m 644 third_party/spirv-tools/LICENSE "$L/SPIRV-Tools $(v third_party/spirv-tools).txt" \
    && install -m 644 third_party/spirv-headers/LICENSE "$L/SPIRV-Headers $(v third_party/spirv-headers).txt" \
    && printf '%s\n' 'prefix=/opt/deps' 'Name: shaderc_combined' 'Description: shaderc, glslang and SPIRV-Tools (static)' \
        "Version: ${SHADERC_VERSION}" 'Cflags: -I${prefix}/include' 'Libs: -L${prefix}/lib -lshaderc_combined' \
        > /opt/deps/lib/pkgconfig/shaderc_combined.pc \
    && rm -rf /tmp/shaderc
ENV PKG_CONFIG_PATH=/opt/deps/lib/pkgconfig \
    SHADER_CUBE_PKGS="glfw3 epoxy vulkan shaderc_combined libpng"

# appimagetool (unpacked: no FUSE in containers) and the static runtime.
RUN curl -fsSLo /tmp/appimagetool "${APPIMAGETOOL_URL}" \
    && echo "${APPIMAGETOOL_SHA256}  /tmp/appimagetool" | sha256sum -c - \
    && chmod +x /tmp/appimagetool && cd /opt && /tmp/appimagetool --appimage-extract >/dev/null \
    && mv /opt/squashfs-root /opt/appimagetool && chmod -R a+rX /opt/appimagetool && rm /tmp/appimagetool \
    && curl -fsSLo /opt/appimage-runtime "${RUNTIME_URL}" \
    && echo "${RUNTIME_SHA256}  /opt/appimage-runtime" | sha256sum -c - && chmod 644 /opt/appimage-runtime
ENV APPIMAGETOOL=/opt/appimagetool/AppRun APPIMAGE_RUNTIME=/opt/appimage-runtime
