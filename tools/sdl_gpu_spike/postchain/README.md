The game's post-processing shaders (`Resources/Shaders/oolite-texture`,
`oolite-blur` and `oolite-final`) as the game hands them to the renderer:
with their prefix, after `OOShaderProgram` has rewritten GLSL 3.30 to 1.20
(see `TranslateGLSL330To120`). Their attribute bindings are aPos = 0 and
aTexCoords = 1 (blur, final), and vert_position = 0 and
texture_coordinate = 1 (texture). `oogpu-backend-test` runs the chain
from these. `oolite-final-hdr.fragment` is the HDR build of the final
pass, compiled by oogpu-hlsl-check. Regenerate them when the shaders or
the rewrite change.
