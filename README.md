# shader-cube

A cube with a Shadertoy shader on each face, bouncing around a room with a moving light. The faces emit light: each one acts as an area light on the room, and the floor reflects the cube. Hundreds of PhysX rigid bodies litter the floor and get knocked around by the cube and the light. Renders with OpenGL ES 3.0, OpenGL 4.3 or Vulkan 1.3, in real time or offline to image files.

    make physx    # once: NVIDIA PhysX, from the third_party/PhysX submodule (optional)
    make && ./shader-cube

Needs GLFW, libepoxy, Vulkan headers + loader, shaderc and libpng (Arch: `glfw libepoxy vulkan-headers vulkan-icd-loader shaderc libpng`), and for PhysX, CMake and the CUDA toolkit (see [PhysX](#physx)).

## GPU selection

shader-cube does not pick a GPU itself; it uses whatever the system gives it:

    shader-cube              # default GPU (the integrated one on hybrid laptops)
    prime-run shader-cube    # NVIDIA dGPU (PRIME render offload)

The usual environment variables work too (`__NV_PRIME_RENDER_OFFLOAD`, `DRI_PRIME`, `MESA_VK_DEVICE_SELECT`, ...). With Vulkan it takes the first suitable device in the order the loader reports. The startup line shows which one it got.

## Options

| option | |
|---|---|
| `--api gles\|gl\|vulkan` | OpenGL ES 3.0 (default), OpenGL 4.3 core, or Vulkan 1.3 |
| `--vsync on\|off` | sync to the display (default on) |
| `--fps-limit N` | cap the frame rate at N fps |
| `--size WxH` | window size, or output size offline (default 1600x900; 1920x1080 for `--record`) |
| `--quit-after SECONDS` | exit after that long and print the average frame rate |
| `--gfx-debug` | OpenGL debug output / Vulkan validation layer |
| `--physx auto\|gpu\|cpu\|off` | PhysX debris; `auto` runs it on the GPU (CUDA) when rendering on an NVIDIA GPU, else on the CPU |
| `--debris N` | number of PhysX bodies (default 600) |
| `--res N`, `--view FACE`, `--shaders DIR`, `--stop 1,3` | face size (default 1024), start viewing a face, shader folder, start with faces stopped |

## Offline rendering

Frames are rendered at a fixed time step, however long each one takes, and written as numbered images:

    shader-cube --record out --duration 20 --rate 60 --size 3840x2160
    ffmpeg -framerate 60 -i out/frame_%06d.png -c:v libx264 -crf 16 -pix_fmt yuv420p cube.mp4

| option | |
|---|---|
| `--record DIR` | write `DIR/frame_000000.png`, ... (DIR is created) |
| `--frames N` / `--duration SECONDS` | how much to render (default 10 s) |
| `--rate FPS` | frames per simulated second (default 60) |
| `--start SECONDS` | simulate up to this time before the first written frame |
| `--format png\|ppm` | image format (default png) |
| `--preview` | show the frames in a window while rendering |
| `--screenshot FILE --at SECONDS` | a single frame (.png or .ppm) |

Images are encoded on background threads. Ctrl+C stops early and still writes every frame rendered so far. Offline Vulkan rendering needs no window system at all.

## PhysX

The debris is simulated by NVIDIA PhysX 5. On an NVIDIA GPU it runs PhysX's CUDA pipeline (GPU broad phase, contact generation and solver in `libPhysXGpu_64.so`); elsewhere it uses the CPU solver. The cube and the light are kinematic bodies that plough through the debris. `F8` blasts it into the air.

The SDK is the `third_party/PhysX` git submodule ([NVIDIA-Omniverse/PhysX](https://github.com/NVIDIA-Omniverse/PhysX), pinned to tag `110.3-omni-and-physx-5.9.1`, i.e. PhysX 5.9.1, Apache-2.0). It is built once (CUDA toolkit needed for the GPU part):

    make physx    # = tools/build_physx.sh, into build/PhysX; PHYSX_GPU=0 for a CPU-only build
    make

`make physx` fetches the submodule itself if it isn't checked out: only the pinned commit, and without the Git LFS files of the repository's `omni/` directory, which shader-cube doesn't use. By hand, that is

    GIT_LFS_SKIP_SMUDGE=1 git submodule update --init --depth 1 third_party/PhysX

(`git clone --recurse-submodules` works too, but with git-lfs installed it also downloads those LFS files, about 120 MB.)

The submodule is never modified. The script copies its `physx/` directory to `build/PhysX`, patches two incompatibilities with CUDA 13 and GCC 15+ there, and builds the CUDA kernels only for the local GPU's architecture. To move to another PhysX release, check out its tag in the submodule and commit that:

    git -C third_party/PhysX fetch --depth 1 origin tag TAG && git -C third_party/PhysX checkout TAG
    git add third_party/PhysX

The next `make physx` then starts over from the new sources. `make clean` keeps the PhysX build, `make distclean` removes it.

Without PhysX, `make` still builds; the debris is just left out. `PHYSX_GPU_DEVICE` selects the CUDA device (default 0).

## AppImage

    make appimage                      # = tools/appimage/build.sh
    prime-run dist/shader-cube-*-x86_64.AppImage --api vulkan

The pipeline builds inside an Ubuntu 22.04 container (docker), so the AppImage runs on any x86_64 distribution with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora 36 and later). The container has GCC 12, CUDA 13.4, and static GLFW 3.5 (Wayland + X11) and shaderc. PhysX's CUDA kernels are built for Turing through Blackwell (`PHYSX_CUDA_ARCH` in `tools/appimage/versions.sh`). The docker image and that PhysX build take a while the first time; both are cached afterwards.

The AppImage bundles everything except glibc, libstdc++ and the GPU drivers, which come from the host, so `prime-run` and the other GPU-selection variables work as usual. PhysX on the GPU needs an NVIDIA driver with CUDA 13 support (580 or newer); otherwise it falls back to the CPU.

`make appimage-test` (or `--test`) then runs it on a clean Ubuntu 22.04 container with no GPU: Mesa's software renderers draw a frame with Vulkan, OpenGL ES and OpenGL, proving the bundle is complete on the oldest supported system.

`tools/appimage/build.sh --host` builds the same AppImage with this machine's toolchain in about a minute, for testing. It only runs on systems at least as new as this one. Every downloaded tool is pinned by version and SHA-256 in `versions.sh`.

### GitHub Actions

`.github/workflows/appimage.yml` runs the same pipeline, smoke test included, on every push to `main`/`master`, on pull requests and on demand. The AppImage is attached to each run as the `shader-cube-AppImage` artifact; the smoke-test renders are uploaded too. Every push to `main`/`master` is also published on the repository's Releases page, as a release titled with the commit's first line (tag `build-<short commit hash>`) holding the AppImage and its `SHA256SUMS`; the newest is marked *Latest*. Pushing a `v*` tag (e.g. `git tag v1.0.0 && git push origin v1.0.0`) publishes a release of that version.

The first run takes about an hour: it builds the toolchain image and compiles PhysX's CUDA kernels on a 4-core runner. The image and the PhysX build are then cached, keyed on `Dockerfile`, `versions.sh`, `build_physx.sh` and (for PhysX) the submodule's commit, and later runs take a few minutes. Changing one of those files rebuilds only what depends on it.

### Licenses in the AppImage

Inside the AppImage, `usr/share/doc/shader-cube/` holds `LICENSE`, `THIRD-PARTY-NOTICES.md` and the full license text of every bundled component (PhysX, the CUDA runtime, GLFW, shaderc/glslang/SPIRV-Tools, libepoxy, libpng, zlib, the Vulkan loader, the AppImage runtime), generated by `bundle.sh` from what it actually packs.

## Controls

| input | action |
|---|---|
| left-click / drag on a cube face | `iMouse` for that face's shader (the cube holds still while pressed) |
| keys after clicking a face | go to that shader's keyboard texture (e.g. WASD in the black hole) |
| drag elsewhere, right-drag | orbit the camera; `F3` returns to the auto camera |
| `1`–`6` | stop / restart that face shader (every cube face using it); a stopped face keeps its last frame and resumes from the same time |
| `F6` / `F7` | view each face shader full-window / back to the room |
| `F8` | blast the PhysX debris |
| `F2` pause · `F5` reload shaders · `Esc` quit | |

The window title shows the API, the GPU and the frame rate.

## Faces

`shaders/faceN/` (N = 0..5) is cube face N, in the order +X −X +Y −Y +Z −Z. They were generated from the Shadertoy JSON exports in `shaders/shadertoy/`:

    python3 tools/import_shadertoy.py shaders/shadertoy/Xds3zN.json shaders/face0

| face | shader | license |
|---|---|---|
| 0 | [Raymarching - Primitives](https://www.shadertoy.com/view/Xds3zN) by iq | MIT |
| 1 | [Light Cycle](https://www.shadertoy.com/view/7XVSWG) by noztol | CC BY-NC-SA 3.0 |
| 2 | [Octagrams](https://www.shadertoy.com/view/tlVGDt) by whisky_shusuky | CC BY-NC-SA 3.0 |
| 3 | [Kerr Newman Black Hole](https://www.shadertoy.com/view/wXdfzj) by baopinsui: 4 buffers, keyboard | CC BY-NC-SA 3.0 |
| 4 | [latte art](https://www.shadertoy.com/view/Nfsczj) by katiemil: drawable with the mouse | CC BY-NC-SA 3.0; `common.glsl` MIT |
| 5 | [Metamorphosis Volume](https://www.shadertoy.com/view/NXySRV) by dathor, after FabriceNeyret2: Volume A pass (128³ 3D texture) | CC BY-NC-SA 3.0 |

The shaders belong to their authors; see [`shaders/LICENSE.md`](shaders/LICENSE.md).

Supported: Image, Common, Buffer A–D (RGBA32F, ping-ponged like Shadertoy), Volume A (`mainVolume`, read as `sampler3D`), keyboard, `iMouse`, and all the standard uniforms. Under Vulkan the shaders are compiled to SPIR-V at startup with shaderc, so the same sources work with every API.
Not supported: Shadertoy image and cubemap textures, video, sound (the importer substitutes noise and warns).

`channels.cfg` can also set `resolution W H` and `crop`. With `crop`, a wide render is shown as its centre square instead of being squashed.

## Source

| file | |
|---|---|
| `src/main.c` | scene, Shadertoy passes, simulation, input, real-time and offline loops |
| `src/gfx.h` | the small rendering interface the app draws through |
| `src/gfx_gl.c` | OpenGL ES 3.0 / OpenGL 4.3 backend (libepoxy) |
| `src/gfx_vk.c` | Vulkan 1.3 backend (dynamic rendering, push descriptors, shaderc) |
| `src/physics_physx.cpp` | PhysX scene (`physics_none.c` when built without PhysX) |
| `src/imgout.c` | threaded PNG / PPM writer |
| `third_party/PhysX` | git submodule: the NVIDIA PhysX SDK sources |
| `tools/build_physx.sh` | patches and builds PhysX from the submodule, into `build/PhysX` |
| `tools/appimage/` | AppImage pipeline: `build.sh` (entry), `Dockerfile`, `bundle.sh`, `smoke_test.sh`, pinned `versions.sh`, desktop entry and icon |
| `.github/workflows/appimage.yml` | CI: builds and smoke-tests the AppImage, publishes it as a release for each push and `v*` tag |

## License

shader-cube's own code and assets, i.e. everything outside `shaders/` (the program, tools, build files, icon and documentation), are released under the [MIT license](LICENSE).

The face shaders in `shaders/` are **not** covered by it. They belong to their authors and are redistributed unmodified, with attribution, under each author's own license: MIT, or Shadertoy's default CC BY-NC-SA 3.0. Those licenses allow this redistribution without further permission, but the CC BY-NC-SA shaders must not be used commercially. Details and links are in [`shaders/LICENSE.md`](shaders/LICENSE.md). For commercial use, swap in shaders whose licenses allow it.

PhysX and the other libraries are downloaded at build time and are not part of this repository. Builds that bundle them (the AppImage) include their license texts.
