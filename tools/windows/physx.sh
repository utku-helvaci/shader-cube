#!/bin/sh
# SPDX-License-Identifier: MIT
# Windows: builds NVIDIA PhysX with MSVC (its GPU part with CUDA) and, from
# src/physics_physx.cpp, the shader-cube-physx.dll the program loads.  Run it
# in Git Bash (or MSYS2's msys shell) started from an MSVC x64 environment
# (a "x64 Native Tools" prompt, or vcvars64.bat):
#
#   tools/windows/physx.sh OUTDIR    -> shader-cube-physx.dll, PhysXGpu_64.dll, LICENSE.md
#
# Environment: PHYSX_GPU=0 (CPU only, no CUDA), PHYSX_CUDA_ARCH (default: the
# AppImage's list), CUDA_ROOT (default: build/windows/cuda, unpacked from
# NVIDIA's archives in versions.sh), PHYSX_DIR (default build/windows/PhysX).
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$ROOT/tools/windows
# shellcheck source=versions.sh
. "$HERE/versions.sh"
# shellcheck source=../appimage/versions.sh
. "$ROOT/tools/appimage/versions.sh" # PORTABLE_CUDA_ARCH
[ $# = 1 ] || { sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
command -v cl >/dev/null || { echo "cl.exe not found: start from an MSVC x64 environment" >&2; exit 1; }
win() { cygpath -m "$1"; } # C:/... paths for the MSVC tools
# Git Bash would rewrite /-style arguments into paths: the tools get -options instead
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

GPU=${PHYSX_GPU:-1}
if [ "$GPU" = 1 ]; then
    CUDA_ROOT=${CUDA_ROOT:-$ROOT/build/windows/cuda}
    if [ ! -f "$CUDA_ROOT/bin/nvcc.exe" ]; then
        echo "unpacking CUDA into $CUDA_ROOT"
        TMP=$(mktemp -d)
        echo "$CUDA_PACKAGES" | while read -r rel sha; do
            [ -n "$rel" ] || continue
            f=$TMP/$(basename "$rel")
            curl -fsSLo "$f" "$CUDA_REDIST/$rel"
            echo "$sha  $f" | sha256sum -c --status - || { echo "checksum mismatch: $rel" >&2; exit 1; }
            if command -v unzip >/dev/null; then unzip -q "$f" -d "$TMP/x"
            else powershell -NoProfile -Command "Expand-Archive -Force '$(win "$f")' '$(win "$TMP/x")'"; fi
        done
        mkdir -p "$CUDA_ROOT"
        for d in "$TMP"/x/*/; do cp -r "$d". "$CUDA_ROOT/"; done
        rm -rf "$TMP"
    fi
    CUDACXX=$(win "$CUDA_ROOT/bin/nvcc.exe")
    CUDAToolkit_ROOT=$(win "$CUDA_ROOT")
    PATH=$CUDA_ROOT/bin:$PATH
    export CUDACXX CUDAToolkit_ROOT PATH
fi

# PhysX's static libraries against the static C runtime (/MT), and
# PhysXGpu_64.dll.  CUDA may not know the newest Visual Studio yet.
PHYSX_DIR=${PHYSX_DIR:-$ROOT/build/windows/PhysX}
PHYSX_CUDA_ARCH=${PHYSX_CUDA_ARCH:-$PORTABLE_CUDA_ARCH}
PHYSX_CMAKE_ARGS="-DNV_USE_STATIC_WINCRT=ON -DNV_USE_DEBUG_WINCRT=OFF -DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler"
export PHYSX_DIR PHYSX_CUDA_ARCH PHYSX_CMAKE_ARGS PHYSX_GPU="$GPU"
"$ROOT/tools/build_physx.sh"

LIB=$(find "$PHYSX_DIR/physx" -name PhysX_static_64.lib | head -1)
[ -n "$LIB" ] || { echo "PhysX_static_64.lib not found under $PHYSX_DIR" >&2; exit 1; }
LIBDIR=$(dirname "$LIB")
echo "PhysX libraries in $LIBDIR"

# shader-cube-physx.dll: physics.h's functions, exported, PhysX linked in.
# link.exe by its full path: Git Bash has a link command of its own.
OBJ=$PHYSX_DIR/physics_physx.obj
cl -nologo -c -O2 -MT -EHsc -std:c++17 -DNDEBUG -DPHYS_DLL_EXPORT -DPX_PHYSX_STATIC_LIB \
    -I"$(win "$PHYSX_DIR/physx/include")" "$(win "$ROOT/src/physics_physx.cpp")" -Fo"$(win "$OBJ")"
LINK=$(dirname "$(command -v cl)")/link.exe
"$LINK" -nologo -DLL -OUT:"$(win "$OUT/shader-cube-physx.dll")" "$(win "$OBJ")" -LIBPATH:"$(win "$LIBDIR")" \
    PhysXExtensions_static_64.lib PhysX_static_64.lib PhysXPvdSDK_static_64.lib PhysXCommon_static_64.lib \
    PhysXFoundation_static_64.lib ws2_32.lib
rm -f "$OUT/shader-cube-physx.lib" "$OUT/shader-cube-physx.exp"
if [ "$GPU" = 1 ]; then
    GPUDLL=$(find "$PHYSX_DIR/physx" -name PhysXGpu_64.dll | head -1)
    [ -n "$GPUDLL" ] || { echo "PhysXGpu_64.dll was not built" >&2; exit 1; }
    cp "$GPUDLL" "$OUT/"
    # The CUDA runtime, if PhysXGpu_64.dll links it dynamically.
    for dll in $(dumpbin -nologo -dependents "$(win "$GPUDLL")" | tr -d '\r' | grep -io 'cudart64_[0-9]*\.dll' | sort -u); do
        cp "$CUDA_ROOT/bin/$dll" "$OUT/"
    done
fi
cp "$PHYSX_DIR/physx/LICENSE.md" "$OUT/"
ls -l "$OUT"
