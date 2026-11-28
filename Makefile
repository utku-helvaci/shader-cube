# SPDX-License-Identifier: MIT
CC       ?= cc
CXX      ?= c++
CFLAGS   ?= -O2 -Wall -Wextra
CXXFLAGS ?= -O2 -Wall -Wextra
PKG_CONFIG ?= pkg-config

# TARGET=windows: shader-cube.exe with MinGW-w64, in MSYS2 (where it is the
# default) or cross-compiled (tools/windows/build.sh).
TARGET ?= $(if $(filter Windows_NT,$(OS)),windows,linux)

# Vulkan is loaded at runtime (third_party/volk): only its headers are needed.
PKGS     ?= glfw3 epoxy shaderc libpng
CFLAGS   += $(shell $(PKG_CONFIG) --cflags $(PKGS)) -Ithird_party/volk -Ithird_party/stb
LDLIBS    = $(shell $(PKG_CONFIG) --libs $(PKGS)) -lm

SRC = main scene_cube scene_galton ui gpuphys plat gfx_gl gfx_vk imgout
OBJ = $(SRC:%=build/%.o) build/volk.o
HDR = $(wildcard src/*.h)

ifeq ($(TARGET),windows)
EXE      = shader-cube.exe
CFLAGS  += -D_WIN32_WINNT=0x0A00
LDLIBS  += -lwinmm -lpthread
# PhysX comes from shader-cube-physx.dll (MSVC; tools/windows/), loaded at runtime.
OBJ     += build/physics_dll.o
LINK     = $(CC)
else
EXE      = shader-cube
LDLIBS  += -lpthread -ldl
LINK     = $(CXX)
# NVIDIA PhysX, built from the third_party/PhysX submodule by `make physx`
# (tools/build_physx.sh).  Without it the debris is disabled and the Galton
# board uses the compute-shader engine.
PHYSX_ROOT   ?= build/PhysX/physx
PHYSX_LIBDIR ?= $(firstword $(wildcard $(PHYSX_ROOT)/lib/bin/linux.x86_64/release))
ifneq ($(PHYSX_LIBDIR),)
OBJ        += build/physics_physx.o
PHYSX_LIBS  = -Wl,--start-group \
              $(addprefix $(PHYSX_LIBDIR)/lib,PhysXExtensions_static_64.a PhysX_static_64.a \
                PhysXPvdSDK_static_64.a PhysXCommon_static_64.a PhysXFoundation_static_64.a) \
              -Wl,--end-group
# libPhysXGpu_64.so (the CUDA part) is dlopen'ed at runtime from here.
PHYSX_LIBS += -Wl,-rpath,'$$ORIGIN' -Wl,-rpath,$(abspath $(PHYSX_LIBDIR))
else
OBJ        += build/physics_none.o
endif
endif

# Linked as C++ on Linux: PhysX and (when linked statically) shaderc are C++.
$(EXE): $(OBJ)
	$(LINK) $(LDFLAGS) -o $@ $(OBJ) $(PHYSX_LIBS) $(LDLIBS)

build/%.o: src/%.c $(HDR) | build
	$(CC) $(CFLAGS) -c -o $@ $<

build/volk.o: third_party/volk/volk.c third_party/volk/volk.h | build
	$(CC) $(CFLAGS) -c -o $@ $<

build/physics_physx.o: src/physics_physx.cpp src/physics.h | build
	$(CXX) $(CXXFLAGS) -std=c++17 -fno-rtti -fno-exceptions -DNDEBUG -isystem $(PHYSX_ROOT)/include -c -o $@ $<

build:
	mkdir -p build

physx:
	tools/build_physx.sh

# Portable AppImage, built in a container (tools/appimage/build.sh --host:
# with this machine's toolchain instead).
appimage:
	tools/appimage/build.sh

# ... and start it on a clean Ubuntu 22.04 with software rendering.
appimage-test:
	tools/appimage/build.sh --test

run: $(EXE)
	./$(EXE)

# The program only; the PhysX build and the AppImage caches stay.
clean:
	rm -f build/*.o shader-cube shader-cube.exe

# Everything that was built, PhysX included.
distclean:
	rm -rf build dist shader-cube shader-cube.exe

.PHONY: run clean distclean physx appimage appimage-test
