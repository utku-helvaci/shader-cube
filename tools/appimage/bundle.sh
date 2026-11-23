#!/bin/sh
# SPDX-License-Identifier: MIT
# Builds shader-cube and packs it as an AppImage.  Run by build.sh, inside
# the pipeline's container or (--host) directly.
#
#   bundle.sh SRC WORK DIST
#     SRC   source tree (only read)
#     WORK  scratch space and caches (the PhysX build is kept here)
#     DIST  where the .AppImage is written
#
# Environment: VERSION, JOBS, PHYSX_SRC (PhysX sources, default the
# SRC/third_party/PhysX submodule), PHYSX_DIR (its build, default WORK/PhysX),
# PHYSX_CUDA_ARCH,
# PHYSX_GPU, SHADER_CUBE_PKGS (pkg-config packages to link), APPIMAGETOOL,
# APPIMAGE_RUNTIME, RUNTIME_URL (for its notice), STATIC_LICENSES (license
# texts of statically linked libraries, default /opt/deps/share/licenses).
set -eu
SRC=$(cd "$1" && pwd)
mkdir -p "$2" "$3"
WORK=$(cd "$2" && pwd)
DIST=$(cd "$3" && pwd)
VERSION=${VERSION:-dev}
JOBS=${JOBS:-$(nproc)}
ARCH=$(uname -m)
PHYSX_SRC="${PHYSX_SRC:-$SRC/third_party/PhysX}"
PHYSX_DIR="${PHYSX_DIR:-$WORK/PhysX}"
export PHYSX_SRC PHYSX_DIR

step() { printf '\n==> %s\n' "$*"; }

step "copying the source tree"
TREE=$WORK/tree
rm -rf "$TREE"
mkdir -p "$TREE"
cp -r "$SRC/src" "$SRC/shaders" "$SRC/tools" "$SRC/Makefile" "$TREE/"

step "PhysX ($PHYSX_DIR)"
"$TREE/tools/build_physx.sh"

step "shader-cube"
set -- PHYSX_ROOT="$PHYSX_DIR/physx"
[ -n "${SHADER_CUBE_PKGS:-}" ] && set -- "$@" PKGS="$SHADER_CUBE_PKGS"
make -C "$TREE" -j"$JOBS" "$@"

step "AppDir"
APPDIR=$WORK/AppDir
SHARE=$APPDIR/usr/share
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$SHARE/shader-cube" "$SHARE/applications" \
         "$SHARE/icons/hicolor/scalable/apps" "$SHARE/icons/hicolor/256x256/apps" "$SHARE/doc/shader-cube"
install -m 755 "$TREE/shader-cube" "$APPDIR/usr/bin/"
strip "$APPDIR/usr/bin/shader-cube"
mkdir -p "$SHARE/shader-cube/shaders"
cp -r "$TREE"/shaders/face* "$TREE/shaders/LICENSE.md" "$SHARE/shader-cube/shaders/"
GPULIB=$PHYSX_DIR/physx/lib/bin/linux.x86_64/release/libPhysXGpu_64.so
[ -f "$GPULIB" ] && install -m 755 "$GPULIB" "$APPDIR/usr/lib/"
install -m 644 "$SRC/tools/appimage/shader-cube.desktop" "$SHARE/applications/"
install -m 644 "$SRC/tools/appimage/shader-cube.svg" "$SHARE/icons/hicolor/scalable/apps/"
install -m 644 "$SRC/tools/appimage/shader-cube.png" "$SHARE/icons/hicolor/256x256/apps/"
install -m 644 "$SRC/README.md" "$SRC/LICENSE" "$SHARE/doc/shader-cube/"
ln -s usr/share/applications/shader-cube.desktop "$APPDIR/shader-cube.desktop"
ln -s usr/share/icons/hicolor/256x256/apps/shader-cube.png "$APPDIR/shader-cube.png"
ln -s shader-cube.png "$APPDIR/.DirIcon"
ln -s usr/bin/shader-cube "$APPDIR/AppRun"
if command -v desktop-file-validate >/dev/null; then desktop-file-validate "$SHARE/applications/shader-cube.desktop"; fi

step "bundling libraries"
# Supplied by every target system, or tied to its GPU driver or display
# server: always taken from the host, never bundled.  (libstdc++/libgcc_s:
# the build baseline's are the oldest any supported system has.)
host_only() {
    case "$1" in
    linux-vdso.so* | ld-linux* | libc.so* | libm.so* | libdl.so* | libpthread.so* | librt.so* | \
        libresolv.so* | libutil.so* | libmvec.so*) return 0 ;;
    libstdc++.so* | libgcc_s.so*) return 0 ;;
    libcuda.so* | libnvidia-* | libGL.so* | libGLX* | libEGL* | libGLES* | libOpenGL* | libGLdispatch* | \
        libdrm* | libgbm*) return 0 ;;
    libX* | libxcb* | libwayland-* | libxkbcommon* | libdecor*) return 0 ;;
    esac
    return 1
}
: > "$WORK/bundled.txt"
added=1
while [ "$added" = 1 ]; do
    added=0
    for elf in "$APPDIR/usr/bin/shader-cube" "$APPDIR"/usr/lib/*.so*; do
        ldd "$elf" | awk '$2 == "=>" { print $1, $3 }' > "$WORK/deps.txt"
        while read -r name path; do
            name=${name##*/} # the loader is listed by path
            host_only "$name" && continue
            [ -e "$APPDIR/usr/lib/$name" ] && continue
            if [ "$path" = not ]; then
                echo "error: $(basename "$elf") needs $name, which is not installed" >&2
                exit 1
            fi
            cp -L "$path" "$APPDIR/usr/lib/$name"
            chmod 755 "$APPDIR/usr/lib/$name"
            echo "$name  ($path)" >> "$WORK/bundled.txt"
            added=1
        done < "$WORK/deps.txt"
    done
done
sort "$WORK/bundled.txt" | tee "$SHARE/doc/shader-cube/bundled-libraries.txt"
# shellcheck disable=SC2016
patchelf --set-rpath '$ORIGIN/../lib' "$APPDIR/usr/bin/shader-cube"
for lib in "$APPDIR"/usr/lib/*.so*; do
    # shellcheck disable=SC2016
    patchelf --set-rpath '$ORIGIN' "$lib"
done

step "license notices"
DOC=$SHARE/doc/shader-cube
LIC=$DOC/licenses
NOTICES=$DOC/THIRD-PARTY-NOTICES.md
mkdir -p "$LIC"
row() { printf '| %s | %s | %s |\n' "$1" "$2" "$3" >> "$NOTICES"; }
# License text of the distribution package that installed a library.
pkg_license() { # LIBRARY OUT -> prints the package name
    real=$(readlink -f "$1")
    if command -v dpkg-query >/dev/null 2>&1; then
        # (a pattern with a / must match a path exactly; a glob searches)
        pkg=$(dpkg-query -S "*/${real##*/}" 2>/dev/null | head -1 | cut -d: -f1)
        if [ -n "$pkg" ] && [ -f "/usr/share/doc/$pkg/copyright" ]; then
            cp "/usr/share/doc/$pkg/copyright" "$2"
            # Debian refers to common licenses instead of repeating them
            grep -o '/usr/share/common-licenses/[A-Za-z0-9.+-]*' "$2" | sed 's/\.$//' | sort -u > "$2.refs"
            while read -r ref; do
                if [ -f "$ref" ]; then printf '\n==> %s\n\n' "$ref"; cat "$ref"; fi
            done < "$2.refs" >> "$2"
            rm -f "$2.refs"
            echo "$pkg"
            return 0
        fi
    fi
    if command -v pacman >/dev/null 2>&1 && pkg=$(pacman -Qqo "$real" 2>/dev/null); then
        if [ -d "/usr/share/licenses/$pkg" ]; then
            for f in "/usr/share/licenses/$pkg"/*; do printf '==> %s\n\n' "${f##*/}"; cat "$f"; echo; done > "$2"
        else # packages under a common license only name it: add the SPDX text
            ids=$(pacman -Qi "$pkg" | sed -n 's/^Licenses *: //p')
            { echo "License: $ids"; for id in $ids; do
                [ -f "/usr/share/licenses/spdx/$id.txt" ] && { echo; cat "/usr/share/licenses/spdx/$id.txt"; }
            done; } > "$2"
        fi
        echo "$pkg"
        return 0
    fi
    return 1
}
cat > "$NOTICES" <<EOF
# Third-party software in the shader-cube AppImage

shader-cube's own code is MIT licensed (LICENSE). This AppImage also contains
the components below. Each stays under its own license, whose full text is in
licenses/; none of them is relicensed under MIT. glibc, libstdc++ and the GPU
drivers are not included: they come from the system the AppImage runs on.

| component | included as | license |
|---|---|---|
EOF
cp "$TREE/shaders/LICENSE.md" "$LIC/face-shaders.md"
row "Face shaders by iq, noztol, whisky_shusuky, baopinsui, katiemil, dathor and FabriceNeyret2" \
    "data files, usr/share/shader-cube/shaders" \
    "per shader, MIT or CC BY-NC-SA 3.0 (non-commercial): licenses/face-shaders.md"
if [ -f "$PHYSX_DIR/physx/LICENSE.md" ]; then
    PXV=$(cut -d. -f1-3 "$PHYSX_DIR/physx/version.txt" 2>/dev/null || echo 5)
    cp "$PHYSX_DIR/physx/LICENSE.md" "$LIC/NVIDIA PhysX $PXV.txt"
    row "NVIDIA PhysX $PXV" "linked into shader-cube; usr/lib/libPhysXGpu_64.so" \
        "Apache-2.0: licenses/NVIDIA PhysX $PXV.txt"
fi
for f in "${STATIC_LICENSES:-/opt/deps/share/licenses}"/*.txt; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .txt)
    cp "$f" "$LIC/$name.txt"
    row "$name" "linked into shader-cube" "licenses/$name.txt"
done
while read -r name path; do
    path=${path#(}
    path=${path%)}
    if pkg=$(pkg_license "$path" "$LIC/$name.txt"); then
        note="licenses/$name.txt (from the $pkg package)"
        case "$name" in libcudart*) note="NVIDIA CUDA Toolkit EULA, redistributable under its Attachment A: $note" ;; esac
        row "$name" "usr/lib" "$note"
    else
        row "$name" "usr/lib" "no license text found on the build system"
    fi
done < "$WORK/bundled.txt"
RT_TAG=$(basename "$(dirname "${RUNTIME_URL:-x/main/runtime}")")
row "AppImage type2-runtime $RT_TAG" "the executable start of the AppImage file" \
    "MIT; statically links libfuse3 (LGPL-2.1), squashfuse (BSD-2-Clause), zstd (BSD-3-Clause), zlib (Zlib), mimalloc (MIT), musl (MIT). Source, to rebuild or relink it: https://github.com/AppImage/type2-runtime/tree/$RT_TAG"
cat "$NOTICES"

newest() { # SYMBOL-VERSION-PREFIX: the newest one any bundled ELF needs
    for f in "$APPDIR/usr/bin/shader-cube" "$APPDIR"/usr/lib/*.so*; do
        objdump -T "$f" | grep -o "$1[0-9.]*" || true # (set -e reaches in here)
    done | sort -uV | tail -1
}
GLIBC=$(newest GLIBC_)
GLIBCXX=$(newest GLIBCXX_)
echo "needs from the host: ${GLIBC:-?} and libstdc++ ${GLIBCXX:-?} or newer"

step "AppImage"
OUT=$DIST/shader-cube-$VERSION-$ARCH.AppImage
set --
[ -n "${APPIMAGE_RUNTIME:-}" ] && set -- --runtime-file "$APPIMAGE_RUNTIME"
rm -f "$OUT"
ARCH=$ARCH VERSION=$VERSION "${APPIMAGETOOL:-appimagetool}" --no-appstream "$@" "$APPDIR" "$OUT"
echo
echo "built $OUT ($(du -h "$OUT" | cut -f1)), needs $GLIBC+"
