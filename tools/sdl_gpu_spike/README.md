# SDL_GPU phase 0 spike: OXP shader compatibility

This directory holds the phase 0 spike for moving Oolite's renderer from OpenGL
to SDL_GPU ([issue #579](https://github.com/OoliteProject/oolite/issues/579)).
The maintainers' requirement is that OXP shaders keep working unchanged. The
spike tests whether that is achievable before any renderer work starts. It is
not part of the game build.

SDL_GPU only accepts precompiled shader formats: SPIR-V (Vulkan), MSL (Metal)
and DXIL/DXBC (D3D12). OXPs ship legacy GLSL source (GLSL 1.10/1.20 against the
OpenGL compatibility profile). That source is compiled at runtime and relies on
fixed-function built-ins such as `gl_LightSource`, `gl_FrontMaterial`,
`gl_Vertex` and `ftransform()`. Uniforms are set by name.

## Result

**OXP shaders can be kept fully working.** Every shader file found in the
expansion catalog translates and builds an SDL_GPU pipeline on Metal, on
Vulkan through MoltenVK, and on Mesa's Vulkan driver on Linux. The one
exception is a single shader that needs a newer glslang than Debian ships.
Every program OpenGL can render produces the same image after translation,
apart from GPU noise and undefined behaviour (both explained below).

Corpus: every OXZ in the catalog at `addons.oolite.space` (818 expansions, as
of 2026-10-20), plus Oolite's 18 built-in programs. The built-ins cover the
ship default shader, every planet/moon/atmosphere/cloud variant, dust,
texture, and the fixed-function emulation.

- **Configured programs:** the `vertex_shader`/`fragment_shader` pairs in each
  OXP's `Config/*.plist`. There are 392 distinct programs, using 537 shader
  files.
- **Unconfigured files:** 75 more files in OXP `Shaders/` directories that no
  plist references. Some are assigned from JavaScript, some are unused and 10
  are backups. The 65 that aren't backups were paired by file name, with the
  fixed-function stage standing in for a missing partner, giving 52
  programs. 25 configured pairs name files that exist in no catalog OXP, so
  they can't be tested.

There are three test platforms:

| Platform | SDL_GPU backend | OpenGL reference | Toolchain |
|---|---|---|---|
| macOS (Apple Silicon) | Metal | Apple GL 2.1 | glslang 16.6.0, SPIRV-Cross 1.4.363 |
| macOS (Apple Silicon) | Vulkan through MoltenVK | Apple GL 2.1 | glslang 16.6.0, SPIRV-Cross 1.4.363 |
| Linux (Debian 13, arm64, Docker) | Vulkan, Mesa lavapipe 25.0 | Mesa llvmpipe, GL 4.5 compatibility profile | glslang 15.1.0, SDL 3.2.10 |

| Check | Metal | MoltenVK | lavapipe |
|---|---|---|---|
| Translate, validate SPIR-V (`spirv-val`, Vulkan 1.0), create SDL_GPU shaders and pipeline: built-in | 18/18 | 18/18 | 18/18 |
| Same, configured OXP programs | 392/392 | 392/392 | 391/392² |
| Same, unconfigured OXP files | 52/52 | 52/52 | 52/52 |
| Rendered image identical to OpenGL¹, configured programs, unset uniforms = 0.5 | 315/338 | 315/338 | 316/338 |
| Same, unset uniforms = 1 (exercises `int`/`bool` branches) | 337/338 | 337/338 | 338/338 |
| Either value, with the shaders' `fract(sin(x) * 43758.5453)` hash neutralised | 338/338 | 338/338 | not needed at 1 |
| Rendered image identical to OpenGL¹, unconfigured files, unset uniforms = 1 | 14/22 | not run | 37/52 |

¹ At most 2/255 per channel on more than 99.5% of pixels, and a mean
difference below 0.5/255.
² `cotbs-sensors.fragment` uses C-style casts (`(float)x`), which glslang
16.6 accepts through `GL_NV_explicit_typecast` but 15.1 does not.

- **Hash noise accounts for every image difference in configured programs**:
  23 on Apple and 22 on Mesa at 0.5; 1 on Apple and none on Mesa at 1. All
  of these are Griff-family engine and hull shaders that use a `sin()`-based
  hash, thresholded to on/off, for engine flicker. Tiny `sin()` precision
  differences between the GL and SDL_GPU drivers flip individual pixels. With
  the hash constant replaced, all of them match (at most a few pixels off by
  10/255 at the threshold).
- **Every unconfigured-file difference is undefined behaviour.** These are
  the pairings made up for testing:
  - On Apple, 8 vertex shaders ran against the fixed-function fragment stage
    without writing `gl_FrontColor`.
  - On Mesa, 15 fragment shaders ran against the fixed-function vertex stage
    while reading varyings that stage never writes.

  GL leaves those values undefined; the translator supplies zero, or white
  for colour. The game never uses these pairings. Mesa compiles all 52
  pairings, so it gives references Apple couldn't.
- **No OpenGL reference for 7 configured programs.** Apple's GL and Mesa's GL
  both reject them. They use constructor-style array initialisers, a fragment
  input the vertex shader never writes, and other syntax that NVIDIA's driver
  accepts. The translator compiles all of them, but whether their output is
  right is unverified.
- **Only the Mesa column is an independent driver test.** MoltenVK converts
  the SPIR-V to MSL with SPIRV-Cross and runs it on Metal, which is also what
  Apple's GL runs on, so the MoltenVK column only shows that the SPIR-V and
  SDL's Vulkan descriptor-set conventions are correct. Lavapipe and llvmpipe
  share nothing with Apple's stack. They are software drivers, so hardware
  Vulkan drivers (NVIDIA, AMD, Intel) are still untested.
- **Cost:** translating, validating and building pipelines for the 392
  configured programs takes about 2 s, roughly 5 ms per program. That is
  fine for load-time translation; a disk cache can come later.
- **The legacy built-ins are pervasive,** so emulating them is mandatory, not
  optional. Of the 537 configured OXP shader files, 410 read
  `gl_LightSource`, 275 `gl_FrontMaterial`, 256 `gl_LightModel`, 169
  `gl_NormalMatrix`, 157 `gl_ModelViewMatrix`, 143 call `ftransform()`, 70 use
  `gl_TexCoord[]` and 44 `gl_TextureMatrix`. Only 2 use the newer
  `ooliteModelView`-style uniforms. 132 declare `uniform bool` and 45
  `uniform int`. No OXP program leaves out a stage.

## How the translation works

`OOGLSLTranslator.{h,c}` is plain C on top of the glslang and SPIRV-Cross C
APIs, so the game can use it as is in phase 3.

1. **Prelude.** Each stage is compiled as GLSL 4.10 with a generated prelude:
   - Legacy matrix, light, material and fog state becomes a std140 uniform
     block, `OOLegacyState` (layout `OOGLSLLegacyStateBlock`). Each `gl_*`
     name is `#define`d to its member.
   - Legacy attributes, varyings and `gl_FragColor`/`gl_FragData` become
     ordinary `in`/`out` variables. They are declared only when the source
     uses them.
   - `texture2D`, `textureCube`, `shadow2D` and the `*Lod`/`*Proj` variants
     become wrapper functions.
   - `GL_ARB_shading_language_420pack` and `GL_NV_explicit_typecast` are
     enabled, for line continuations, scalar swizzles and C-style casts that
     GL drivers accepted.
   - `gl_DepthRange` becomes a constant.
   - `gl_FragCoord` is flipped to GL's bottom-left origin.
2. **The user's `main`** is renamed and wrapped. The wrapper remaps clip-space
   depth from GL's [-w, w] to SDL_GPU's [0, w], so **engine matrices stay in
   GL convention**. SDL_GPU already normalises the Y direction across backends.
3. **glslang** compiles with relaxed Vulkan rules, so loose `uniform`
   declarations are gathered into a per-stage block (`OOVertexUniforms` /
   `OOFragmentUniforms`).
4. **Missing varyings.** If the fragment shader reads a varying the vertex
   shader never writes, GL leaves it undefined but Metal and Vulkan refuse to
   link. The vertex shader is recompiled with the output declared and zeroed
   (colour defaults to white).
5. **SPIR-V patching.** Descriptor sets and bindings are rewritten to
   SDL_GPU's layout: samplers in set 0/2 numbered from 0, uniform slot 0 =
   `OOLegacyState`, slot 1 = loose uniforms. Fragment input locations are
   matched to vertex outputs by name.
6. **SPIRV-Cross** reflects the uniform block layout (name → offset, type,
   matrix and array stride), the samplers (name → slot, 2D or cube) and the
   vertex inputs (name → location), and emits MSL for Metal.
7. **Missing stages.** A missing vertex or fragment shader is replaced by an
   emulation of the fixed-function stage, written in legacy GLSL and
   translated the same way. It matches GL's fixed-function output exactly
   (max 1/255).

## Implications for the renderer (phases 1–3)

- **Legacy state block.** The renderer must keep GL-equivalent light,
  material and matrix state and upload `OOGLSLLegacyStateBlock` to uniform
  slot 0 of both stages for each draw. This includes the derived values GL
  computes: light products, the scene colour, the inverse/transpose matrices
  and half vectors. `OOOpenGLMatrixManager` and the `glLight`/`glMaterial`
  calls in `Universe.m`, `OOSunEntity.m` and `OOBasicMaterial.m` are where it
  comes from today.
- **Uniforms by name.** OXP uniform binding stays name-based: look the name up
  in the reflected block and write at its offset. A `bool` arrives as a 32-bit
  `uint`, matrices use the reflected matrix stride (`mat3` columns are 16
  bytes), and arrays use the reflected array stride.
- **Vertex inputs by name.** Each reflected vertex input name maps to a mesh
  stream: `oo_Vertex`, `oo_Normal`, `oo_MultiTexCoord0`, `oo_Color`,
  `tangent`, and the dust shader's `aWarpiness`. Pipelines are built from that
  reflection, and unknown inputs read a zero stream.
- **Pipeline cache.** The pipeline is per program plus fixed-function state
  (blend, depth, cull, topology, target formats). That is the cache key
  phase 1 needs.
- **Fixed-function emulation.** It needs `oo_LightingEnabled` and a bound
  `oo_FixedFunctionTexture0` (white when untextured). Disabled lights are
  represented by zeroed colours.

## Open points

- **D3D12 was not tested** (no Windows machine here). The simplest route is
  SDL_GPU's Vulkan backend on Windows. Native D3D12 would add SPIRV-Cross →
  HLSL → DXIL, which needs the DirectX Shader Compiler at runtime.
- **Things the corpus doesn't exercise:** `gl_FragCoord`, `gl_FragData`,
  `gl_Fog`, `gl_FrontColor` and `shadow2D` appear in no OXP shader, and
  `textureCube` in only one. The translator handles them, but their output
  hasn't been compared against GL. 1D and 3D samplers are rejected (none in
  the corpus, and SDL_GPU has no 1D textures).
- **Test limits:** one scene (a lit, textured sphere), with every unset
  uniform at 0.5 or 1 and every unset 2D sampler bound to the same ship
  texture.
  The OXPs' own textures and their animated uniform bindings (engine level,
  time and so on) were not used. The OpenGL reference is Apple's GL 2.1 only.
- **Dependencies:** glslang and SPIRV-Cross; SDL_shadercross is not needed.
  Tested with Homebrew (glslang 16.6.0, SPIRV-Cross 1.4.363.0) and Debian 13
  (glslang 15.1.0, `libspirv-cross-c-shared`, SPIRV-Tools 2025.1). Debian's
  static glslang also needs `SPIRV-Tools-opt`. MSYS2 packaging hasn't been
  checked.
  The static SPIRV-Cross libraries need the C++ runtime at link time, and
  their pkg-config file doesn't list the backend libraries.
- **Minimum glslang version: 15.0.0.** That release added
  `glslang_shader_set_default_uniform_block_name` and
  `…_set_and_binding` to the C API. `GLSLANG_SHADER_VULKAN_RULES_RELAXED`
  dates from 11.8.0. LTS distributions may ship something older. The
  translator only needs the two newer calls because it links both stages in
  one glslang program, which requires the stages' default uniform blocks to
  have different names. Compiling each stage as its own program would avoid
  that and lower the minimum to 11.8.0, since sets, bindings and varying
  locations are rewritten afterwards anyway. Alternatively, glslang can be
  built as a Meson subproject.
- **Full compatibility needs glslang 16.3.0 or later.** That release added
  `GL_NV_explicit_typecast`, which C-style casts such as `(float)x` need.
  Only one catalog shader uses them. Debian 13 and Ubuntu 24.04 ship 15.1.0,
  so a bundled glslang (Meson subproject) is the safer choice for release
  builds.

## Phase 1: renderer layer, immediate mode first

Phase 1 starts the renderer layer in `src/Core/Renderer/`. It goes in
behind the OpenGL backend first, so the game can be checked against itself
at every step.

**Done so far: an immediate-mode replacement** (`OOImmediateMode.h`). It
replaces `glBegin`/`glVertex`/`glColor`/`glEnd` (about 770 calls, mostly in
the HUD and GUI).
- **Same semantics as GL.** Vertices take the current colour, texture
  co-ordinate and normal, as in GL immediate mode.
- **Primitive expansion.** At `OOImmediateEnd()` the batch is expanded into
  primitives SDL_GPU can draw: quads, quad strips, polygons, fans and line
  loops become triangles or line strips. The expansion keeps GL's winding
  and its flat-shading provoking vertex.
- **OpenGL backend** (`OORendererGL.c`). It draws the expanded vertices from
  client-side arrays and leaves all other state to the live GL context.
  Legacy GL code still runs between batches, so:
  - the attribute setters also set GL's current values;
  - `OOImmediateBegin()` picks up values set directly through GL;
  - debug builds warn if a raw `glColor` call lands inside a batch.

  This interop layer (`OO_IMMEDIATE_GL_INTEROP`) is removed when the SDL_GPU
  backend arrives.

**Checks.**
- **`oogpu-immediate-test`.** It draws every primitive type with real GL
  immediate mode and through the new layer, using per-vertex colours and
  non-parallelogram quads, in smooth and flat shading, textured, and with
  wide lines and points. All 40 cases are pixel-identical on Apple's GL
  (max difference 0), and so are the two interop checks. As a negative
  control, swapping the quad diagonal makes all four quad cases fail.
- **In-game snapshot.** The pilot migration covers `GuiDisplayGen.m`, the
  text drawing in `HeadUpDisplay.m`, the shape helpers in `OOOpenGL.m`, and
  the `GLDrawBallBillboard` callers. Its title-screen snapshot matches the
  unmigrated build within the measured noise floor: at most 1/255 outside
  the rotating ship and the version string, the same as two runs of the
  unmodified build. The game was run with `-novsync`, because a locked
  macOS screen otherwise blocks GL buffer swaps. Use `oogpu-imgdiff` to
  compare snapshots.

**Tooling.** `migrate_immediate.py <file> [first-last ...]` does the
mechanical conversion and lists anything it can't convert.

**Still to do.**
- Convert the remaining immediate-mode callers (the HUD, entities, debug
  drawing).
- Add render-state and pass objects (pipeline key: program, vertex layout,
  topology, blend, depth, cull, target formats).
- Express fixed-function state (lights, material, fog, texture combine) as
  plain data.
- Make uniforms go through programs by name.
- Expand wide lines and points on the CPU.
- Convert the vertex-array drawing code.

Broad in-game coverage needs scripted navigation of the GUI screens. A
Linux game build under Xvfb, driven by simulated keys, is the likely route.

## Reproducing

```bash
brew install glslang spirv-cross spirv-tools        # plus molten-vk vulkan-loader for Vulkan
meson setup build/sdl_gpu_spike tools/sdl_gpu_spike
meson compile -C build/sdl_gpu_spike

C=/tmp/oxp-corpus
python3 tools/sdl_gpu_spike/corpus/fetch.py $C                  # HTTP range requests: Shaders/ and Config/ only
python3 tools/sdl_gpu_spike/corpus/manifest.py $C $PWD tools/sdl_gpu_spike/corpus/ship-prefix.txt $C/corpus.tsv
build/sdl_gpu_spike/oogpu-check $C/corpus.tsv $C/check.log      # translate + spirv-val + pipeline
python3 tools/sdl_gpu_spike/corpus/sweep.py build/sdl_gpu_spike/oogpu-render $C/corpus.tsv $C/images \
    Resources/Textures/cobra3_redux.png 1 > $C/sweep.tsv        # GL vs SDL_GPU images, unset uniforms = 1
```

To run the Linux checks (Mesa lavapipe and llvmpipe), build
`tools/sdl_gpu_spike/linux/Dockerfile` and follow the instructions at the top
of `linux/run-tests.sh`. The manifests have to use the container's `/src` and
`/corpus` paths.

To use the Vulkan backend through MoltenVK, set `SDL_GPU_DRIVER=vulkan`,
`VK_ICD_FILENAMES=/opt/homebrew/etc/vulkan/icd.d/MoltenVK_icd.json` and
`SDL_VULKAN_LIBRARY=/opt/homebrew/lib/libvulkan.1.dylib`.

`oogpu-render` also runs on its own. For example, the built-in ship shader:

```bash
build/sdl_gpu_spike/oogpu-render -l 0.15 -p <prefix> -t uDiffuseMap=Resources/Textures/cobra3_redux.png \
    -i uGammaCorrect=1 Resources/Shaders/oolite-tangent-space-vertex.vertex \
    Resources/Shaders/oolite-default-shader.fragment /tmp/default
```

The tool writes `/tmp/default-gl.png` and `/tmp/default-gpu.png`, and prints
the difference between them.
