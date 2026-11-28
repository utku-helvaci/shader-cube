#!/bin/sh
# SPDX-License-Identifier: MIT
# Windows build of shader-cube: dist/shader-cube-VERSION-windows-x86_64.zip
#
#   tools/windows/build.sh         in MSYS2's UCRT64 shell: a native build;
#                                  elsewhere (Linux): cross-compiled in docker
#   ... --test                     then start it: natively with Mesa's
#                                  software renderers, or under Wine (docker)
#
# Environment: VERSION (default: git describe, by v* tags), JOBS,
# PHYSX_DLL_DIR (shader-cube-physx.dll and PhysXGpu_64.dll, built with MSVC
# by tools/windows/physx.sh; without them the program runs without PhysX).
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$ROOT/tools/windows
# shellcheck source=versions.sh
. "$HERE/versions.sh"

TEST=0
for arg in "$@"; do
    case "$arg" in
    --test) TEST=1 ;;
    *) sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
    esac
done
VERSION=${VERSION:-$(git -C "$ROOT" describe --tags --match 'v[0-9]*' --always --dirty 2>/dev/null || date +%Y.%m.%d)}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}
mkdir -p "$ROOT/dist"
ZIP=$ROOT/dist/shader-cube-$VERSION-windows-x86_64.zip

if [ -n "${MSYSTEM:-}" ]; then
    # MSYS2: the UCRT64 toolchain and libraries (versions.sh: MSYS2_INSTALL).
    [ "$MSYSTEM" = UCRT64 ] || { echo "run this in MSYS2's UCRT64 shell" >&2; exit 1; }
    # A copy, so the Linux build's objects in build/ stay as they are.
    TREE=$ROOT/build/windows/tree
    rm -rf "$TREE"
    mkdir -p "$TREE"
    mkdir -p "$TREE/third_party"
    cp -r "$ROOT/src" "$ROOT/Makefile" "$TREE/"
    cp -r "$ROOT/third_party/volk" "$ROOT/third_party/stb" "$TREE/third_party/"
    make -C "$TREE" -j"$JOBS" TARGET=windows
    "$HERE/package.sh" "$ROOT" "$TREE/shader-cube.exe" "$ROOT/dist" "$VERSION"
else
    IMAGE=shader-cube-windows:$(cat "$HERE/Dockerfile" "$HERE/versions.sh" | sha256sum | cut -c1-16)
    if docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "using the existing build image $IMAGE"
    else
        docker build -t "$IMAGE" --build-arg BASE_IMAGE="$CROSS_IMAGE" --build-arg MSYS2_REPO="$MSYS2_REPO" \
            --build-arg MSYS2_PACKAGES="$MSYS2_PACKAGES" "$HERE"
    fi
    WORK=$ROOT/build/windows
    mkdir -p "$WORK"
    set --
    [ -n "${PHYSX_DLL_DIR:-}" ] && set -- -v "$(cd "$PHYSX_DLL_DIR" && pwd):/physx:ro" -e PHYSX_DLL_DIR=/physx
    docker run --rm --user "$(id -u):$(id -g)" -e VERSION="$VERSION" -e JOBS="$JOBS" "$@" \
        -v "$ROOT:/src:ro" -v "$WORK:/work" -v "$ROOT/dist:/dist" "$IMAGE" sh -euc '
        rm -rf /work/tree && mkdir -p /work/tree
        mkdir -p /work/tree/third_party
        cp -r /src/src /src/Makefile /work/tree/
        cp -r /src/third_party/volk /src/third_party/stb /work/tree/third_party/
        make -C /work/tree -j"$JOBS" TARGET=windows CC="$CC"
        /src/tools/windows/package.sh /src /work/tree/shader-cube.exe /dist "$VERSION"'
fi

if [ "$TEST" = 1 ]; then
    "$HERE/smoke_test.sh" "$ZIP"
fi
