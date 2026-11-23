#!/bin/sh
# SPDX-License-Identifier: MIT
# Fetch and build the NVIDIA PhysX SDK (static CPU libraries + the CUDA GPU
# module libPhysXGpu_64.so) into third_party/PhysX.  `make` picks it up
# automatically once third_party/PhysX/physx/lib/bin exists.
#
#   tools/build_physx.sh                   # GPU arch from nvidia-smi, else 86
#   PHYSX_CUDA_ARCH=89 tools/build_physx.sh
#   PHYSX_CUDA_ARCH=75,86,89,120 tools/build_physx.sh
#                                          # several GPU generations, lowest
#                                          # first (its PTX covers the rest)
#   PHYSX_GPU=0 tools/build_physx.sh       # CPU-only build (no CUDA needed)
#   PHYSX_DIR=/elsewhere tools/build_physx.sh   # build somewhere else
set -eu
cd "$(dirname "$0")/.."

TAG=110.3-omni-and-physx-5.9.1          # PhysX SDK 5.9.1
SRC=${PHYSX_DIR:-third_party/PhysX}
GPU=${PHYSX_GPU:-1}
JOBS=${JOBS:-$(nproc)}

if [ ! -d "$SRC/physx" ]; then
    mkdir -p "$(dirname "$SRC")"
    git clone --depth 1 --filter=blob:none --sparse --branch "$TAG" \
        https://github.com/NVIDIA-Omniverse/PhysX.git "$SRC"
    git -C "$SRC" sparse-checkout set physx
    # A plain source tree, not a nested repository: editors would otherwise
    # offer it for commits (and it holds the build output).
    rm -rf "$SRC/.git"
fi
P="$SRC/physx"

# Source patches.  Each is applied only while its target is still unpatched:
# rewriting a file would bump its mtime and recompile every CUDA kernel.
patch() { # FILE GREP-PATTERN SED-SCRIPT
    if grep -q -- "$2" "$1"; then sed -i "$3" "$1"; fi
}
# Newer compilers than PhysX is tested with raise new warnings; PhysX's own
# Linux readme recommends dropping -Werror in that case.
patch "$P/source/compiler/cmake/linux/CMakeLists.txt" '-Werror ' 's/ -Werror / /; s/-Wall -Werror /-Wall /'
patch "$P/source/compiler/cmakegpu/CMakeLists.txt" '-Werror=all-warnings' 's/-Werror=all-warnings //'
# libstdc++ >= 15 exports std::lerp into the global namespace in C++20, which
# clashes with the CUDA helper lerp(float, float, float).  It is only used
# inside this header, so give PhysX's version its own name.
patch "$P/source/gpucommon/include/cutil_math.h" '\blerp(' 's/\blerp(/pxg_lerp(/g'
# CUDA 13 turned cuCtxCreate into cuCtxCreate_v4, which takes a params struct.
CCM="$P/source/cudamanager/src/CudaContextManager.cpp"
if ! grep -q 'CUDA_VERSION >= 13000' "$CCM"; then
    sed -i 's|^\(\s*\)status = cuCtxCreate(&mCtx, (unsigned int)flags, mDevHandle);|#if CUDA_VERSION >= 13000\n\1status = cuCtxCreate(\&mCtx, NULL, (unsigned int)flags, mDevHandle);\n#else\n&\n#endif|' "$CCM"
fi

GPU_FLAGS="-DPX_GENERATE_GPU_PROJECTS=OFF"
if [ "$GPU" = 1 ]; then
    command -v nvcc >/dev/null 2>&1 || PATH="$PATH:/opt/cuda/bin:/usr/local/cuda/bin"
    ARCH=${PHYSX_CUDA_ARCH:-$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '. ')}
    ARCH=$(echo "${ARCH:-86}" | tr -d ' ')
    PTX=${ARCH%%,*}
    # Compile the CUDA kernels for the listed GPUs only (SASS for each, plus
    # PTX of the first so newer GPUs can JIT it) instead of every
    # architecture since Volta, which also avoids sm_70 that CUDA 13 dropped.
    GCM="$P/source/compiler/cmakegpu/CMakeLists.txt"
    if grep 'GENERATE_ARCH_CODE_LIST(SASS' "$GCM" | grep -qv "SASS \"$ARCH\" PTX \"$PTX\""; then
        sed -i "s/GENERATE_ARCH_CODE_LIST(SASS \"[0-9,]*\" PTX \"[0-9]*\")/GENERATE_ARCH_CODE_LIST(SASS \"$ARCH\" PTX \"$PTX\")/" "$GCM"
    fi
    GPU_FLAGS="-DPX_GENERATE_GPU_PROJECTS=ON -DCMAKE_CUDA_ARCHITECTURES=$PTX"
    echo "building PhysX with GPU support for sm_$ARCH (+ PTX $PTX)"
fi

GEN=""
command -v ninja >/dev/null 2>&1 && GEN="-G Ninja"

# shellcheck disable=SC2086
cmake -S "$P" -B "$SRC/build" $GEN \
    -DCMAKE_BUILD_TYPE=release \
    -DPX_GENERATE_STATIC_LIBRARIES=ON \
    -DPX_GENERATE_GPU_STATIC_LIBRARIES=OFF \
    -DPX_BUILDSNIPPETS=OFF -DPX_BUILDPVDRUNTIME=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    $GPU_FLAGS
cmake --build "$SRC/build" -j "$JOBS"
echo "PhysX libraries:"
find "$P/lib/bin" -name "*.a" -o -name "*.so" | sort
