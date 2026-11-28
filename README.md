# shader-cube

Two real-time scenes rendered with OpenGL ES 3.1, OpenGL 4.3 or Vulkan 1.3, on Linux and Windows, live or offline to image files:

- **Shader cube**: a cube with a Shadertoy shader on each face, bouncing around a room with a moving light. The faces emit light: each one acts as an area light on the room, and the floor reflects the cube. Hundreds of PhysX rigid bodies litter the floor and get knocked around by the cube and the light.
- **Galton board**: steel balls run from a hopper through rows of pins, between two glass panes, into bins, where they pile up into a normal distribution. The balls are simulated by NVIDIA PhysX (on the GPU with CUDA, or on the CPU) or by a physics engine written in compute shaders.

**F1** opens the settings menu: the scene, its physics and look, and the display.

    make physx    # once: NVIDIA PhysX, from the third_party/PhysX submodule (optional)
    make && ./shader-cube
    ./shader-cube --scene galton

Needs GLFW, libepoxy, the Vulkan headers, shaderc and libpng (Arch: `glfw libepoxy vulkan-headers shaderc libpng`), and for PhysX, CMake and the CUDA toolkit (see [PhysX](#physx)). The Vulkan loader is opened at runtime, so the program also runs, with OpenGL, where there is none. Windows: see [Windows](#windows).

## GPU selection

shader-cube does not pick a GPU itself; it uses whatever the system gives it:

    shader-cube              # default GPU (the integrated one on hybrid laptops)
    prime-run shader-cube    # NVIDIA dGPU (PRIME render offload)

The usual environment variables work too (`__NV_PRIME_RENDER_OFFLOAD`, `DRI_PRIME`, `MESA_VK_DEVICE_SELECT`, ...). With Vulkan it takes the first suitable device in the order the loader reports. The startup line shows which one it got.

## The menu (F1)

| | keyboard | mouse |
|---|---|---|
| choose a row | `↑` `↓` (or `W` `S`), `PgUp` `PgDn` `Home` `End` | point at it |
| change it | `←` `→` (or `A` `D`); `Shift` for big steps | click the arrows, drag a slider |
| switch, press | `Enter` / `Space` | click |
| scroll | | wheel |
| close | `Esc` / `F1` | |

It holds the scene choice; the scene's own settings (physics engine, numbers of bodies, materials, look); and the display: vsync, a frame-rate limit, pause. Changes apply immediately; the ones that rebuild a physics world (engine, ball count, rows) wait half a second for the slider to settle. The menu's font is [Atkinson Hyperlegible](https://www.brailleinstitute.org/freefont/), rasterised with stb_truetype.

## Scenes

### Shader cube

| input | action |
|---|---|
| left-click / drag on a cube face | `iMouse` for that face's shader (the cube holds still while pressed) |
| keys after clicking a face | go to that shader's keyboard texture (e.g. WASD in the black hole) |
| drag elsewhere, right-drag | orbit the camera; `F3` returns to the auto camera |
| `1`–`6` | stop / restart that face shader (every cube face using it); a stopped face keeps its last frame and resumes from the same time |
| `F6` / `F7` | view each face shader full-window / back to the room |
| `F8` | blast the PhysX debris |
| `F2` pause · `F5` reload shaders · `Esc` quit | |

The debris runs on PhysX (GPU or CPU, see below); the menu changes its engine and number of bodies.

### Galton board

The hopper holds the balls (1200 by default) above a closed gate. A second after the start, or with `Space`, the gate opens; `R` refills the hopper. The board is built for the chosen numbers of balls and rows of pins (default 14): the bins are as tall as the piles will grow, the hopper as large as the balls need. Drag to orbit, wheel to zoom, `F3` resets the camera.

The glowing line on the front pane is a normal curve: by default fitted to the balls in the bins (their mean and spread, growing as they arrive), or, from the menu, the binomial prediction for an ideal board.

A real board doesn't reach the ideal binomial spread: a ball that bounces off a pin keeps some of its sideways speed and can skip a pin. The boards here are tuned the way real ones work, with pins that take most of a ball's speed (friction, and the spin it causes, which is damped), and their piles come out about 1.6 times as wide as the binomial, in both engines. `GALTON_STATS=1` prints the counts per bin, their mean and spread, against the binomial, every two seconds.

## Physics

### PhysX

NVIDIA PhysX 5. On an NVIDIA GPU a world can run PhysX's CUDA pipeline (GPU broad phase, contact generation and solver, in `libPhysXGpu_64.so` / `PhysXGpu_64.dll`); otherwise, or when chosen, the CPU solver. `--physics auto` (the default) uses the GPU when the program renders on an NVIDIA GPU, i.e. under `prime-run`; plain runs leave the dGPU alone. `PHYSX_GPU_DEVICE` selects the CUDA device (default 0). PhysX on the GPU needs an NVIDIA driver with CUDA 13 support (580 or newer); otherwise it falls back to the CPU.

The SDK is the `third_party/PhysX` git submodule ([NVIDIA-Omniverse/PhysX](https://github.com/NVIDIA-Omniverse/PhysX), pinned to tag `110.3-omni-and-physx-5.9.1`, i.e. PhysX 5.9.1, Apache-2.0). It is built once (CUDA toolkit needed for the GPU part):

    make physx    # = tools/build_physx.sh, into build/PhysX; PHYSX_GPU=0 for a CPU-only build
    make

`make physx` fetches the submodule itself if it isn't checked out: only the pinned commit, and without the Git LFS files of the repository's `omni/` directory, which shader-cube doesn't use. By hand, that is

    GIT_LFS_SKIP_SMUDGE=1 git submodule update --init --depth 1 third_party/PhysX

(`git clone --recurse-submodules` works too, but with git-lfs installed it also downloads those LFS files, about 120 MB.)

The submodule is never modified. The script copies its `physx/` directory to `build/PhysX`, patches two incompatibilities with CUDA 13 and GCC 15+ there, and builds the CUDA kernels only for the local GPU's architecture. To move to another PhysX release, check out its tag in the submodule and commit that:

    git -C third_party/PhysX fetch --depth 1 origin tag TAG && git -C third_party/PhysX checkout TAG
    git add third_party/PhysX

The next `make physx` then starts over from the new sources. `make clean` keeps the PhysX build, `make distclean` removes it. Without PhysX, `make` still builds: the cube scene has no debris and the Galton board uses the compute shaders.

### Compute shaders

`src/gpuphys.c`: the Galton board's balls simulated entirely on the GPU, through the same rendering interface as everything else (OpenGL 4.3, OpenGL ES 3.1 or Vulkan; not OpenGL ES 3.0). Position-based dynamics with eight or more substeps per frame:

1. integrate gravity and predict positions;
2. sort the balls into a uniform grid with atomic counters;
3. two Jacobi iterations push overlapping balls apart and out of the pins and walls (found through a coarse grid of the statics), and keep them between the panes;
4. velocities follow from the corrected positions, with restitution and Coulomb friction against the statics; balls that come to rest in a bin freeze and become support for the next ones.

The balls never come back to the CPU: the last pass writes the instance buffer the renderer draws them from.

## Options

| option | |
|---|---|
| `--scene cube\|galton` | the scene to start with (default cube) |
| `--api gles\|gl\|vulkan` | OpenGL ES 3.1 (3.0 without compute shaders; default), OpenGL 4.3 core, or Vulkan 1.3 |
| `--physics auto\|gpu\|cpu\|compute\|off` | PhysX on the GPU or CPU, or the compute shaders (Galton board); `--physx` is the same |
| `--vsync on\|off` | sync to the display (default on) |
| `--fps-limit N` | cap the frame rate at N fps |
| `--size WxH` | window size, or output size offline (default 1600x900; 1920x1080 for `--record`) |
| `--quit-after SECONDS` | exit after that long and print the average frame rate |
| `--gfx-debug` | OpenGL debug output / Vulkan validation layer |
| `--menu` | open the menu at start |
| `--debris N` | cube: number of PhysX bodies (default 600) |
| `--balls N`, `--rows N` | Galton board: balls (default 1200) and rows of pins (default 14) |
| `--res N`, `--view FACE`, `--shaders DIR`, `--stop 1,3` | cube: face size (default 1024), start viewing a face, shader folder, start with faces stopped |

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
| `--inject T:KEY,...` | press keys at simulated times, e.g. `1:F1,1.5:DOWN,2:RIGHT` (scripted recordings, tests) |

Images are encoded on background threads. Ctrl+C stops early and still writes every frame rendered so far. Offline Vulkan rendering needs no window system at all. With `--menu` (or an injected `F1`) the menu is in the recorded frames too.

## Windows

The [Releases](../../releases) page has `shader-cube-VERSION-windows-x86_64.zip` next to the AppImage: unpack it and start `shader-cube.exe`. It holds the program, the DLLs it needs, the shaders and fonts, PhysX (`shader-cube-physx.dll` and, for the GPU, `PhysXGpu_64.dll`), and the license notices. The GPU drivers and the Vulkan loader come from the system. From a command prompt, the options above work as on Linux.

The program is built with MinGW-w64 against MSYS2's UCRT64 packages; PhysX, which needs MSVC (and CUDA for its GPU part), lives in `shader-cube-physx.dll`, which the program loads at runtime. Without it, the program runs without PhysX (the Galton board then uses the compute shaders).

Building it:

| where | how |
|---|---|
| Windows, MSYS2 UCRT64 shell | `pacman -S make zip unzip mingw-w64-ucrt-x86_64-{gcc,pkgconf,glfw,libepoxy,vulkan-headers,shaderc,libpng}`, then `tools/windows/build.sh` |
| Linux (docker) | `tools/windows/build.sh`: a cross build with Debian's MinGW-w64 and the same MSYS2 packages, pinned in `tools/windows/versions.sh` |
| PhysX (Windows, Git Bash from an MSVC x64 prompt) | `tools/windows/physx.sh build/windows/physx-dll`, then `PHYSX_DLL_DIR=build/windows/physx-dll tools/windows/build.sh`; it downloads the CUDA components it needs from NVIDIA (pinned) |

`tools/windows/build.sh --test` then starts the result with software rendering and has it draw both scenes through Vulkan and OpenGL: on Linux under Wine (in docker, with Mesa underneath), in MSYS2 with MSYS2's Mesa.

## AppImage

    make appimage                      # = tools/appimage/build.sh
    prime-run dist/shader-cube-*-x86_64.AppImage --api vulkan

The pipeline builds inside an Ubuntu 22.04 container (docker), so the AppImage runs on any x86_64 distribution with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora 36 and later). The container has GCC 12, CUDA 13.4, and static GLFW 3.5 (Wayland + X11) and shaderc. PhysX's CUDA kernels are built for Turing through Blackwell (`PHYSX_CUDA_ARCH` in `tools/appimage/versions.sh`). The docker image and that PhysX build take a while the first time; both are cached afterwards.

The AppImage bundles everything except glibc, libstdc++, the Vulkan loader and the GPU drivers, which come from the host, so `prime-run` and the other GPU-selection variables work as usual.

`make appimage-test` (or `--test`) then runs it on a clean Ubuntu 22.04 container with no GPU: Mesa's software renderers draw a frame of each scene with Vulkan, OpenGL ES and OpenGL, proving the bundle is complete on the oldest supported system.

`tools/appimage/build.sh --host` builds the same AppImage with this machine's toolchain in about a minute, for testing. It only runs on systems at least as new as this one. Every downloaded tool is pinned by version and SHA-256 in `versions.sh`.

## GitHub Actions

`.github/workflows/build.yml` builds both on every push to `main`/`master`, on pull requests and on demand:

- **Linux**: the AppImage pipeline above, smoke test included.
- **Windows** (windows-2025 runner): PhysX and `shader-cube-physx.dll` with MSVC and CUDA, the program in MSYS2, the zip, and a smoke test with Mesa's software renderers.

Each run keeps the AppImage, the zip and the smoke-test renders as artifacts. Every push to `main`/`master` is also published on the Releases page, as a release titled with the commit's first line (tag `build-<short commit hash>`) holding the AppImage, the Windows zip and their `SHA256SUMS`; the newest is marked *Latest*. Pushing a `v*` tag (e.g. `git tag v1.0.0 && git push origin v1.0.0`) publishes a release of that version. A failed Windows build doesn't hold back the AppImage's release.

The first run takes about an hour per platform, mostly compiling PhysX's CUDA kernels. The Linux build image, the CUDA components and both PhysX builds are then cached, keyed on the files that define them and the submodule's commit, and later runs take a few minutes.

### Licenses in the builds

The AppImage (`usr/share/doc/shader-cube/`) and the Windows zip hold `LICENSE`, `THIRD-PARTY-NOTICES.md` and the full license text of every component they contain (PhysX, the CUDA runtime, GLFW, shaderc/glslang/SPIRV-Tools, libepoxy, libpng, zlib, the MinGW runtime, volk, stb_truetype, the font, the AppImage runtime), generated by the packaging scripts from what they actually pack.

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

The shaders belong to their authors; see [`shaders/LICENSE.md`](shaders/LICENSE.md). The Galton board doesn't use them: its shaders are its own (`src/scene_galton.c`).

Supported: Image, Common, Buffer A–D (RGBA32F, ping-ponged like Shadertoy), Volume A (`mainVolume`, read as `sampler3D`), keyboard, `iMouse`, and all the standard uniforms. Under Vulkan the shaders are compiled to SPIR-V at startup with shaderc, so the same sources work with every API.
Not supported: Shadertoy image and cubemap textures, video, sound (the importer substitutes noise and warns).

`channels.cfg` can also set `resolution W H` and `crop`. With `crop`, a wide render is shown as its centre square instead of being squashed.

## Source

| file | |
|---|---|
| `src/main.c` | the application: options, window, frame loop, bloom and tone mapping, offline recording, scene switching |
| `src/scene_cube.c` | the shader cube: Shadertoy passes, the room and its lighting, the bouncing cube, debris |
| `src/scene_galton.c` | the Galton board: its geometry (for both physics engines), shaders, camera and menu |
| `src/gpuphys.c` | the compute-shader physics engine |
| `src/ui.c` | the F1 menu: fonts (stb_truetype), widgets, keyboard and mouse |
| `src/gfx.h` | the small rendering interface everything draws through (also compute shaders and storage buffers) |
| `src/gfx_gl.c` | OpenGL ES 3.1 / OpenGL 4.3 backend (libepoxy) |
| `src/gfx_vk.c` | Vulkan 1.3 backend (dynamic rendering, push descriptors, shaderc, volk) |
| `src/physics_physx.cpp` | both PhysX worlds (`physics_none.c` without PhysX; `physics_dll.c` loads them from a DLL on Windows) |
| `src/plat.c` | the platform layer: time, sleeping, directories (Linux, Windows) |
| `src/imgout.c` | threaded PNG / PPM writer |
| `third_party/PhysX` | git submodule: the NVIDIA PhysX SDK sources |
| `third_party/volk`, `third_party/stb` | volk (Vulkan loader, MIT) and stb_truetype (MIT / public domain), vendored |
| `assets/fonts` | the menu's font (SIL Open Font License) |
| `tools/build_physx.sh` | patches and builds PhysX from the submodule, into `build/PhysX` |
| `tools/appimage/` | AppImage pipeline: `build.sh` (entry), `Dockerfile`, `bundle.sh`, `smoke_test.sh`, pinned `versions.sh`, desktop entry and icon |
| `tools/windows/` | Windows build: `build.sh` (entry), `physx.sh` (MSVC), `package.sh`, `smoke_test.sh`, `Dockerfile` (cross build), pinned `versions.sh` |
| `.github/workflows/build.yml` | CI: builds and smoke-tests both, publishes them as a release for each push and `v*` tag |

## License

shader-cube's own code and assets, i.e. everything outside `shaders/`, `third_party/` and `assets/fonts/` (the program, tools, build files, icon and documentation), are released under the [MIT license](LICENSE).

These are **not** covered by it and stay under their own licenses:

- The face shaders in `shaders/` belong to their authors and are redistributed unmodified, with attribution, under each author's own license: MIT, or Shadertoy's default CC BY-NC-SA 3.0. Those licenses allow this redistribution without further permission, but the CC BY-NC-SA shaders must not be used commercially. Details and links are in [`shaders/LICENSE.md`](shaders/LICENSE.md). For commercial use, swap in shaders whose licenses allow it.
- The Atkinson Hyperlegible font (`assets/fonts/`, © Braille Institute of America) is under the SIL Open Font License 1.1 ([`OFL.txt`](assets/fonts/OFL.txt)), which allows bundling it with software.
- volk ([`LICENSE.md`](third_party/volk/LICENSE.md), MIT) and stb_truetype (MIT or public domain, at the end of the header) are vendored unmodified.
- PhysX is a git submodule (Apache-2.0); it and the other libraries are fetched at build time. Builds that bundle them (the AppImage, the Windows zip) include their license texts.
