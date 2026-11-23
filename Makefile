# SPDX-License-Identifier: MIT
CC       ?= cc
CXX      ?= c++
CFLAGS   ?= -O2 -Wall -Wextra
CXXFLAGS ?= -O2 -Wall -Wextra
PKG_CONFIG ?= pkg-config
PKGS     ?= glfw3 epoxy vulkan shaderc libpng
CFLAGS   += $(shell $(PKG_CONFIG) --cflags $(PKGS))
LDLIBS    = $(shell $(PKG_CONFIG) --libs $(PKGS)) -lpthread -lm

OBJ = build/main.o build/gfx_gl.o build/gfx_vk.o build/imgout.o
HDR = src/gfx.h src/mathx.h src/physics.h src/imgout.h

# NVIDIA PhysX (tools/build_physx.sh).  Without it the debris is disabled.
PHYSX_ROOT   ?= third_party/PhysX/physx
PHYSX_LIBDIR ?= $(firstword $(wildcard $(PHYSX_ROOT)/lib/bin/linux.x86_64/release))
ifneq ($(PHYSX_LIBDIR),)
OBJ        += build/physics_physx.o
PHYSX_LIBS  = -Wl,--start-group \
              $(addprefix $(PHYSX_LIBDIR)/lib,PhysXExtensions_static_64.a PhysX_static_64.a \
                PhysXPvdSDK_static_64.a PhysXCommon_static_64.a PhysXFoundation_static_64.a) \
              -Wl,--end-group -ldl
# libPhysXGpu_64.so (the CUDA part) is dlopen'ed at runtime from here.
PHYSX_LIBS += -Wl,-rpath,'$$ORIGIN' -Wl,-rpath,$(abspath $(PHYSX_LIBDIR))
else
OBJ        += build/physics_none.o
endif

# Linked as C++: PhysX and (when linked statically) shaderc are C++.
shader-cube: $(OBJ)
	$(CXX) $(LDFLAGS) -o $@ $(OBJ) $(PHYSX_LIBS) $(LDLIBS)

build/%.o: src/%.c $(HDR) | build
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

run: shader-cube
	./shader-cube

clean:
	rm -rf build shader-cube

.PHONY: run clean physx appimage appimage-test
