#!/bin/sh
# SPDX-License-Identifier: MIT
# Assembles the Windows zip: the program, the DLLs it needs from the MSYS2
# (UCRT64) prefix and their licenses, the shaders and fonts, the notices.
#
#   package.sh SRC EXE DIST VERSION
#     SRC   source tree (shaders/, assets/, README.md, LICENSE)
#     EXE   shader-cube.exe
#     DIST  where shader-cube-VERSION-windows-x86_64.zip is written
#
# Environment: MINGW_PREFIX (the UCRT64 prefix: bin/ with the DLLs,
# share/licenses), OBJDUMP (default objdump), OWNERS (file -> package list of
# a cross sysroot; without it pacman says), PHYSX_DLL_DIR (optional: the MSVC
# build of shader-cube-physx.dll, PhysXGpu_64.dll and PhysX's license).
set -eu
SRC=$(cd "$1" && pwd)
EXE=$2
mkdir -p "$3"
DIST=$(cd "$3" && pwd)
VERSION=$4
OBJDUMP=${OBJDUMP:-objdump}
: "${MINGW_PREFIX:?set MINGW_PREFIX to the UCRT64 prefix (e.g. /ucrt64)}"

NAME=shader-cube-$VERSION-windows-x86_64
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP=$STAGE/shader-cube
mkdir -p "$APP/shaders" "$APP/assets" "$APP/licenses"

install -m 755 "$EXE" "$APP/shader-cube.exe"
cp -r "$SRC"/shaders/face* "$SRC/shaders/LICENSE.md" "$APP/shaders/"
cp -r "$SRC/assets/fonts" "$APP/assets/"
cp "$SRC/README.md" "$SRC/LICENSE" "$APP/"

# The DLLs, following imports from the program.  Windows' own and anything
# tied to the GPU driver (opengl32, vulkan-1) always come from the system.
imports() { "$OBJDUMP" -p "$1" | sed -n 's/^\s*DLL Name: //p'; }
system_dll() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    opengl32.dll | vulkan-1.dll | d3d*.dll | dxgi.dll | api-ms-win-* | ext-ms-* | ucrtbase.dll) return 0 ;;
    esac
    return 1
}
: > "$STAGE/bundled.txt"
todo="$APP/shader-cube.exe"
while [ -n "$todo" ]; do
    next=""
    for f in $todo; do
        for dll in $(imports "$f"); do
            system_dll "$dll" && continue
            [ -e "$APP/$dll" ] && continue
            path=$(find "$MINGW_PREFIX/bin" -maxdepth 1 -iname "$dll" | head -1)
            [ -n "$path" ] || continue # a Windows DLL
            cp "$path" "$APP/$dll"
            echo "$dll $path" >> "$STAGE/bundled.txt"
            next="$next $APP/$dll"
        done
    done
    todo=$next
done

if [ -n "${PHYSX_DLL_DIR:-}" ]; then
    for f in "$PHYSX_DLL_DIR"/*.dll; do
        [ -f "$f" ] && cp "$f" "$APP/"
    done
fi

# Notices: what is in here, and under which license.
NOTICES=$APP/THIRD-PARTY-NOTICES.md
row() { printf '| %s | %s | %s |\n' "$1" "$2" "$3" >> "$NOTICES"; }
owner() { # FILE -> MSYS2 package
    if [ -n "${OWNERS:-}" ]; then
        rel=${1#"${MINGW_PREFIX%/ucrt64}/"}
        awk -v f="$rel" '$2 == f { print $1; exit }' "$OWNERS"
    else
        pacman -Qqo "$1" 2>/dev/null || true
    fi
}
cat > "$NOTICES" <<EOF
# Third-party software in shader-cube for Windows

shader-cube's own code is MIT licensed (LICENSE). This package also contains
the components below. Each stays under its own license, whose full text is in
licenses/; none of them is relicensed under MIT. The DLLs come from MSYS2's
UCRT64 packages (https://packages.msys2.org); the GPU drivers and the Vulkan
loader come from the system.

| component | included as | license |
|---|---|---|
EOF
cp "$SRC/shaders/LICENSE.md" "$APP/licenses/face-shaders.md"
row "Face shaders by iq, noztol, whisky_shusuky, baopinsui, katiemil, dathor and FabriceNeyret2" \
    "data files, shaders/" "per shader, MIT or CC BY-NC-SA 3.0 (non-commercial): licenses/face-shaders.md"
cp "$SRC/assets/fonts/OFL.txt" "$APP/licenses/Atkinson Hyperlegible (OFL).txt"
row "Atkinson Hyperlegible font (Braille Institute)" "assets/fonts" \
    "SIL Open Font License 1.1: licenses/Atkinson Hyperlegible (OFL).txt"
cp "$SRC/third_party/volk/LICENSE.md" "$APP/licenses/volk.txt"
row "volk (Vulkan meta-loader)" "compiled into shader-cube.exe" "MIT: licenses/volk.txt"
sed -n '/This software is available under 2 licenses/,$p' "$SRC/third_party/stb/stb_truetype.h" | grep -v '^\*/' \
    > "$APP/licenses/stb_truetype.txt"
row "stb_truetype" "compiled into shader-cube.exe" "MIT or public domain: licenses/stb_truetype.txt"
while read -r dll path; do
    pkg=$(owner "$path")
    short=${pkg#mingw-w64-ucrt-x86_64-}
    dir=$MINGW_PREFIX/share/licenses/$short
    if [ -n "$pkg" ] && [ -d "$dir" ]; then
        mkdir -p "$APP/licenses/$short"
        cp -r "$dir"/. "$APP/licenses/$short/"
        row "$dll" "from the MSYS2 package $pkg" "licenses/$short/"
    else
        row "$dll" "from the MSYS2 package ${pkg:-?}" "see https://packages.msys2.org/packages/${pkg:-}"
    fi
done < "$STAGE/bundled.txt"
if [ -f "$APP/shader-cube-physx.dll" ]; then
    lic=${PHYSX_DLL_DIR:-}/LICENSE.md
    [ -f "$lic" ] && cp "$lic" "$APP/licenses/NVIDIA PhysX.txt"
    row "NVIDIA PhysX 5" "shader-cube-physx.dll, PhysXGpu_64.dll" "Apache-2.0: licenses/NVIDIA PhysX.txt"
fi
for f in "$APP"/cudart64_*.dll; do
    [ -f "$f" ] || continue
    row "$(basename "$f")" "NVIDIA CUDA runtime" "NVIDIA CUDA Toolkit EULA, redistributable under its Attachment A"
done
cat "$NOTICES"

rm -f "$DIST/$NAME.zip"
(cd "$STAGE" && zip -qr "$DIST/$NAME.zip" shader-cube)
echo "built $DIST/$NAME.zip ($(du -h "$DIST/$NAME.zip" | cut -f1))"
