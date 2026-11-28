# SPDX-License-Identifier: MIT
# Cross build environment for the Windows build of shader-cube: Debian's
# MinGW-w64 for UCRT with the MSYS2 UCRT64 packages listed in versions.sh as
# its sysroot.  Use it through tools/windows/build.sh.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG MSYS2_REPO
ARG MSYS2_PACKAGES
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl zstd make pkg-config gcc-mingw-w64-ucrt64 binutils-mingw-w64-ucrt64 zip unzip file \
    && rm -rf /var/lib/apt/lists/*

# The packages unpacked into /opt/msys2 (so /opt/msys2/ucrt64/...), and
# which package each file came from, for the license notices.
RUN mkdir -p /opt/msys2 /tmp/pkg && cd /tmp/pkg \
    && echo "$MSYS2_PACKAGES" | while read -r f sha; do \
        [ -n "$f" ] || continue; \
        curl -fsSLo "$f" "$MSYS2_REPO/$f" && echo "$sha  $f" | sha256sum -c - || exit 1; \
        tar --zstd -xf "$f" -C /opt/msys2 --exclude='.*' || exit 1; \
        tar --zstd -tf "$f" --exclude='.*' | sed "s|^|${f%-*-*-any.pkg.tar.zst} |" >> /opt/msys2/owners.txt; \
    done \
    && rm -rf /tmp/pkg

ENV MINGW_PREFIX=/opt/msys2/ucrt64 CC=x86_64-w64-mingw32ucrt-gcc OBJDUMP=x86_64-w64-mingw32ucrt-objdump \
    PKG_CONFIG_SYSROOT_DIR=/opt/msys2 PKG_CONFIG_LIBDIR=/opt/msys2/ucrt64/lib/pkgconfig \
    OWNERS=/opt/msys2/owners.txt
