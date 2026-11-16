/*

OOOpenGLExtensionManager.h

Handles checking for and using OpenGL extensions and related information.

This is thread safe, except for initialization; that is, sharedManager() should
be called from the main thread at an early point. The OpenGL context must be
set up by then.

C++20 since bead oo-z1s4 (proposed ADR-0056). The class is cxx::OOOpenGLExtensionManager while
OOOpenGLExtensionManager+ObjCBridge.h, imported at the end of this header, keeps the Objective-C
OOOpenGLExtensionManager its unconverted callers message; the bridge's deletion bead moves it out
of namespace cxx.


Copyright (C) 2007-2013 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#pragma once

#ifndef OOOPENGLEXTENSIONMANAGER_H
#define OOOPENGLEXTENSIONMANAGER_H

#import "OOFoundation.h"
#import "OOFunctionAttributes.h"
#import "OOOpenGL.h"
#import "OOTypes.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

// The OpenGL feature switches and the Windows extension function pointers (bead oo-9ht.120).
#include "OOOpenGLExtensionPointers.h"

#define OOOPENGLEXTMGR_LOCK_SET_ACCESS (!OOLITE_MAC_COCOA_UI)

namespace cxx {

class OOOpenGLExtensionManager : public oo::RefCounted {
public:
    /*	The shared manager, made (and reset()) on first use; borrowed, never released (proposed
            ADR-0056 amendment oo-r7m0). NOTE: assumes single-threaded first access.
    */
    static OOOpenGLExtensionManager* sharedManager();

    ~OOOpenGLExtensionManager();

    void reset();

    bool haveExtension(const std::string& extension);

    bool shadersSupported();
    bool shadersForceDisabled();
    OOGraphicsDetail defaultDetailLevel();
    OOGraphicsDetail maximumDetailLevel();
    GLint textureImageUnitCount(); // Fragment shader sampler count limit. Does not apply to fixed function multitexturing. (GL_MAX_TEXTURE_IMAGE_UNITS_ARB)

    bool vboSupported(); // Vertex buffer objects
    bool fboSupported(); // Frame buffer objects
    bool textureCombinersSupported();
    GLint textureUnitCount(); // Fixed function multitexture limit, does not apply to shaders. (GL_MAX_TEXTURE_UNITS_ARB)

    NSUInteger majorVersionNumber();
    NSUInteger minorVersionNumber();
    NSUInteger releaseVersionNumber();
    void getVersionMajor(unsigned* outMajor, unsigned* outMinor, unsigned* outRelease);
    bool versionIsAtLeastMajor(unsigned maj, unsigned min);

    std::optional<std::string> vendorString();
    std::optional<std::string> rendererString();

    //	GL_POINT_SMOOTH is slow or non-functional on some GPUs.
    bool usePointSmoothing();
    bool useLineSmoothing();

    // Using vertex shader for dust transformation is counterproductive on systems which run vertex shaders on the CPU.
    bool useDustShader();

private:
#if OO_SHADERS
    void checkShadersSupported();
#endif

#if OO_USE_VBO
    void checkVBOSupported();
#endif

#if OO_USE_FBO
    void checkFBOSupported();
#endif

#if GL_ARB_texture_env_combine
    void checkTextureCombinersSupported();
#endif

    oo::PList lookUpPerGPUSettingsWithVersionString(const std::optional<std::string>& version, const std::optional<std::string>& extensionsStr);

    // An ivar that shares its name with a member function (its own or oo::RefCounted's) has the
    // suffix _ (proposed ADR-0056 amendment oo-z1s4).
#if OOOPENGLEXTMGR_LOCK_SET_ACCESS
    std::mutex lock = { };
#endif
    // Foundation sweep (proposed ADR-0043, bead oo-fzwt): the extension names, and the vendor /
    // renderer strings (nullopt where OpenGL answered NULL, as the strings were nil).
    std::set<std::string> extensions = { };

    std::optional<std::string> vendor = { };
    std::optional<std::string> renderer = { };

    unsigned major = { }, minor = { }, release_ = { }; // _: oo::RefCounted has a release()

    bool usePointSmoothing_ = { };
    bool useLineSmoothing_ = { };
    bool useDustShader_ = { };

#if OO_SHADERS
    bool shadersAvailable = { };
    bool shadersForceDisabled_ = { };
    OOShaderSetting defaultShaderSetting = { };
    OOShaderSetting maximumShaderSetting = { };
    GLint textureImageUnitCount_ = { };
#endif
#if OO_USE_VBO
    bool vboSupported_ = { };
#endif
#if OO_USE_FBO
    bool fboSupported_ = { };
#endif
#if OO_MULTITEXTURE
    bool textureCombinersSupported_ = { };
    GLint textureUnitCount_ = { };
#endif
};

} // namespace cxx

OOINLINE BOOL OOShadersSupported(void) INLINE_PURE_FUNC;
OOINLINE BOOL OOShadersSupported(void)
{
    return cxx::OOOpenGLExtensionManager::sharedManager()->shadersSupported();
}

// Transitional: the Objective-C OOOpenGLExtensionManager, for callers not yet converted. Deleted,
// with namespace cxx above, by the bridge's deletion bead.
#import "OOOpenGLExtensionManager+ObjCBridge.h"

#endif // OOOPENGLEXTENSIONMANAGER_H
