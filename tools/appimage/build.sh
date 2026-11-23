#!/bin/sh
# SPDX-License-Identifier: MIT
# AppImage pipeline for shader-cube.  Writes dist/shader-cube-VERSION-x86_64.AppImage.
#
#   tools/appimage/build.sh           portable build in an Ubuntu 22.04 container
#                                     (needs docker; runs on glibc 2.35+ systems)
#   tools/appimage/build.sh --host    quick build with this machine's toolchain;
#                                     runs only on systems as new as this one
#   ... --test                        then run smoke_test.sh on the result (a
#                                     clean Ubuntu 22.04, software rendering)
#
# Environment: VERSION (default: git describe, else the date), JOBS,
# PHYSX_CUDA_ARCH (default for the container build: see versions.sh),
# PHYSX_GPU=0 for CPU-only PhysX.
#
# The first container run builds the image (~10 min) and PhysX for several
# GPU generations (much longer); both are cached for later runs, in docker
# and build/appimage/.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$ROOT/tools/appimage
# shellcheck source=versions.sh
. "$HERE/versions.sh"

MODE=container TEST=0
for arg in "$@"; do
    case "$arg" in
    --host) MODE=host ;;
    --test) TEST=1 ;;
    *) sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
    esac
done

VERSION=${VERSION:-$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || date +%Y.%m.%d)}
export VERSION
mkdir -p "$ROOT/dist"

if [ "$MODE" = container ]; then
    # Tagged with a hash of everything the image is built from, so an
    # existing image (an earlier build, or one restored by CI) is reused as is.
    IMAGE=shader-cube-appimage:$(cat "$HERE/Dockerfile" "$HERE/versions.sh" | sha256sum | cut -c1-16)
    if docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "using the existing build image $IMAGE"
    else
        docker build -t "$IMAGE" --build-arg BASE_IMAGE="$BASE_IMAGE" \
            --build-arg CUDA_VERSION="$CUDA_VERSION" --build-arg CMAKE_VERSION="$CMAKE_VERSION" \
            --build-arg GLFW_VERSION="$GLFW_VERSION" --build-arg GLFW_SHA256="$GLFW_SHA256" \
            --build-arg SHADERC_VERSION="$SHADERC_VERSION" \
            --build-arg APPIMAGETOOL_URL="$APPIMAGETOOL_URL" --build-arg APPIMAGETOOL_SHA256="$APPIMAGETOOL_SHA256" \
            --build-arg RUNTIME_URL="$RUNTIME_URL" --build-arg RUNTIME_SHA256="$RUNTIME_SHA256" \
            "$HERE"
    fi
    WORK=$ROOT/build/appimage
    mkdir -p "$WORK/home"
    docker run --rm --user "$(id -u):$(id -g)" \
        -e HOME=/work/home -e VERSION -e JOBS -e PHYSX_GPU -e RUNTIME_URL="$RUNTIME_URL" \
        -e PHYSX_CUDA_ARCH="${PHYSX_CUDA_ARCH:-$PORTABLE_CUDA_ARCH}" \
        -v "$ROOT:/src:ro" -v "$WORK:/work" -v "$ROOT/dist:/dist" \
        "$IMAGE" /src/tools/appimage/bundle.sh /src /work /dist
else
    # The same pinned appimagetool and runtime as the container uses.
    TOOLS=$ROOT/build/appimage-host/tools
    mkdir -p "$TOOLS"
    fetch() { # URL SHA256 FILE
        if [ -f "$3" ] && echo "$2  $3" | sha256sum -c --status -; then return; fi
        curl -fsSL -o "$3.part" "$1"
        echo "$2  $3.part" | sha256sum -c --status - || { echo "checksum mismatch: $1" >&2; exit 1; }
        mv "$3.part" "$3"
    }
    fetch "$APPIMAGETOOL_URL" "$APPIMAGETOOL_SHA256" "$TOOLS/appimagetool"
    fetch "$RUNTIME_URL" "$RUNTIME_SHA256" "$TOOLS/runtime"
    chmod +x "$TOOLS/appimagetool"
    # Reuses the regular third_party/PhysX build (this machine's GPU only).
    PHYSX_DIR=${PHYSX_DIR:-$ROOT/third_party/PhysX} RUNTIME_URL="$RUNTIME_URL" \
    APPIMAGETOOL="$TOOLS/appimagetool" APPIMAGE_RUNTIME="$TOOLS/runtime" APPIMAGE_EXTRACT_AND_RUN=1 \
        "$HERE/bundle.sh" "$ROOT" "$ROOT/build/appimage-host" "$ROOT/dist"
fi

if [ "$TEST" = 1 ]; then
    "$HERE/smoke_test.sh" "$ROOT/dist/shader-cube-$VERSION-$(uname -m).AppImage"
fi
