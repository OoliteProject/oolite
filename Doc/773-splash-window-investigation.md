# #773 (option 2): game window shows only the splash image

## Symptom
On Linux/X11, the game window is created but never shows game content. It keeps displaying the splash image
(or is blank). Oolite's own `rendering.opengl.state` checks flood `Latest.log` (about 83,000 lines in 20 s).
If a `SDL_GL_MakeCurrent` is added after the window is shown, the game segfaults in Mesa instead.

## Baseline
This is a bug in the real code, not in local modifications. The starting point is the committed
"Replace the splash window with a new game window on Linux (#773 option 2)" (`219824b78`) on top of
Oolite 1.93, with no local edits. Debugger and editor setup changes are unrelated and not covered here.

## What the committed code does
`-[MyOpenGLView endSplashScreen]` in `src/SDL/MyOpenGLView.m`:

1. Remember the splash window and set `window = NULL`.
2. `[self createWindowWithSize:firstScreen]` creates the new SDL window. `glContext` already exists, so this
   calls `SDL_GL_MakeCurrent(window, glContext)` instead of creating a context.
3. `SDL_DestroyWindow(splashWindow)`, then `SDL_ShowWindow(window)`.

The commit assumes the single `glContext` stays current across the swap. By then Universe has already created
its VAO, FBOs and shader programs (`initTargetFramebufferWithViewSize`) in that context.

## Finding the segfault
The "splash image only" symptom gives no stack, so I looked for something that fails loudly. Adding an explicit
`SDL_GL_MakeCurrent(window, glContext)` after `SDL_ShowWindow` made the game crash inside Mesa:

- Crash site: `glDrawElements` in `-[Universe drawTargetTextureIntoDefaultFramebuffer]` (Universe.m:658).
- Removing my extra call made the crash go away. That was misleading: GL was then running with no current
  context, so nothing drew and nothing crashed.

So the crash was only a symptom, and it showed that the draw uses objects the current context does not have.

## Instrumenting the GL context
To test that, I ran under gdb and, at fixed points, printed which context was current and whether Universe's
objects existed in it. This needs no SDL symbols because it only calls GL/GLX functions in the process:

- `glXGetCurrentContext()` to see which context is current.
- `glIsProgram(48)` and `glIsVertexArray(1)`, the program and VAO Universe uses for the final draw.
- `glGetError()` for pending errors.

Results:

| Point | Current context | program 48 / VAO 1 | `glGetError` |
|---|---|---|---|
| Start of `endSplashScreen` | context A | exist | none |
| After `createWindowWithSize:` | different context | do not exist | `GL_INVALID_FRAMEBUFFER_OPERATION` |
| `-nosplash` run (no window swap) | context A throughout | exist | none |

So the window swap changes the current context to one that has none of Universe's objects. Drawing with
objects missing explains both the blank window and the Mesa crash.

Note: gdb prints ObjC ivars (`self->window`, `self->glContext`) wrongly under the GNUstep non-fragile ABI (both
showed the same address), so I used locals and the calls above, not ivar values.

## Finding who creates the new context
`createWindowWithSize:` is supposed to reuse `glContext`, so something else created another one. I set a
breakpoint on `glXCreateContext` and took a backtrace:

```
glXCreateContext
libSDL3 (no symbols) x6
-[MyOpenGLView createWindowWithSize:]
-[MyOpenGLView endSplashScreen]
```

So SDL creates the context, from inside `createWindowWithSize:`, and Oolite never calls `SDL_GL_CreateContext`
there (the `glContext` branch calls `SDL_GL_MakeCurrent`). The SDL frames have no names, so I read the matching
SDL 3.4 source (`src/video/SDL_video.c`) for the calls `createWindowWithSize:` makes after window creation.
The one that matches is `SDL_GetWindowSurface(window)`, used to set the surface colorspace:

```
SDL_GetWindowSurface
  -> SDL_CreateWindowFramebuffer
       -> ShouldAttemptTextureFramebuffer()   // decided once (checked_texture_framebuffer)
       -> SDL_CreateWindowTexture()           // creates an SDL 2D renderer for the window
            -> the renderer creates its own GL context and makes it current
```

The renderer's context becomes current and replaces `glContext`. This explains why the first window was fine
and the second was not: SDL decides the texture-framebuffer path once, and later windows use it.

Confidence: the backtrace (SDL creating a context inside `createWindowWithSize:`) and the source agree, and
the fix below removes the problem. I did not step inside SDL to see the renderer being created, so the exact
path above is inference, not proof.

## The destroy question
The first fix attempt kept the splash window hidden, because I believed `SDL_DestroyWindow` destroys the
application's GL context. It does not. I traced the GLX calls made during `SDL_DestroyWindow(previousWindow)`:

1. `glXMakeCurrent(splash drawable, SDL's renderer context)`: SDL makes the splash window's own framebuffer
   renderer context current, so it can free its resources.
2. `glXMakeCurrent(NULL, NULL)`: SDL releases it.
3. `glXDestroyContext(SDL's renderer context)`: only SDL's context is destroyed. Our `glContext` is untouched.

Afterwards no context is current. `glXMakeCurrent` (and so `SDL_GL_MakeCurrent(window, context)`) binds a
drawable and a context to the thread together, and a context is not owned by a window. So the splash window can
be destroyed as the commit intends, as long as `glContext` is bound to the new window again afterwards.

## Fix (`src/SDL/MyOpenGLView.m`, +10 lines)
1. In `createWindowWithSize:`, after the `SDL_GetWindowSurface` / colorspace block, call
   `SDL_GL_MakeCurrent(window, glContext)` to undo the renderer's context.
2. In `endSplashScreen`, after `SDL_DestroyWindow(splashWindow)`, call `SDL_GL_MakeCurrent(window, glContext)`
   because the destroy leaves no context current.

## Verification
- Debug build, 15-25 s runs: no crash, 0 `Incorrect OpenGL state` lines in `~/.Oolite/Logs/Latest.log`.
- Screenshot: main menu and ship render in the new window.
- Control: destroying the splash without the second re-bind gave 83,195 state errors and a blank window.

## Not verified
- Only Linux/X11 with Mesa (Intel). Wayland/XWayland, NVIDIA, Windows and macOS were not run.
- The window-manager issues the commit addresses (Marco/Mutter borderless splash and focus) were not retested.
  The fix does not change the window creation order.
- An alternative is to avoid `SDL_GetWindowSurface` on an OpenGL window, but it sets the surface colorspace for
  HDR/SDR, so I left that alone.
