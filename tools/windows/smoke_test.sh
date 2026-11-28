#!/bin/sh
# SPDX-License-Identifier: MIT
# Starts the Windows build with software rendering and has it draw a small
# frame of each scene through Vulkan and OpenGL:
#   in MSYS2 (on Windows): Mesa's lavapipe and llvmpipe from MSYS2's mesa
#     package, put next to a copy of the program (not into the zip)
#   on Linux: under Wine in a clean Ubuntu container, with Mesa underneath
#
#   tools/windows/smoke_test.sh dist/shader-cube-VERSION-windows-x86_64.zip [OUTDIR]
set -eu
[ $# -ge 1 ] || { sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
ZIP=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
OUT=${2:-$(dirname "$ZIP")/smoke-test-windows}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
# shellcheck source=versions.sh
. "$(dirname "$0")/versions.sh"

# What to draw: name, then the arguments.
RUNS="vulkan-cube --api vulkan
gl-cube --api gl
vulkan-galton --api vulkan --scene galton --physics compute --balls 300
gl-galton --api gl --scene galton --physics compute --balls 300
vulkan-menu --api vulkan --scene galton --physics compute --balls 300 --menu"
ARGS="--res 64 --size 320x180 --at 0.5"

if [ -n "${MSYSTEM:-}" ]; then
    DIR=$(mktemp -d)
    trap 'rm -rf "$DIR"' EXIT
    unzip -q "$ZIP" -d "$DIR"
    APP=$DIR/shader-cube
    # Mesa: opengl32.dll beside the program wins over the system's; the
    # Vulkan loader finds lavapipe through VK_DRIVER_FILES.
    cp "$MINGW_PREFIX/bin/opengl32.dll" "$MINGW_PREFIX"/bin/libgallium_wgl.dll "$APP/"
    cp "$MINGW_PREFIX/bin/vulkan-1.dll" "$APP/"
    for dll in $(ldd "$MINGW_PREFIX/bin/libgallium_wgl.dll" "$MINGW_PREFIX/bin/vulkan_lvp.dll" |
                 awk '$3 ~ /^\/ucrt64\// { print $3 }' | sort -u); do
        cp -n "$dll" "$APP/" 2>/dev/null || true
    done
    VK_DRIVER_FILES=$(cygpath -w "$MINGW_PREFIX/share/vulkan/icd.d/lvp_icd.x86_64.json")
    export VK_DRIVER_FILES
    echo "$RUNS" | while read -r name args; do
        echo "--- $name"
        # shellcheck disable=SC2086
        (cd "$APP" && ./shader-cube.exe $args $ARGS --screenshot "$(cygpath -w "$OUT/$name.png")")
    done
else
    docker run --rm -v "$ZIP:/app.zip:ro" -v "$OUT:/out" -e RUNS="$RUNS" -e ARGS="$ARGS" "$CROSS_IMAGE" sh -euc '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends wine64 xvfb xauth unzip \
            mesa-vulkan-drivers libvulkan1 libgl1-mesa-dri libgl1 libglx-mesa0 >/dev/null
        unzip -q /app.zip -d /tmp
        cd /tmp/shader-cube
        export WINEPREFIX=/tmp/wine WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
        WINE=$(command -v wine64 || command -v wine || echo /usr/lib/wine/wine64)
        xvfb-run -a "$WINE" wineboot -i >/dev/null 2>&1 || true
        echo "$RUNS" | while read -r name args; do
            echo "--- $name"
            xvfb-run -a "$WINE" shader-cube.exe $args $ARGS --screenshot "Z:\\out\\$name.png"
        done
        chown -R "$(stat -c %u:%g /out)" /out'
fi
echo "$RUNS" | while read -r name args; do
    [ -s "$OUT/$name.png" ] || { echo "smoke test FAILED: no $name.png" >&2; exit 1; }
done
echo "smoke test passed: $OUT"
