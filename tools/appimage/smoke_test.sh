#!/bin/sh
# SPDX-License-Identifier: MIT
# Starts an AppImage on a clean Ubuntu 22.04 (the pipeline's baseline) with
# no GPU: Mesa's software renderers draw one small frame through each API.
# Proves the bundle is complete and runs on the oldest supported system.
#
#   tools/appimage/smoke_test.sh dist/shader-cube-VERSION-x86_64.AppImage [OUTDIR]
set -eu
[ $# -ge 1 ] || { sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
APPIMAGE=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
OUT=${2:-$(dirname "$APPIMAGE")/smoke-test}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
# shellcheck source=versions.sh
. "$(dirname "$0")/versions.sh"

docker run --rm -v "$APPIMAGE:/app/shader-cube.AppImage:ro" -v "$OUT:/out" "$BASE_IMAGE" sh -euc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        mesa-vulkan-drivers libgl1-mesa-dri libgl1 libglx-mesa0 libegl1 libegl-mesa0 libgles2 xvfb xauth >/dev/null
    cd /tmp
    export XDG_RUNTIME_DIR=/tmp/xdg
    mkdir -m 700 -p "$XDG_RUNTIME_DIR"
    app="/app/shader-cube.AppImage --appimage-extract-and-run --res 64 --size 320x180 --at 0.25"
    echo "--- Vulkan (lavapipe, no window system)"
    $app --api vulkan --screenshot /out/vulkan.png
    echo "--- OpenGL ES (llvmpipe, Xvfb)"
    xvfb-run -a $app --api gles --screenshot /out/gles.png
    echo "--- OpenGL 4.3 (llvmpipe, Xvfb)"
    xvfb-run -a $app --api gl --screenshot /out/gl.png
    chown -R "$(stat -c %u:%g /out)" /out
'
for f in vulkan gles gl; do
    [ -s "$OUT/$f.png" ] || { echo "smoke test FAILED: no $f.png" >&2; exit 1; }
done
echo "smoke test passed: $OUT/{vulkan,gles,gl}.png"
