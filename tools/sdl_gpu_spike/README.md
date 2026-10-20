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
expansion catalog translates and builds an SDL_GPU pipeline on both the Metal
and Vulkan backends. Every program OpenGL can render produces the same image
after translation, apart from GPU noise and undefined behaviour (both
explained below).

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
  programs. 25 configured pairs name files that exist in no catalog OXP, so they can't be tested.

| Check | Metal | Vulkan (MoltenVK) |
|---|---|---|
| Translate, validate SPIR-V (`spirv-val`, Vulkan 1.0), create SDL_GPU shaders and pipeline: built-in | 18/18 | 18/18 |
| Same, configured OXP programs | 392/392 | 392/392 |
| Same, unconfigured OXP files | 52/52 | 52/52 |
| Rendered image identical to OpenGL¹, configured programs, unset uniforms = 0.5 | 315/338 | 315/338 |
| Same, unset uniforms = 1 (exercises `int`/`bool` branches) | 337/338 | 337/338 |
| Either value, with the shaders' `fract(sin(x) * 43758.5453)` hash neutralised | 338/338 | 338/338 |
| Rendered image identical to OpenGL¹, unconfigured files | 14/22 | not run |

¹ At most 2/255 per channel on more than 99.5% of pixels, and a mean
difference below 0.5/255.

- **Hash noise accounts for every image difference in configured programs**:
  23 at 0.5, 1 at 1. All of these are Griff-family engine and hull shaders
  that use a `sin()`-based hash, thresholded to on/off, for engine flicker.
  Tiny differences in `sin()` precision between Apple's GL and Metal flip
  individual pixels. Other GL drivers would be expected to differ in the same
  way, but that wasn't measured. With the hash constant replaced, all of them
  match (at most a few pixels off by 10/255 at the threshold).
- **The 8 unconfigured-file differences are undefined behaviour.** Each is a
  vertex shader whose fragment shader couldn't be paired by name, so it ran
  against the fixed-function fragment stage. None of these vertex shaders
  write `gl_FrontColor`, which makes GL's output undefined; the translator
  defaults it to white. These pairings never occur in the game.
- **No OpenGL reference for 7 configured programs and 30 unconfigured pairs,**
  because Apple's GL 2.1 compiler rejects them. The configured 7 use
  constructor-style array initialisers, a fragment input the vertex shader
  never writes, and other syntax that NVIDIA's driver accepts. The translator
  compiles all of them, but whether their output is right is unverified.
- **The Vulkan column is not an independent driver test.** MoltenVK converts
  the SPIR-V to MSL with SPIRV-Cross and runs it on Metal, which is also what
  Apple's GL runs on. The column shows that the SPIR-V and SDL's Vulkan
  descriptor-set conventions are correct. It says nothing about real Vulkan
  drivers (Mesa, NVIDIA, AMD).
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
  Tested only with Homebrew's glslang 16.6.0 and SPIRV-Cross 1.4.363.0;
  packaging on MSYS2 and the Linux distributions hasn't been checked yet.
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
