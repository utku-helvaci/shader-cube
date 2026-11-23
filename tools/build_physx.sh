#!/bin/sh
# SPDX-License-Identifier: MIT
# Build the NVIDIA PhysX SDK (static CPU libraries + the CUDA GPU module
# libPhysXGpu_64.so) from the third_party/PhysX git submodule into
# build/PhysX.  `make` picks it up automatically once
# build/PhysX/physx/lib/bin exists.
#
# The submodule is never modified: its physx/ directory is copied into the
# build directory, patched and built there.  The copy is replaced when the
# submodule is moved to another commit or its files are edited.
#
#   tools/build_physx.sh                   # GPU arch from nvidia-smi, else 86
#   PHYSX_CUDA_ARCH=89 tools/build_physx.sh
#   PHYSX_CUDA_ARCH=75,86,89,120 tools/build_physx.sh
#                                          # several GPU generations, lowest
#                                          # first (its PTX covers the rest)
#   PHYSX_GPU=0 tools/build_physx.sh       # CPU-only build (no CUDA needed)
#   PHYSX_DIR=/elsewhere tools/build_physx.sh   # build somewhere else
#   PHYSX_SRC=/a/PhysX/clone tools/build_physx.sh   # other PhysX sources
set -eu
cd "$(dirname "$0")/.."

SUBMODULE=third_party/PhysX             # NVIDIA-Omniverse/PhysX, PhysX SDK 5.9.1
SRC=${PHYSX_SRC:-$SUBMODULE}
OUT=${PHYSX_DIR:-build/PhysX}
GPU=${PHYSX_GPU:-1}
JOBS=${JOBS:-$(nproc)}

if [ ! -f "$SRC/physx/version.txt" ]; then
    if [ "$SRC" = "$SUBMODULE" ]; then
        # Only the commit itself (.gitmodules: shallow), and without the Git
        # LFS files of omni/, which isn't used.
        GIT_LFS_SKIP_SMUDGE=1 git submodule update --init --depth 1 -- "$SUBMODULE"
    else
        echo "error: no PhysX sources in $SRC" >&2
        echo "(in a shader-cube clone: git submodule update --init --depth 1 $SUBMODULE)" >&2
        exit 1
    fi
fi

# Which sources the build directory holds: the commit plus any local edits,
# or for a plain source tree, its version.
source_id() {
    if [ "$(git -C "$SRC" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$SRC" && pwd -P)" ]; then
        echo "commit $(git -C "$SRC" rev-parse HEAD)"
        git -C "$SRC" diff HEAD -- physx
    else
        echo "version $(cat "$SRC/physx/version.txt")"
    fi
}
ID=$(source_id | sha256sum | cut -d' ' -f1)
P="$OUT/physx"
if [ "$(cat "$OUT/source-id" 2>/dev/null)" != "$ID" ]; then
    echo "copying the PhysX sources from $SRC to $OUT"
    rm -rf "$P" "$OUT/build" "$OUT/source-id"
    mkdir -p "$OUT"
    cp -a "$SRC/physx" "$OUT/"
    echo "$ID" > "$OUT/source-id"
fi

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
cmake -S "$P" -B "$OUT/build" $GEN \
    -DCMAKE_BUILD_TYPE=release \
    -DPX_GENERATE_STATIC_LIBRARIES=ON \
    -DPX_GENERATE_GPU_STATIC_LIBRARIES=OFF \
    -DPX_BUILDSNIPPETS=OFF -DPX_BUILDPVDRUNTIME=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    $GPU_FLAGS
cmake --build "$OUT/build" -j "$JOBS"
echo "PhysX libraries:"
find "$P/lib/bin" -name "*.a" -o -name "*.so" | sort
