/*

OOOpenGLExtensionManager+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-z1s4): the Objective-C OOOpenGLExtensionManager, a
facade over the C++ cxx::OOOpenGLExtensionManager (OOOpenGLExtensionManager.h), for callers that
are not converted yet. Its interface is the one OOOpenGLExtensionManager.h declared before the
conversion, copied exactly (same selectors, same types), so those callers compile and behave
unchanged; each method forwards to its C++ member. Imported as the last line of
OOOpenGLExtensionManager.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      [OOOpenGLExtensionManager sharedManager]   nothing
        converted (C++)                        cxx::OOOpenGLExtensionManager::sharedManager()   nothing

The manager is a singleton: +sharedManager answers one facade for the life of the process, as it
answered one object before (proposed ADR-0056 amendment oo-r7m0, item 5). oo::ToObjC/oo::ToCxx
cross as for any facade. Never add to this file; converted code does not message the facade.
Deleted by its deletion bead once no file outside OOOpenGLExtensionManager.* names the
Objective-C class.


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

#ifndef OOOPENGLEXTENSIONMANAGER_OBJCBRIDGE_H
#define OOOPENGLEXTENSIONMANAGER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOOpenGLExtensionManager : OOObject {
@private
    oo::Ref<cxx::OOOpenGLExtensionManager> _cxxManager;
}

+ (OOOpenGLExtensionManager*)sharedManager;

- (void)reset;

- (BOOL)haveExtension:(const std::string&)extension;

- (BOOL)shadersSupported;
- (BOOL)shadersForceDisabled;
- (OOGraphicsDetail)defaultDetailLevel;
- (OOGraphicsDetail)maximumDetailLevel;
- (GLint)textureImageUnitCount; // Fragment shader sampler count limit. Does not apply to fixed function multitexturing. (GL_MAX_TEXTURE_IMAGE_UNITS_ARB)

- (BOOL)vboSupported; // Vertex buffer objects
- (BOOL)fboSupported; // Frame buffer objects
- (BOOL)textureCombinersSupported;
- (GLint)textureUnitCount; // Fixed function multitexture limit, does not apply to shaders. (GL_MAX_TEXTURE_UNITS_ARB)

- (NSUInteger)majorVersionNumber;
- (NSUInteger)minorVersionNumber;
- (NSUInteger)releaseVersionNumber;
- (void)getVersionMajor:(unsigned*)outMajor minor:(unsigned*)outMinor release:(unsigned*)outRelease;
- (BOOL)versionIsAtLeastMajor:(unsigned)maj minor:(unsigned)min;

- (std::optional<std::string>)vendorString;
- (std::optional<std::string>)rendererString;

//	GL_POINT_SMOOTH is slow or non-functional on some GPUs.
- (BOOL)usePointSmoothing;
- (BOOL)useLineSmoothing;

// Using vertex shader for dust transformation is counterproductive on systems which run vertex shaders on the CPU.
- (BOOL)useDustShader;

@end

namespace oo {

// The manager's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOOpenGLExtensionManager* ToObjC(cxx::OOOpenGLExtensionManager* manager);

// The C++ manager behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOOpenGLExtensionManager* ToCxx(OOOpenGLExtensionManager* manager);

} // namespace oo

#endif // OOOPENGLEXTENSIONMANAGER_OBJCBRIDGE_H
