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
  wide lines and points.
  - **Results:** all 42 cases match on Apple's GL (max difference 0) and on
    Mesa's llvmpipe. That's 40 drawing cases plus 2 interop checks. As a
    negative control, swapping the quad diagonal makes all four quad cases
    fail.
  - **One driver difference:** for smooth-shaded quads, Apple splits along
    the 1-3 diagonal and Mesa along 0-2. GL leaves the diagonal to the
    implementation, so the test accepts either for that case and labels it
    `OK02`.
  - **Cost:** `--bench` times text-like batches in an optimised (`-O2`)
    build on Apple GL. A batch costs 0.57 µs, against 0.26 µs for GL
    immediate mode; the GL interop layer is 0.06 µs of that. For a HUD with
    500 batches that adds about 0.15 ms per frame. The interop layer leaves
    GL alone inside a batch, and syncs once at the end.
- **`audit_immediate.py`.** Mixing the two APIs fails silently, because
  batches often span functions: a helper emits vertices and its caller
  opens the batch. The script finds every function that emits vertices
  without opening its own batch. It reports any batch of one API that calls
  an emitter of the other. The pilot is clean, and planting a raw `glBegin`
  around a `GLDrawBallBillboard` call is caught.
- **In-game snapshot.** The pilot migration covers `GuiDisplayGen.m`, the
  text drawing in `HeadUpDisplay.m`, the shape helpers in `OOOpenGL.m`, and
  the `GLDrawBallBillboard` callers. Its title-screen snapshot matches the
  unmigrated build within the measured noise floor: at most 1/255 outside
  the rotating ship and the version string, the same as two runs of the
  unmodified build. The game was run with `-novsync`, because a locked
  macOS screen otherwise blocks GL buffer swaps. Use `oogpu-imgdiff` to
  compare snapshots.

**Tooling.** `migrate_immediate.py <file> [first-last ...]` does the
mechanical conversion and lists anything it can't convert. Run
`audit_immediate.py` after each migration.

**Explicit draw state** (`OORenderState.h`). Migrated code brackets its
drawing with `OORendererPushDrawState()` and `OORendererPopDrawState()`.
- **What the state covers:**
  - blend mode, depth test and write, and culling (the SDL_GPU pipeline key);
  - lighting, texturing and fog, which select the fixed-function emulation
    under SDL_GPU;
  - the texture on unit 0, whose options give the SDL_GPU sampler;
  - the scissor rect.
- **How the GL backend applies it:** a push saves the GL state these fields
  cover and applies the new values; a pop restores exactly what was there.
  Migrated and legacy code therefore can't disturb each other.
- **Verification:** debug builds check at every batch that GL still matches
  the pushed state, and log the first time each field differs. The legacy
  `OOSetOpenGLState` debug verifier repairs state silently at preset
  switches, so the renderer's check sits right at the draw.

**Pilot status.** The GUI (`drawGUI`, and the star chart's scissor as a
nested state) and the HUD text functions now draw only with pushed state.
Text inherits the enclosing scissor, so system names stay clipped to the
chart.

**Checks.**
- `oogpu-immediate-test` adds three cases, and all 45 pass on Apple's GL and
  on Mesa:
  - a pushed overlay state with texture and scissor draws exactly like the
    equivalent raw GL;
  - popping restores deliberately unusual previous state;
  - a raw GL change inside a pushed state is reported.
- The title-screen snapshot still matches the noise floor, with no renderer
  warnings.
- As an in-game negative control, a raw `glDisable(GL_BLEND)` inside the
  text scope is logged.

**Rest of phase 1, one commit each.** Each is checked against the frozen
title screen (below), and each has a negative control: a deliberate error
that must change the screenshot.
- **Uniforms** go through `OOShaderProgram` by handle, a location on GL
  and an index into the reflected layout under SDL_GPU. `OOShaderUniform`
  and the standard matrices use it. Control: halving float uniforms
  changes 2% of pixels.
- **Lights, material and fog as data** (`OOFixedFunction.h`). Light
  positions are converted to eye space at the call, as GL does, using the
  manager's modelview. In the harness, GL ends up with exactly the legacy
  values. All `glLight`/`glMaterial` callers are converted; the fog
  callers are left for phase 2 (no testable screen uses fog). Control: a
  nudged light changes the ship.
- **Vertex arrays** (`OOVertexArray.h`): renderer buffers created once,
  plus a per-draw layout. `OOMesh`, which draws every ship, uses them; GL
  still draws from client memory. Control: dropping normals changes 3% of
  pixels.
- **Passes and readback** (`OORenderPass.h`):
  - the main frame is a scene pass, with a new pass for each depth range
    and a HUD pass when the HUD is drawn separately;
  - the clear colour and depth are renderer state, so the frame keeps
    clearing with the previous frame's colour;
  - the snapshot reads back through the renderer.

  Control: a different GUI clear colour changes 95% of pixels.
- **Line width and point size** are per-batch immediate-mode state.
  `OOExpandLinesToTriangles` and `OOExpandPointsToTriangles` produce the
  triangles SDL_GPU will draw. Without smoothing they overlap GL's own
  output by at least 0.999 on Apple's GL and on Mesa; a wrong offset rule
  scores 0.98, under the 0.995 threshold. The game still draws natively.

**Reproducible title screen.** In debug builds, `OO_FREEZE_DEMO_SHIPS`
stops the demo ship rotating. `game-snapshot.py` sets it and pins the mouse
pointer, because the GUI cursor follows it. Two runs then differ by at most
1/255 over the whole screen, including the lit, textured, shader-drawn
ship. The hook is worth keeping upstream for tests.

**Left for phase 2** (no API changes needed):
- **Remaining passes:** the post-processing chain and environment cube
  maps, and the splash and fallback clears.
- **Fixed-function state:** fog callers, point sprites, texture combine
  modes beyond the pilot's, and `GL_LIGHT_MODEL_COLOR_CONTROL` (separate
  specular, which the emulation shader must reproduce).
- **Migration:** the remaining immediate-mode and vertex-array callers
  (HUD, entities, planets, particles, debug drawing). Use the migration
  scripts and `audit_immediate.py`.
- **Not verified in-game:** the flight HUD, planets, the sun and fog are
  only covered by the harness.
- **Windows** builds are untested; the C backend declares the extension
  manager's function pointers by name.

Broad in-game coverage needs scripted navigation of the GUI screens. A
Linux game build under Xvfb, driven by simulated keys, is the likely route.

## Phase 2: migrating the call sites

Phase 2 moves the game onto the renderer layer, still on OpenGL, one area
per commit.

**In-game regression scenario.** `scenarios/RenderTest.oxp` with
`game-snapshot.py --scenario` takes 17 screenshots:
- title and new game;
- status, manifest, both charts, system data and market;
- flight: forward twice, then the aft, port and starboard views;
- a ship spawned ahead, lasers fired at it, its explosion and the debris.

Debug builds make these reproducible:
- `OO_DETERMINISTIC_TEST` fixes the game tick at 1/60 s, holds time on the
  title screens, and seeds the random number generators;
- the OXP seeds `Math.random`, times its steps from `startUpComplete`, and
  gives Lave a fixed planet texture, because procedural texture
  generation races;
- `console.simulateKey()` presses keys.

Two runs of the same build match exactly, except for one 6x3 patch on the
spawned ship (a light flasher) in the ship and lasers frames, which varies
by up to 22/255 between runs. The check masks only that patch.

**Done** (each commit checked on all 17 screens, the immediate-mode audit,
the harness on Apple's GL and on Mesa, and a deployment build):
- **Immediate mode:** every `glBegin`/`glEnd` caller (HUD, GUI, entities,
  planets, particles, debug drawing) uses `OOImmediate`, and
  `audit_immediate.py` finds no raw GL emitters. Batches with the light
  particles change 10-20 pixels by rounding in triangle setup; restoring
  the raw-GL file removes the difference.
- **Vertex arrays:** every client-array draw goes through
  `OORendererDrawArrays`, `OORendererDrawElements` or, for quads and fans,
  `OORendererDrawPrimitive`/`OORendererDrawPrimitiveElements`, which
  expand them into triangle indices. Transient data uses a ring of upload
  buffers. Display lists are gone (sky, mesh).
- **State machine** (`OORenderStateMachine.h`, `OOGLStateCompat.h`). The
  renderer keeps its own copy of the GL state that legacy code sets one
  call at a time: capabilities, lights, blend, depth, culling, shading,
  polygon mode, scissor, per-unit texture enables, bindings, environment
  mode and LOD bias, and the program. `OOGLEnable`, `OOGLBindTexture` and
  the other wrappers record each change and then make the GL call;
  `migrate_state.py` moved every caller onto them, `OOSetOpenGLState`
  included. `glPushAttrib`/`glPopAttrib` groups are mirrored too. The
  SDL_GPU backend will build pipelines, fixed-function emulation and
  bindings from this copy. With `OO_VERIFY_RENDER_STATE=1`, debug builds
  compare GL with the copy at every draw: all 17 screens are clean, and a
  planted raw `glDisable(GL_BLEND)` is reported.
- **Fog** is set only through `OORendererSetFog*`.
- **Textures** (`OORendererTexture.h`). Textures are created from a
  descriptor (size, cube flag, mip level count, RGBA8/Gray8/Alpha8/
  GrayAlpha8, sRGB, sampler settings), then uploaded and read back one
  face and level at a time. The GL backend now uploads tightly packed
  rows. GL's default 4-byte alignment had been misreading the narrowest
  mipmap levels of one- and two-channel textures, which changes 6 pixels
  in two frames. Harness cases round-trip every format, level and cube
  face, and fail without that fix.

- **Render targets and passes** (`OORenderPass.h`). Render targets have
  RGBA16F colour attachments (up to two), an optional float depth buffer
  and 1 or 4 samples. They can be resized, their attachments are looked up
  as textures, and an explicit resolve handles MSAA, which SDL_GPU does as
  a store op. Universe's MSAA, scene, passthrough and ping-pong
  framebuffers are render targets now. The post chain runs as passes (the
  window cleared, the passthrough cleared, the blur iterations
  don't-care, then the composite), and its quad draws from renderer
  buffers on generic attributes 0 and 1. The splash screen and the early
  clears also go through the renderer. Harness cases: a 4x resolve with
  partial edge coverage, an MRT clear, resizing and bindings, on Apple's
  GL and on Mesa (which takes the multisample-texture path).
- **Fixed-function extras:** separate specular
  (`OORendererSetLightModelSeparateSpecular`), and the per-unit
  `GL_COMBINE_RGB` op that `OOMultiTextureMaterial` sets.
- **Uniforms** in the post chain are set by handle through
  `OOShaderProgram`.

**Variant runs.** The default settings never reach MSAA, the post effects
that draw the HUD with the scene, the no-bloom path or the no-shader path.
`OO_SNAPSHOT_ARGS` passes launch arguments, which Foundation reads as
defaults for that run only, so each branch is also run against its own
baseline: `-anti-aliasing YES`, `oolite.postFX = 5;` (grayscale) as a
console command, `-detailLevel 2` and `-detailLevel 1`. Two runs of the
same build match within 6/255 (MSAA), 3, 1 and 0 respectively.

**Left as they are, for phase 3:**
- `OOShaderProgram` still compiles and links through GL. The SDL_GPU
  backend replaces it with the translator from phase 0.
- Native wide lines and points: the GL backend relies on the
  `glLineWidth`/`glPointSize` calls in `GLScaledLineWidth` and
  `GLScaledPointSize`. SDL_GPU will use the CPU expansion.
- The fog hints, client-texture selection in `OOMesh` and the legacy state
  manager's client-array presets only matter to GL.
- Snapshot readback chooses `glReadBuffer` directly; under SDL_GPU it
  becomes a swapchain texture download.
- `OOEnvironmentCubeMap` is an unbuilt upstream prototype (it isn't in
  any `meson.build`, and it doesn't compile); it is left alone.
- The Windows-only HDR uniforms and the backend's Windows function
  pointer declarations have not been built.

## Phase 3: the SDL_GPU backend

**Groundwork on GL** (in the game, checked with the 17-screen scenario and
its variants):
- The state verifier covers every mirrored field on every texture unit:
  caps, lights, both blend factors, depth function, culling, front face,
  shading, polygon mode, scissor, program, texture enables and bindings,
  environment mode and colour, combine op and LOD bias. Seven planted raw
  GL changes are each reported.
- The mirror also holds the modelview and projection as last synced to GL,
  and the viewport, with the verifier checking all three; a planted
  glViewport, glScalef and glTranslatef are each caught.
- Every GL state read left in game code is a startup query of device limits
  or debug-only dumping.

**First backend slice** (`OORendererSDLGPU.c`, spike build only). It
implements `OORendererBackend.h` on SDL_GPU from the state mirror and the
fixed-function values, drawing with the translator's own fixed-function
emulation shaders.
- **Recording.** SDL_GPU can't start a copy pass inside a render pass,
  while Oolite makes vertex data and uploads textures mid-frame. So each
  pass's draws are recorded (vertices into a CPU arena, de-indexed into
  lists, plus a uniform snapshot and pipeline key), and at the end of the
  pass one copy pass uploads everything before the draws are replayed.
- **Conventions:**
  - the translator remaps clip-space depth;
  - pipelines turn depth clipping on, because SDL_GPU clamps by default
    and would draw geometry in front of the near plane that GL clips;
  - viewport, scissor and readback are flipped between the two origins;
  - flat shading uses GL's last vertex;
  - luminance and alpha textures are expanded to RGBA on upload.

**Checking it.** `oogpu-backend-test.c` draws nine scenes through the
renderer API only: smooth, flat, blending, depth (including the near
plane), culling, textures, indexed arrays, lighting, and scissor inside an
off-centre viewport. It is built against both backends, and
`oogpu-backend-compare.py` compares the results: a scene passes when at
most 0.5% of pixels differ by more than 16/255 and the mean difference is
at most 1/255. All nine pass on Metal against Apple's GL, and on lavapipe
Vulkan against llvmpipe GL. `OO_BACKEND_FAULT` and `OO_TRANSLATOR_FAULT`
plant one fault each (blend factor, winding, depth test, flat shading,
texture, origin, depth clamping, depth remap), and every one fails only
the scenes it should, on both platforms. Two scenes first missed their
faults: a depth scene with all its geometry beyond the near plane can't
see the depth remap, and a viewport centred vertically can't see the
origin flip. Both scenes were changed until their faults showed.

```bash
build/sdl_gpu_spike/oogpu-backend-test-gl out/gl
build/sdl_gpu_spike/oogpu-backend-test-gpu out/gpu
tools/sdl_gpu_spike/oogpu-backend-compare.py out/gl out/gpu
```

**Orientation.** A target SDL_GPU draws into the usual way, then sampled
with GL texture co-ordinates, comes out upside down. With
`kOOGLSLOutputGLOrientation` the translator negates clip-space y in every
vertex shader, next to the depth remap, and leaves gl_FragCoord unflipped.
That also covers shaders that don't use the matrices, like the
post-processing quad. The backend draws that way with its front face
inverted, so every target holds GL's bottom-up rows, as uploaded textures
do. Viewports, scissor rectangles and readback use GL co-ordinates
unchanged; only presenting to a window will flip.

**Render targets** in the backend: RGBA16F colour (sampleable, so draw
states can bind it), float depth and 4x MSAA. A resize recreates the
textures under the same handles, and the resolve is an empty pass with a
resolve store op. Scenes render into a target, a resolved MSAA target and
a two-attachment target, then sample them in the window.

**Programs** (`OORendererProgram.h`): create from legacy GLSL, a prefix and
attribute bindings; use; uniforms by handle; samplers by texture unit.
- The GL backend compiles exactly as `OOShaderProgram` did.
- `OOShaderProgram` now goes through the API, so every material and OXP
  shader is backend-neutral. In the game this matches all baselines; a
  broken shader logs the same failure message as before, and dropping
  mat4 uniforms changes the ship frame.
- On SDL_GPU, the translator's reflection gives a per-program uniform
  table. Values persist per program, as in GL, and are snapshotted at each
  draw. An unbound sampler reads black, as GL's incomplete texture does,
  and the bound "tangent" attribute is fed from its vertex stream.
- Known difference: the translator compiles and links both stages
  together, so on SDL_GPU every shader failure is logged as "shader program
  linking failed", where GL names the failing stage. The log underneath is
  the compiler's, with the stage's line numbers.

**Fixed function and wide primitives.**
- The emulation adds separate specular after texturing, as Oolite always
  asks, and applies linear, exp and exp2 fog.
- Points, and lines wider than a pixel, are expanded on the CPU and drawn
  with identity matrices. This matches Apple's GL exactly and llvmpipe
  within 0.21% of pixels.
- A lesson from the specular scene: both spheres were wound inside out,
  and since the two backends agreed, only the undetected control showed
  it.

16 scenes now match GL on Metal and on lavapipe Vulkan, and 16 planted
faults (14 in the backend, 2 in the translator) each fail only their
scenes.

**Game code is backend-neutral.** The post chain binds renderer programs.
GL's context housekeeping now lives in the GL backend: snapshot read
buffer and alignment, finish and flush, the fog hint, colour clamping for
float targets, and the texture limits. What's left in game code is the
extension manager's start-up probing, and debug-only state dumps and
checks.

**CI.** The branch was pushed to the fork on 2026-10-21, with the user's
agreement, to get Windows builds.
- Linux (Arch, Ubuntu, Fedora; dev, test, deployment) and macOS built and
  passed. A local Arch build of dev and deployment passed too.
- Windows found two problems: `srandom`, which MinGW lacks, in the
  deterministic-test seed; and the SDL header added to `OOJSConsole.m`
  for `console.simulateKey`, which clashed with `intrin.h` after Oolite's
  headers. Both are fixed.
- Every push publishes a prerelease on the fork, from the release job.

**Frames in flight and readback.** Passes are submitted without waiting;
only readback waits. Texture readback works on SDL_GPU, and the backend
test round-trips every format, level and cube face on both backends.

**Next:**
- **Needs a decision:** moving the translator and backend into
  `src/Core/Renderer` makes glslang and SPIRV-Cross game dependencies,
  which probably means bundling them (Debian's glslang is too old), and
  that affects CI and packaging on every platform. After that: a build
  option that selects the backend, a swapchain with the final flip, and
  the 17-screen scenario on SDL_GPU.
- Frames in flight instead of waiting after each pass; device limits in
  place of the GL queries.
- Multitexture combine and texture environment modes other than
  modulate, which only the no-shader detail level uses. Whether that
  level survives on SDL_GPU, where everything is a shader anyway, is a
  maintainer question.

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
