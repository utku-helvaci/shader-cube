# SPDX-License-Identifier: MIT
# Pinned inputs of the AppImage pipeline, sourced by build.sh (which passes
# them to the Dockerfile as build arguments).  Downloads are checked against
# these SHA-256 sums.

# Container baseline: Ubuntu 22.04, glibc 2.35.  Pinned by digest so builds
# are reproducible and the smoke test runs on exactly this image.
BASE_IMAGE=ubuntu:22.04@sha256:f64b2ffc2f10ab8f8505aa56b2664bd846cbb9df87c7e2532e30f7667021c0e6
CUDA_VERSION=13.4
CMAKE_VERSION=3.31.6
GLFW_VERSION=3.5.1
GLFW_SHA256=ea79bc5feffc254c87291980c2d0bce9acebb68c4983b79f961dcd2cb8a611a0
SHADERC_VERSION=v2026.4

APPIMAGETOOL_URL=https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUNTIME_URL=https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64
RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d

# CUDA kernels in the portable build: Turing, Ampere, Ada, Blackwell (SASS),
# plus Turing PTX that newer GPUs can JIT.
PORTABLE_CUDA_ARCH=75,86,89,120
