# SPDX-License-Identifier: MIT
# shellcheck shell=sh disable=SC2034
# Pinned inputs of the Windows build, sourced by the scripts in this
# directory.  Downloads are checked against these SHA-256 sums.

# The program: MinGW-w64 (UCRT) and these MSYS2 UCRT64 packages.  The GitHub
# runner builds in MSYS2 itself; the cross build (Linux, docker) uses Debian
# 13's MinGW-w64 for UCRT with exactly these package files as its sysroot.
CROSS_IMAGE=debian:trixie@sha256:3cda3ca472ce45507a5109c6a3907093e24d9ae67d55954c9a07a45665dafba2
MSYS2_REPO=https://repo.msys2.org/mingw/ucrt64
MSYS2_PACKAGES="
mingw-w64-ucrt-x86_64-glfw-3.5.1-1-any.pkg.tar.zst c2963b68c534199bb4cf65e4dc6c7984ae6709b36a946290d93994964cd2ec30
mingw-w64-ucrt-x86_64-libepoxy-1.5.10-7-any.pkg.tar.zst c6c6994e8ec49071f06cc1fae475406bdf17603d4687ad0bcac2e11078cfd7c8
mingw-w64-ucrt-x86_64-egl-headers-1.5.r284.3ae2b7c-1-any.pkg.tar.zst 29743159048cf216f75d0dc3eb3e0a04a07515db17d839803e54b060f5aeb0b3
mingw-w64-ucrt-x86_64-gles-headers-3.2.r1065.7fc154c-1-any.pkg.tar.zst 066007a50bd08f062b5494f2c4811a219e1a65f4ecdce2beb453f6d9d8b92098
mingw-w64-ucrt-x86_64-vulkan-headers-1~1.4.363.0-1-any.pkg.tar.zst be602b2657cace531316e78b1eda4087e8f7f84ebb877f08fba198a2db06406a
mingw-w64-ucrt-x86_64-shaderc-2026.4-1-any.pkg.tar.zst a4ad271f76acd2307ed67738770b30d6486bd3c7acff63ba83dd13e56ce9ab82
mingw-w64-ucrt-x86_64-glslang-16.6.0-1-any.pkg.tar.zst 74742908b850637e4f0710cd9630f511b0def5b0f18d653cf9657197758bda82
mingw-w64-ucrt-x86_64-spirv-tools-3~1.4.363.0-1-any.pkg.tar.zst d31d67fe918aeee21d1e930fd96360856a60146d23094e4ae8baf071a4049aaa
mingw-w64-ucrt-x86_64-libpng-1.6.59-2-any.pkg.tar.zst 6cc296f5029220e1a226c4bc50294212b20ab8fcabeb00b5a002667f4a882edc
mingw-w64-ucrt-x86_64-zlib-1.4-2-any.pkg.tar.zst 172541cf5e2391a402f092104988699b0163129d22be1d6b4b201bfb84af6fcf
mingw-w64-ucrt-x86_64-libgcc-16.2.0-7-any.pkg.tar.zst bc0ae31c582e0847964b4c8c4b55bb2404a9b7ddce7ebf0b176b6693b76e0c62
mingw-w64-ucrt-x86_64-libstdc++-16.2.0-7-any.pkg.tar.zst 4dd4b216b0e92ffa160127dd50620372609e98cb219ff1c5dcb9b3fbfe153253
mingw-w64-ucrt-x86_64-libwinpthread-14.0.0.r598.ge3d18511f-1-any.pkg.tar.zst c35d6be83d141c8cfbb61f1637dd4b53aac8f5562d766aa26d0741c40bad4e4d
"
# The same libraries by name, for pacman on the runner (plus the toolchain).
MSYS2_INSTALL="glfw libepoxy vulkan-headers shaderc libpng gcc pkgconf binutils"

# PhysX on Windows is built with MSVC (tools/windows/physx.sh); its GPU part
# needs these CUDA 13.4 components (NVIDIA's redistributable archives).
CUDA_REDIST=https://developer.download.nvidia.com/compute/cuda/redist
CUDA_PACKAGES="
cuda_nvcc/windows-x86_64/cuda_nvcc-windows-x86_64-13.4.92-archive.zip 23950047aa5405993129a982a99924b4e6d5eb9bc312300030f3afd9b3b49ea4
cuda_cudart/windows-x86_64/cuda_cudart-windows-x86_64-13.4.92-archive.zip 621a70c4778287b1abf8c27c61b841d797fda2aeff01033374dd19624bcfa249
cuda_crt/windows-x86_64/cuda_crt-windows-x86_64-13.4.92-archive.zip a38e3aa75e259128a1c7fb46e706182e4babca407cd3f3c447d21ab7fb14c7fd
libnvvm/windows-x86_64/libnvvm-windows-x86_64-13.4.92-archive.zip 64fa39ad6332d6c40a02115d64827272f6befbc86e50568254f44d37d924e10b
cccl/windows-x86_64/cccl-windows-x86_64-13.3.4.3.1-archive.zip 17d0ca1592c0dfc974a5fc39f470a6b7bae40da239e3e19bd0752017735acbca
"
