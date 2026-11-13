/*

OOOpenGLExtensionManager.m

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

#include "OOOpenGLExtensionManager.h"

#include <stdlib.h>

#include <array>
#include <string_view>

#include "OOConstToString.h"
#include "OOFunctionAttributes.h"
#include "OOLogging.h"
#include "OORegExpMatcher.h"
#include "ResourceManager.h"
#include "oofnd/Log.hpp"
#include "oofnd/Process.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"

/*	OpenGL version required, currently 1.1 or later (basic stuff like
        glBindTexture(), glDrawArrays()). We probably have implicit requirements
        for later versions, but I don't feel like auditing.
        -- Ahruman
        We need at least 3.0 for the Frame Buffer Objects now in use. Might as
        well go all the way to 3.3.
        -- Nikos 20220817
*/
constexpr int kMinMajorVersion = 3;
constexpr int kMinMinorVersion = 3;

#if OOLITE_WINDOWS
/*	Define the function pointers for the OpenGL extensions used in the game
        (required for Windows only).
*/
static void OOBadOpenGLExtensionUsed(void) GCC_ATTR((noreturn, used));

#if OO_SHADERS

PFNGLUSEPROGRAMOBJECTARBPROC glUseProgramObjectARB =
    reinterpret_cast<PFNGLUSEPROGRAMOBJECTARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLGETUNIFORMLOCATIONARBPROC glGetUniformLocationARB =
    reinterpret_cast<PFNGLGETUNIFORMLOCATIONARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLUNIFORM1IARBPROC glUniform1iARB =
    reinterpret_cast<PFNGLUNIFORM1IARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLUNIFORM1FARBPROC glUniform1fARB =
    reinterpret_cast<PFNGLUNIFORM1FARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLUNIFORMMATRIX3FVARBPROC glUniformMatrix3fvARB =
    reinterpret_cast<PFNGLUNIFORMMATRIX3FVARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLUNIFORMMATRIX4FVARBPROC glUniformMatrix4fvARB =
    reinterpret_cast<PFNGLUNIFORMMATRIX4FVARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLUNIFORM4FVARBPROC glUniform4fvARB =
    reinterpret_cast<PFNGLUNIFORM4FVARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLGETOBJECTPARAMETERIVARBPROC glGetObjectParameterivARB =
    reinterpret_cast<PFNGLGETOBJECTPARAMETERIVARBPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLCREATESHADEROBJECTARBPROC glCreateShaderObjectARB =
    reinterpret_cast<PFNGLCREATESHADEROBJECTARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLGETINFOLOGARBPROC glGetInfoLogARB =
    reinterpret_cast<PFNGLGETINFOLOGARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLCREATEPROGRAMOBJECTARBPROC glCreateProgramObjectARB =
    reinterpret_cast<PFNGLCREATEPROGRAMOBJECTARBPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLATTACHOBJECTARBPROC glAttachObjectARB =
    reinterpret_cast<PFNGLATTACHOBJECTARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLDELETEOBJECTARBPROC glDeleteObjectARB =
    reinterpret_cast<PFNGLDELETEOBJECTARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLLINKPROGRAMARBPROC glLinkProgramARB =
    reinterpret_cast<PFNGLLINKPROGRAMARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLCOMPILESHADERARBPROC glCompileShaderARB =
    reinterpret_cast<PFNGLCOMPILESHADERARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLSHADERSOURCEARBPROC glShaderSourceARB =
    reinterpret_cast<PFNGLSHADERSOURCEARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLUNIFORM2FVARBPROC glUniform2fvARB =
    reinterpret_cast<PFNGLUNIFORM2FVARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBINDATTRIBLOCATIONARBPROC glBindAttribLocationARB =
    reinterpret_cast<PFNGLBINDATTRIBLOCATIONARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLENABLEVERTEXATTRIBARRAYARBPROC glEnableVertexAttribArrayARB =
    reinterpret_cast<PFNGLENABLEVERTEXATTRIBARRAYARBPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLVERTEXATTRIBPOINTERARBPROC glVertexAttribPointerARB =
    reinterpret_cast<PFNGLVERTEXATTRIBPOINTERARBPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLDISABLEVERTEXATTRIBARRAYARBPROC glDisableVertexAttribArrayARB =
    reinterpret_cast<PFNGLDISABLEVERTEXATTRIBARRAYARBPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLVALIDATEPROGRAMARBPROC glValidateProgramARB =
    reinterpret_cast<PFNGLVALIDATEPROGRAMARBPROC>(&OOBadOpenGLExtensionUsed);
#endif

#if OO_SHADERS || OO_MULTITEXTURE
PFNGLACTIVETEXTUREARBPROC glActiveTextureARB =
    reinterpret_cast<PFNGLACTIVETEXTUREARBPROC>(&OOBadOpenGLExtensionUsed);
#endif

#if OO_MULTITEXTURE
PFNGLCLIENTACTIVETEXTUREARBPROC glClientActiveTextureARB =
    reinterpret_cast<PFNGLCLIENTACTIVETEXTUREARBPROC>(
        &OOBadOpenGLExtensionUsed);
#endif

#if OO_USE_VBO
PFNGLGENBUFFERSARBPROC glGenBuffersARB =
    reinterpret_cast<PFNGLGENBUFFERSARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLDELETEBUFFERSARBPROC glDeleteBuffersARB =
    reinterpret_cast<PFNGLDELETEBUFFERSARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBINDBUFFERARBPROC glBindBufferARB =
    reinterpret_cast<PFNGLBINDBUFFERARBPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBUFFERDATAARBPROC glBufferDataARB =
    reinterpret_cast<PFNGLBUFFERDATAARBPROC>(&OOBadOpenGLExtensionUsed);
#endif

#if OO_USE_FBO
PFNGLGENFRAMEBUFFERSEXTPROC glGenFramebuffersEXT =
    reinterpret_cast<PFNGLGENFRAMEBUFFERSEXTPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBINDFRAMEBUFFEREXTPROC glBindFramebufferEXT =
    reinterpret_cast<PFNGLBINDFRAMEBUFFEREXTPROC>(&OOBadOpenGLExtensionUsed);
PFNGLGENRENDERBUFFERSEXTPROC glGenRenderbuffersEXT =
    reinterpret_cast<PFNGLGENRENDERBUFFERSEXTPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBINDRENDERBUFFEREXTPROC glBindRenderbufferEXT =
    reinterpret_cast<PFNGLBINDRENDERBUFFEREXTPROC>(&OOBadOpenGLExtensionUsed);
PFNGLRENDERBUFFERSTORAGEEXTPROC glRenderbufferStorageEXT =
    reinterpret_cast<PFNGLRENDERBUFFERSTORAGEEXTPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC glFramebufferRenderbufferEXT =
    reinterpret_cast<PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLFRAMEBUFFERTEXTURE2DEXTPROC glFramebufferTexture2DEXT =
    reinterpret_cast<PFNGLFRAMEBUFFERTEXTURE2DEXTPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC glCheckFramebufferStatusEXT =
    reinterpret_cast<PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLDELETEFRAMEBUFFERSEXTPROC glDeleteFramebuffersEXT =
    reinterpret_cast<PFNGLDELETEFRAMEBUFFERSEXTPROC>(&OOBadOpenGLExtensionUsed);
PFNGLDELETERENDERBUFFERSEXTPROC glDeleteRenderbuffersEXT =
    reinterpret_cast<PFNGLDELETERENDERBUFFERSEXTPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLGENRENDERBUFFERSPROC glGenRenderbuffers =
    reinterpret_cast<PFNGLGENRENDERBUFFERSPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBINDRENDERBUFFERPROC glBindRenderbuffer =
    reinterpret_cast<PFNGLBINDRENDERBUFFERPROC>(&OOBadOpenGLExtensionUsed);
PFNGLRENDERBUFFERSTORAGEPROC glRenderbufferStorage =
    reinterpret_cast<PFNGLRENDERBUFFERSTORAGEPROC>(&OOBadOpenGLExtensionUsed);
PFNGLGENFRAMEBUFFERSPROC glGenFramebuffers =
    reinterpret_cast<PFNGLGENFRAMEBUFFERSPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBINDFRAMEBUFFERPROC glBindFramebuffer =
    reinterpret_cast<PFNGLBINDFRAMEBUFFERPROC>(&OOBadOpenGLExtensionUsed);
PFNGLFRAMEBUFFERRENDERBUFFERPROC glFramebufferRenderbuffer =
    reinterpret_cast<PFNGLFRAMEBUFFERRENDERBUFFERPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLFRAMEBUFFERTEXTURE2DPROC glFramebufferTexture2D =
    reinterpret_cast<PFNGLFRAMEBUFFERTEXTURE2DPROC>(&OOBadOpenGLExtensionUsed);
PFNGLGENVERTEXARRAYSPROC glGenVertexArrays =
    reinterpret_cast<PFNGLGENVERTEXARRAYSPROC>(&OOBadOpenGLExtensionUsed);
PFNGLGENBUFFERSPROC glGenBuffers =
    reinterpret_cast<PFNGLGENBUFFERSPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBINDVERTEXARRAYPROC glBindVertexArray =
    reinterpret_cast<PFNGLBINDVERTEXARRAYPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBINDBUFFERPROC glBindBuffer =
    reinterpret_cast<PFNGLBINDBUFFERPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBUFFERDATAPROC glBufferData =
    reinterpret_cast<PFNGLBUFFERDATAPROC>(&OOBadOpenGLExtensionUsed);
PFNGLVERTEXATTRIBPOINTERPROC glVertexAttribPointer =
    reinterpret_cast<PFNGLVERTEXATTRIBPOINTERPROC>(&OOBadOpenGLExtensionUsed);
PFNGLENABLEVERTEXATTRIBARRAYPROC glEnableVertexAttribArray =
    reinterpret_cast<PFNGLENABLEVERTEXATTRIBARRAYPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLUSEPROGRAMPROC glUseProgram =
    reinterpret_cast<PFNGLUSEPROGRAMPROC>(&OOBadOpenGLExtensionUsed);
PFNGLGETUNIFORMLOCATIONPROC glGetUniformLocation =
    reinterpret_cast<PFNGLGETUNIFORMLOCATIONPROC>(&OOBadOpenGLExtensionUsed);
PFNGLUNIFORM1IPROC glUniform1i =
    reinterpret_cast<PFNGLUNIFORM1IPROC>(&OOBadOpenGLExtensionUsed);
PFNGLACTIVETEXTUREPROC glActiveTexture =
    reinterpret_cast<PFNGLACTIVETEXTUREPROC>(&OOBadOpenGLExtensionUsed);
PFNGLBLENDFUNCSEPARATEPROC glBlendFuncSeparate =
    reinterpret_cast<PFNGLBLENDFUNCSEPARATEPROC>(&OOBadOpenGLExtensionUsed);
PFNGLUNIFORM1FPROC glUniform1f =
    reinterpret_cast<PFNGLUNIFORM1FPROC>(&OOBadOpenGLExtensionUsed);
PFNGLUNIFORM2FVPROC glUniform2fv =
    reinterpret_cast<PFNGLUNIFORM2FVPROC>(&OOBadOpenGLExtensionUsed);
PFNGLDELETERENDERBUFFERSPROC glDeleteRenderbuffers =
    reinterpret_cast<PFNGLDELETERENDERBUFFERSPROC>(&OOBadOpenGLExtensionUsed);
PFNGLDELETEFRAMEBUFFERSPROC glDeleteFramebuffers =
    reinterpret_cast<PFNGLDELETEFRAMEBUFFERSPROC>(&OOBadOpenGLExtensionUsed);
PFNGLDELETEVERTEXARRAYSPROC glDeleteVertexArrays =
    reinterpret_cast<PFNGLDELETEVERTEXARRAYSPROC>(&OOBadOpenGLExtensionUsed);
PFNGLDELETEBUFFERSPROC glDeleteBuffers =
    reinterpret_cast<PFNGLDELETEBUFFERSPROC>(&OOBadOpenGLExtensionUsed);
PFNGLDRAWBUFFERSPROC glDrawBuffers =
    reinterpret_cast<PFNGLDRAWBUFFERSPROC>(&OOBadOpenGLExtensionUsed);
PFNGLCHECKFRAMEBUFFERSTATUSPROC glCheckFramebufferStatus =
    reinterpret_cast<PFNGLCHECKFRAMEBUFFERSTATUSPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLTEXIMAGE2DMULTISAMPLEPROC glTexImage2DMultisample =
    reinterpret_cast<PFNGLTEXIMAGE2DMULTISAMPLEPROC>(&OOBadOpenGLExtensionUsed);
PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC glRenderbufferStorageMultisample =
    reinterpret_cast<PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC>(
        &OOBadOpenGLExtensionUsed);
PFNGLBLITFRAMEBUFFERPROC glBlitFramebuffer =
    reinterpret_cast<PFNGLBLITFRAMEBUFFERPROC>(&OOBadOpenGLExtensionUsed);
PFNGLCLAMPCOLORPROC glClampColor =
    reinterpret_cast<PFNGLCLAMPCOLORPROC>(&OOBadOpenGLExtensionUsed);
#endif
#endif

namespace {
constexpr const char* kOOLogOpenGLShaderSupport =
    "rendering.opengl.shader.support";
}

namespace {

OOOpenGLExtensionManager* sSingleton =
    nullptr;  // +1, never released (the retained singleton)

}  // namespace

// Read integer from string, advancing string to end of read data.
static unsigned IntegerFromString(const GLubyte** ioString);

namespace {

std::vector<std::string> ArrayOfExtensions(
    const std::optional<std::string>& extensionString) {
  std::vector<std::string> result;
  if (!extensionString.has_value()) return result;
  for (std::string& extStr : oo::str::split(*extensionString, " ")) {
    if (!extStr.empty()) result.push_back(std::move(extStr));
  }
  return result;
}

// What -initWithUTF8String: gave for a glGetString() result: nil for NULL.
std::optional<std::string> OptionalGLString(const GLubyte* string) {
  if (string == nullptr) return std::nullopt;
  return std::string(reinterpret_cast<const char*>(string));
}

}  // namespace

void OOOpenGLExtensionManager::reset() {
  const GLubyte *versionString = nullptr, *curr = nullptr;

  const std::optional<std::string> extensionsStr =
      OptionalGLString(glGetString(GL_EXTENSIONS));
  {
    const std::vector<std::string> extensionList =
        ArrayOfExtensions(extensionsStr);
    extensions =
        std::set<std::string>(extensionList.begin(), extensionList.end());
  }

  vendor = OptionalGLString(glGetString(GL_VENDOR));
  renderer = OptionalGLString(glGetString(GL_RENDERER));

  versionString = glGetString(GL_VERSION);
  if (versionString != nullptr) {
    /*	String is supposed to be "major.minorFOO" or
     "major.minor.releaseFOO" where FOO is an empty string or
     a string beginning with space.
     */
    curr = versionString;
    major = IntegerFromString(&curr);
    if (*curr == '.') {
      curr++;
      minor = IntegerFromString(&curr);
    }
    if (*curr == '.') {
      curr++;
      release_ = IntegerFromString(&curr);
    }
  }

  /*	For aesthetic reasons, cause the ResourceManager to initialize its
   search paths here. If we don't, the search path dump ends up in
   the middle of the OpenGL stuff.
   */
  ResourceManager::paths();

  OO_LOG(
      "rendering.opengl.version",
      "OpenGL renderer version: {}.{}.{} (\"{}\"). Vendor: \"{}\". Renderer: "
      "\"{}\".",
      major, minor, release_,
      versionString ? reinterpret_cast<const char*>(versionString) : "(null)",
      vendor.value_or("(null)"), renderer.value_or("(null)"));
  {
    // Listed in byte order of the name (the set's hash order before).
    std::string extensionList;
    for (const std::string& extension : extensions) {
      if (!extensionList.empty()) extensionList += ", ";
      extensionList += extension;
    }
    OO_LOG("rendering.opengl.extensions", "OpenGL extensions ({}):\n{}",
           extensions.size(), extensionList);
  }

#if OOLITE_MACOS
  /*	macOS only offers a 2.1 legacy context alongside fixed-function GL, but
          it provides what Oolite needs from 3.3 as extensions.
  */
  if (versionIsAtLeastMajor(2, 1) &&
      haveExtension("GL_ARB_framebuffer_object") &&
      haveExtension("GL_APPLE_vertex_array_object") &&
      haveExtension("GL_ARB_texture_float") &&
      haveExtension("GL_ARB_color_buffer_float") &&
      haveExtension("GL_ARB_draw_buffers")) {
    // OK
  } else
#endif
      if (!versionIsAtLeastMajor(kMinMajorVersion, kMinMinorVersion)) {
    OO_LOG("rendering.opengl.version.insufficient",
           "***** Oolite requires OpenGL version {}.{} or later.",
           static_cast<unsigned>(kMinMajorVersion),
           static_cast<unsigned>(kMinMinorVersion));
    OORaiseException(
        "OoliteOpenGLTooOldException",
        "Oolite requires at least OpenGL %u.%u. You have %u.%u (\"%s\").",
        kMinMajorVersion, kMinMinorVersion, major, minor, versionString);
  }

  const std::optional<std::string> versionStr = OptionalGLString(versionString);
  const oo::PList gpuConfig =
      lookUpPerGPUSettingsWithVersionString(versionStr, extensionsStr);

#if OO_SHADERS
  checkShadersSupported();

  if (shadersAvailable) {
    defaultShaderSetting = cxx_OOShaderSettingFromString(
        gpuConfig.get<std::string>("default_shader_level", "SHADERS_FULL"));
    maximumShaderSetting = cxx_OOShaderSettingFromString(
        gpuConfig.get<std::string>("maximum_shader_level", "SHADERS_FULL"));
    if (maximumShaderSetting <= OOShaderSetting::kOff) {
      shadersAvailable = false;
      maximumShaderSetting = OOShaderSetting::kNotSupported;
      {
        // A name that is not a string fell back to the renderer, which may
        // itself be nil.
        const oo::PList* name = gpuConfig.find("name");
        const bool hasName =
            name != nullptr && (name->isString() || name->isNumber());
        OO_LOG(kOOLogOpenGLShaderSupport,
               "Shaders will not be used (disallowed for GPU type \"{}\").",
               hasName ? gpuConfig.get<std::string>("name")
                       : renderer.value_or("(null)"));
      }
    }
    if (maximumShaderSetting < defaultShaderSetting) {
      defaultShaderSetting = maximumShaderSetting;
    }

    if (shadersAvailable) {
      OO_LOG(kOOLogOpenGLShaderSupport, "{}", "Shaders are supported.");
    }
  } else {
    defaultShaderSetting = OOShaderSetting::kNotSupported;
    maximumShaderSetting = OOShaderSetting::kNotSupported;
  }

  GLint texImageUnitOverride =
      gpuConfig.get<int>("texture_image_units", textureImageUnitCount_);
  if (texImageUnitOverride < textureImageUnitCount_)
    textureImageUnitCount_ = MAX(texImageUnitOverride, 0);
#endif

#if OO_USE_VBO
  checkVBOSupported();
#endif
#if OO_USE_FBO
  checkFBOSupported();
#endif
#if OO_MULTITEXTURE
  checkTextureCombinersSupported();
  GLint texUnitOverride =
      gpuConfig.get<int>("texture_units", textureUnitCount_);
  if (texUnitOverride < textureUnitCount_)
    textureUnitCount_ = MAX(texUnitOverride, 0);
#endif

  usePointSmoothing_ =
      gpuConfig.get<bool>("smooth_points", true) ? true : false;
  useLineSmoothing_ = gpuConfig.get<bool>("smooth_lines", true) ? true : false;
  useDustShader_ = gpuConfig.get<bool>("use_dust_shader", true) ? true : false;
}

OOOpenGLExtensionManager::~OOOpenGLExtensionManager() {
  if (sSingleton == this) sSingleton = nullptr;
}

OOOpenGLExtensionManager* OOOpenGLExtensionManager::sharedManager() {
  // NOTE: assumes single-threaded first access. See header.
  if (sSingleton == nullptr) {
    // The singleton category's +allocWithZone: recorded the instance before
    // -init ran -reset, so it is recorded here before reset() runs too.
    sSingleton = (*new std::shared_ptr<OOOpenGLExtensionManager>(
                      oo::makeShared<OOOpenGLExtensionManager>()))
                     .get();
    sSingleton->reset();
  }
  return sSingleton;
}

bool OOOpenGLExtensionManager::haveExtension(const std::string& extension) {
  // The Foundation set was documented as thread-safe under OS X, but I'm not
  // sure about GNUstep. -- Ahruman
  lock.lock();

  bool result = extensions.contains(extension) ? true : false;

  lock.unlock();

  return result;
}

bool OOOpenGLExtensionManager::shadersSupported() {
#if OO_SHADERS
  return shadersAvailable;
#else
  return false;
#endif
}

bool OOOpenGLExtensionManager::shadersForceDisabled() {
#if OO_SHADERS
  return shadersForceDisabled_;
#else
  return true;
#endif
}

OOGraphicsDetail OOOpenGLExtensionManager::defaultDetailLevel() {
#if OO_SHADERS
  if (defaultShaderSetting < OOShaderSetting::kFull) {
    return OOGraphicsDetail::kMinimum;
  } else {
    return kOOGraphicsDetailMaximum;
  }
#else
  return OOShaderSetting::kNotSupported;
#endif
}

OOGraphicsDetail OOOpenGLExtensionManager::maximumDetailLevel() {
#if OO_SHADERS
  if (maximumShaderSetting < OOShaderSetting::kFull) {
    return OOGraphicsDetail::kMinimum;
  } else {
    return kOOGraphicsDetailMaximum;
  }
#else
  return OOGraphicsDetail::kMinimum;
#endif
}

GLint OOOpenGLExtensionManager::textureImageUnitCount() {
#if OO_SHADERS
  return textureImageUnitCount_;
#else
  return 0;
#endif
}

bool OOOpenGLExtensionManager::vboSupported() {
#if OO_USE_VBO
  return vboSupported_;
#else
  return false;
#endif
}

bool OOOpenGLExtensionManager::fboSupported() {
#if OO_USE_FBO
  return fboSupported_;
#else
  return false;
#endif
}

bool OOOpenGLExtensionManager::textureCombinersSupported() {
#if OO_MULTITEXTURE
  return textureCombinersSupported_;
#else
  return false;
#endif
}

GLint OOOpenGLExtensionManager::textureUnitCount() {
#if OO_MULTITEXTURE
  return textureUnitCount_;
#else
  return 0;
#endif
}

std::size_t OOOpenGLExtensionManager::majorVersionNumber() { return major; }

std::size_t OOOpenGLExtensionManager::minorVersionNumber() { return minor; }

std::size_t OOOpenGLExtensionManager::releaseVersionNumber() {
  return release_;
}

void OOOpenGLExtensionManager::getVersionMajor(unsigned* outMajor,
                                               unsigned* outMinor,
                                               unsigned* outRelease) {
  if (outMajor != nullptr) *outMajor = major;
  if (outMinor != nullptr) *outMinor = minor;
  if (outRelease != nullptr) *outRelease = release_;
}

bool OOOpenGLExtensionManager::versionIsAtLeastMajor(unsigned maj,
                                                     unsigned min) {
  return major > maj || (major == maj && minor >= min);
}

std::optional<std::string> OOOpenGLExtensionManager::vendorString() {
  return vendor;
}

std::optional<std::string> OOOpenGLExtensionManager::rendererString() {
  return renderer;
}

bool OOOpenGLExtensionManager::usePointSmoothing() {
  return usePointSmoothing_;
}

bool OOOpenGLExtensionManager::useLineSmoothing() { return useLineSmoothing_; }

bool OOOpenGLExtensionManager::useDustShader() { return useDustShader_; }

static unsigned IntegerFromString(const GLubyte** ioString) {
  if (EXPECT_NOT(ioString == nullptr)) return 0;

  unsigned result = 0;
  const GLubyte* curr = *ioString;

  while ('0' <= *curr && *curr <= '9') {
    result = result * 10 + *curr++ - '0';
  }

  *ioString = curr;
  return result;
}

#if OO_SHADERS

/**
 * \ingroup cli
 * Scans the command line for -noshaders or --noshaders arguments.
 */
void OOOpenGLExtensionManager::checkShadersSupported() {
  shadersAvailable = false;
  shadersForceDisabled_ = false;

  /* Some cards claim to support shaders but do so extremely
   * badly. These are listed in gpu-settings.plist where we know
   * about them; for those we don't being able to run with
   * -noshaders may help get the game up and running at a frame rate
   * where thegraphics settings can be changed.  - CIM */
  // scan for shader overrides: -noshaders || --noshaders
  for (const std::string& arg : oo::process::arguments()) {
    if (arg == "-noshaders" || arg == "--noshaders") {
      shadersForceDisabled_ = true;
      OO_LOG(kOOLogOpenGLShaderSupport, "{}",
             "Shaders will not be used (disabled on command line).");
      return;
    }
  }

  static constexpr std::array<std::string_view, 5> requiredExtension = {
      "GL_ARB_shading_language_100", "GL_ARB_fragment_shader",
      "GL_ARB_vertex_shader",        "GL_ARB_multitexture",
      "GL_ARB_shader_objects",
  };

  for (std::string_view required : requiredExtension) {
    if (!haveExtension(std::string(required))) {
      OO_LOG(kOOLogOpenGLShaderSupport,
             "Shaders will not be used (OpenGL extension {} is not available).",
             required);
      return;
    }
  }

#if OOLITE_WINDOWS
  glGetObjectParameterivARB =
      reinterpret_cast<PFNGLGETOBJECTPARAMETERIVARBPROC>(
          wglGetProcAddress("glGetObjectParameterivARB"));
  glCreateShaderObjectARB = reinterpret_cast<PFNGLCREATESHADEROBJECTARBPROC>(
      wglGetProcAddress("glCreateShaderObjectARB"));
  glGetInfoLogARB = reinterpret_cast<PFNGLGETINFOLOGARBPROC>(
      wglGetProcAddress("glGetInfoLogARB"));
  glCreateProgramObjectARB = reinterpret_cast<PFNGLCREATEPROGRAMOBJECTARBPROC>(
      wglGetProcAddress("glCreateProgramObjectARB"));
  glAttachObjectARB = reinterpret_cast<PFNGLATTACHOBJECTARBPROC>(
      wglGetProcAddress("glAttachObjectARB"));
  glDeleteObjectARB = reinterpret_cast<PFNGLDELETEOBJECTARBPROC>(
      wglGetProcAddress("glDeleteObjectARB"));
  glLinkProgramARB = reinterpret_cast<PFNGLLINKPROGRAMARBPROC>(
      wglGetProcAddress("glLinkProgramARB"));
  glCompileShaderARB = reinterpret_cast<PFNGLCOMPILESHADERARBPROC>(
      wglGetProcAddress("glCompileShaderARB"));
  glShaderSourceARB = reinterpret_cast<PFNGLSHADERSOURCEARBPROC>(
      wglGetProcAddress("glShaderSourceARB"));
  glUseProgramObjectARB = reinterpret_cast<PFNGLUSEPROGRAMOBJECTARBPROC>(
      wglGetProcAddress("glUseProgramObjectARB"));
  glActiveTextureARB = reinterpret_cast<PFNGLACTIVETEXTUREARBPROC>(
      wglGetProcAddress("glActiveTextureARB"));
  glGetUniformLocationARB = reinterpret_cast<PFNGLGETUNIFORMLOCATIONARBPROC>(
      wglGetProcAddress("glGetUniformLocationARB"));
  glUniform1iARB = reinterpret_cast<PFNGLUNIFORM1IARBPROC>(
      wglGetProcAddress("glUniform1iARB"));
  glUniform1fARB = reinterpret_cast<PFNGLUNIFORM1FARBPROC>(
      wglGetProcAddress("glUniform1fARB"));
  glUniformMatrix3fvARB = reinterpret_cast<PFNGLUNIFORMMATRIX3FVARBPROC>(
      wglGetProcAddress("glUniformMatrix3fvARB"));
  glUniformMatrix4fvARB = reinterpret_cast<PFNGLUNIFORMMATRIX4FVARBPROC>(
      wglGetProcAddress("glUniformMatrix4fvARB"));
  glUniform4fvARB = reinterpret_cast<PFNGLUNIFORM4FVARBPROC>(
      wglGetProcAddress("glUniform4fvARB"));
  glUniform2fvARB = reinterpret_cast<PFNGLUNIFORM2FVARBPROC>(
      wglGetProcAddress("glUniform2fvARB"));
  glBindAttribLocationARB = reinterpret_cast<PFNGLBINDATTRIBLOCATIONARBPROC>(
      wglGetProcAddress("glBindAttribLocationARB"));
  glEnableVertexAttribArrayARB =
      reinterpret_cast<PFNGLENABLEVERTEXATTRIBARRAYARBPROC>(
          wglGetProcAddress("glEnableVertexAttribArrayARB"));
  glVertexAttribPointerARB = reinterpret_cast<PFNGLVERTEXATTRIBPOINTERARBPROC>(
      wglGetProcAddress("glVertexAttribPointerARB"));
  glDisableVertexAttribArrayARB =
      reinterpret_cast<PFNGLDISABLEVERTEXATTRIBARRAYARBPROC>(
          wglGetProcAddress("glDisableVertexAttribArrayARB"));
  glValidateProgramARB = reinterpret_cast<PFNGLVALIDATEPROGRAMARBPROC>(
      wglGetProcAddress("glValidateProgramARB"));
#endif

  glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS_ARB, &textureImageUnitCount_);

  shadersAvailable = true;
}
#endif

#if OO_USE_VBO
void OOOpenGLExtensionManager::checkVBOSupported() {
  vboSupported_ = false;

  if (versionIsAtLeastMajor(1, 5) ||
      haveExtension("GL_ARB_vertex_buffer_object")) {
    vboSupported_ = true;
  }

#if OOLITE_WINDOWS
  if (vboSupported_) {
    glGenBuffersARB = reinterpret_cast<PFNGLGENBUFFERSARBPROC>(
        wglGetProcAddress("glGenBuffersARB"));
    glDeleteBuffersARB = reinterpret_cast<PFNGLDELETEBUFFERSARBPROC>(
        wglGetProcAddress("glDeleteBuffersARB"));
    glBindBufferARB = reinterpret_cast<PFNGLBINDBUFFERARBPROC>(
        wglGetProcAddress("glBindBufferARB"));
    glBufferDataARB = reinterpret_cast<PFNGLBUFFERDATAARBPROC>(
        wglGetProcAddress("glBufferDataARB"));
  }
#endif
}
#endif

#if OO_USE_FBO
void OOOpenGLExtensionManager::checkFBOSupported() {
  fboSupported_ = false;

  if (haveExtension("GL_EXT_framebuffer_object")) {
    fboSupported_ = true;
  }

#if OOLITE_WINDOWS
  if (fboSupported_) {
    glGenFramebuffersEXT = reinterpret_cast<PFNGLGENFRAMEBUFFERSEXTPROC>(
        wglGetProcAddress("glGenFramebuffersEXT"));
    glBindFramebufferEXT = reinterpret_cast<PFNGLBINDFRAMEBUFFEREXTPROC>(
        wglGetProcAddress("glBindFramebufferEXT"));
    glGenRenderbuffersEXT = reinterpret_cast<PFNGLGENRENDERBUFFERSEXTPROC>(
        wglGetProcAddress("glGenRenderbuffersEXT"));
    glBindRenderbufferEXT = reinterpret_cast<PFNGLBINDRENDERBUFFEREXTPROC>(
        wglGetProcAddress("glBindRenderbufferEXT"));
    glRenderbufferStorageEXT =
        reinterpret_cast<PFNGLRENDERBUFFERSTORAGEEXTPROC>(
            wglGetProcAddress("glRenderbufferStorageEXT"));
    glFramebufferRenderbufferEXT =
        reinterpret_cast<PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC>(
            wglGetProcAddress("glFramebufferRenderbufferEXT"));
    glFramebufferTexture2DEXT =
        reinterpret_cast<PFNGLFRAMEBUFFERTEXTURE2DEXTPROC>(
            wglGetProcAddress("glFramebufferTexture2DEXT"));
    glCheckFramebufferStatusEXT =
        reinterpret_cast<PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC>(
            wglGetProcAddress("glCheckFramebufferStatusEXT"));
    glDeleteFramebuffersEXT = reinterpret_cast<PFNGLDELETEFRAMEBUFFERSEXTPROC>(
        wglGetProcAddress("glDeleteFramebuffersEXT"));
    glDeleteRenderbuffersEXT =
        reinterpret_cast<PFNGLDELETERENDERBUFFERSEXTPROC>(
            wglGetProcAddress("glDeleteRenderbuffersEXT"));
    glGenRenderbuffers = reinterpret_cast<PFNGLGENRENDERBUFFERSPROC>(
        wglGetProcAddress("glGenRenderbuffers"));
    glBindRenderbuffer = reinterpret_cast<PFNGLBINDRENDERBUFFERPROC>(
        wglGetProcAddress("glBindRenderbuffer"));
    glRenderbufferStorage = reinterpret_cast<PFNGLRENDERBUFFERSTORAGEPROC>(
        wglGetProcAddress("glRenderbufferStorage"));
    glGenFramebuffers = reinterpret_cast<PFNGLGENFRAMEBUFFERSPROC>(
        wglGetProcAddress("glGenFramebuffers"));
    glBindFramebuffer = reinterpret_cast<PFNGLBINDFRAMEBUFFERPROC>(
        wglGetProcAddress("glBindFramebuffer"));
    glFramebufferRenderbuffer =
        reinterpret_cast<PFNGLFRAMEBUFFERRENDERBUFFERPROC>(
            wglGetProcAddress("glFramebufferRenderbuffer"));
    glFramebufferTexture2D = reinterpret_cast<PFNGLFRAMEBUFFERTEXTURE2DPROC>(
        wglGetProcAddress("glFramebufferTexture2D"));
    glGenVertexArrays = reinterpret_cast<PFNGLGENVERTEXARRAYSPROC>(
        wglGetProcAddress("glGenVertexArrays"));
    glGenBuffers = reinterpret_cast<PFNGLGENBUFFERSPROC>(
        wglGetProcAddress("glGenBuffers"));
    glBindVertexArray = reinterpret_cast<PFNGLBINDVERTEXARRAYPROC>(
        wglGetProcAddress("glBindVertexArray"));
    glBindBuffer = reinterpret_cast<PFNGLBINDBUFFERPROC>(
        wglGetProcAddress("glBindBuffer"));
    glBufferData = reinterpret_cast<PFNGLBUFFERDATAPROC>(
        wglGetProcAddress("glBufferData"));
    glVertexAttribPointer = reinterpret_cast<PFNGLVERTEXATTRIBPOINTERPROC>(
        wglGetProcAddress("glVertexAttribPointer"));
    glEnableVertexAttribArray =
        reinterpret_cast<PFNGLENABLEVERTEXATTRIBARRAYPROC>(
            wglGetProcAddress("glEnableVertexAttribArray"));
    glUseProgram = reinterpret_cast<PFNGLUSEPROGRAMPROC>(
        wglGetProcAddress("glUseProgram"));
    glGetUniformLocation = reinterpret_cast<PFNGLGETUNIFORMLOCATIONPROC>(
        wglGetProcAddress("glGetUniformLocation"));
    glUniform1i =
        reinterpret_cast<PFNGLUNIFORM1IPROC>(wglGetProcAddress("glUniform1i"));
    glActiveTexture = reinterpret_cast<PFNGLACTIVETEXTUREPROC>(
        wglGetProcAddress("glActiveTexture"));
    glBlendFuncSeparate = reinterpret_cast<PFNGLBLENDFUNCSEPARATEPROC>(
        wglGetProcAddress("glBlendFuncSeparate"));
    glUniform1f =
        reinterpret_cast<PFNGLUNIFORM1FPROC>(wglGetProcAddress("glUniform1f"));
    glUniform2fv = reinterpret_cast<PFNGLUNIFORM2FVPROC>(
        wglGetProcAddress("glUniform2fv"));
    glDeleteRenderbuffers = reinterpret_cast<PFNGLDELETERENDERBUFFERSPROC>(
        wglGetProcAddress("glDeleteRenderbuffer"));
    glDeleteFramebuffers = reinterpret_cast<PFNGLDELETEFRAMEBUFFERSPROC>(
        wglGetProcAddress("glDeleteFramebuffers"));
    glDeleteVertexArrays = reinterpret_cast<PFNGLDELETEVERTEXARRAYSPROC>(
        wglGetProcAddress("glDeleteVertexArrays"));
    glDeleteBuffers = reinterpret_cast<PFNGLDELETEBUFFERSPROC>(
        wglGetProcAddress("glDeleteBuffers"));
    glDrawBuffers = reinterpret_cast<PFNGLDRAWBUFFERSPROC>(
        wglGetProcAddress("glDrawBuffers"));
    glCheckFramebufferStatus =
        reinterpret_cast<PFNGLCHECKFRAMEBUFFERSTATUSPROC>(
            wglGetProcAddress("glCheckFramebufferStatus"));
    glTexImage2DMultisample = reinterpret_cast<PFNGLTEXIMAGE2DMULTISAMPLEPROC>(
        wglGetProcAddress("glTexImage2DMultisample"));
    glRenderbufferStorageMultisample =
        reinterpret_cast<PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC>(
            wglGetProcAddress("glRenderbufferStorageMultisample"));
    glBlitFramebuffer = reinterpret_cast<PFNGLBLITFRAMEBUFFERPROC>(
        wglGetProcAddress("glBlitFramebuffer"));
    glClampColor = reinterpret_cast<PFNGLCLAMPCOLORPROC>(
        wglGetProcAddress("glClampColor"));
  }
#endif
}
#endif

#if OO_MULTITEXTURE
void OOOpenGLExtensionManager::checkTextureCombinersSupported() {
  textureCombinersSupported_ = haveExtension("GL_ARB_texture_env_combine");

  if (textureCombinersSupported_) {
    OOGL(glGetIntegerv(GL_MAX_TEXTURE_UNITS_ARB, &textureUnitCount_));

#if OOLITE_WINDOWS
    // Duplicated in checkShadersSupported. but that's not really a problem.
    glActiveTextureARB = reinterpret_cast<PFNGLACTIVETEXTUREARBPROC>(
        wglGetProcAddress("glActiveTextureARB"));

    glClientActiveTextureARB =
        reinterpret_cast<PFNGLCLIENTACTIVETEXTUREARBPROC>(
            wglGetProcAddress("glClientActiveTextureARB"));
#endif
  } else {
    textureUnitCount_ = 1;
  }
}
#endif

namespace {

// The regexp test sent to a string that may be nil (a nil string matched
// nothing). matcher is the one pass's matcher, taken on first use and held by
// the caller, so one pass compiles one tester.
// A null matcher (the tester did not compile) answers NO and is asked again.
bool MatchesRegExp(oo::Ref<::OORegExpMatcher>& matcher,
                   const std::optional<std::string>& string,
                   const std::string& regexp) {
  if (!string.has_value()) return false;
  if (matcher == nullptr) matcher = ::OORegExpMatcher::regExpMatcher();
  if (matcher == nullptr) return false;
  return matcher->string(*string, regexp);
}

// regexps may be a single string or an array of strings (in which case results
// are ANDed).
bool CheckRegExps(oo::Ref<::OORegExpMatcher>& matcher,
                  const std::optional<std::string>& string,
                  const oo::PList& regexps) {
  if (regexps.isNull()) return true;  // No restriction == match.
  if (const std::string* regexp = regexps.getIf<std::string>()) {
    return MatchesRegExp(matcher, string, *regexp);
  }
  if (const oo::PList::Array* array = regexps.getIf<oo::PList::Array>()) {
    for (const oo::PList& element : *array) {
      const std::string* regexp = element.getIf<std::string>();
      if (EXPECT_NOT(regexp == nullptr)) {
        // Invalid type -- match fails.
        return false;
      }

      if (!MatchesRegExp(matcher, string, *regexp)) return false;
    }
    return true;
  }

  // Invalid type -- match fails.
  return false;
}

// oo_stringForKey: on a dictionary that may be nil: a string, a number's string
// value, or nil.
oo::PList StringForKey(const oo::PList* dict, std::string_view key) {
  const oo::PList* value = (dict != nullptr) ? dict->find(key) : nullptr;
  if (value == nullptr || !(value->isString() || value->isNumber()))
    return oo::PList();
  return oo::PList(dict->get<std::string>(key));
}

}  // namespace

oo::PList OOOpenGLExtensionManager::lookUpPerGPUSettingsWithVersionString(
    const std::optional<std::string>& versionStr,
    const std::optional<std::string>& extensionsStr) {
  const oo::PList configurations = ResourceManager::dictionaryFromFilesNamed(
      "gpu-settings.plist", "Config", true);

  // Highest precedence first, then case-insensitive name order (keys were taken
  // in hash order before sorting; ties between names equal but for case now
  // keep byte order).
  std::vector<std::string> keys;
  if (const oo::PList::Dict* dict = configurations.getIf<oo::PList::Dict>()) {
    for (const auto& entry : *dict) keys.push_back(entry.first);
  }
  std::stable_sort(
      keys.begin(), keys.end(),
      [&configurations](const std::string& keyA, const std::string& keyB) {
        const oo::PList* dictA = configurations.get<oo::PList::Dict>(keyA);
        const oo::PList* dictB = configurations.get<oo::PList::Dict>(keyB);
        const double precedenceA =
            dictA != nullptr ? dictA->get<double>("precedence", 1) : 0;
        const double precedenceB =
            dictB != nullptr ? dictB->get<double>("precedence", 1) : 0;

        if (precedenceA != precedenceB) return precedenceA > precedenceB;
        return oo::str::caseInsensitiveCompare(keyA, keyB) < 0;
      });

  oo::Ref<::OORegExpMatcher> matcher;  // one for the pass (see MatchesRegExp)
  for (const std::string& key : keys) {
    const oo::PList* config = configurations.get<oo::PList::Dict>(key);
    if (EXPECT_NOT(config == nullptr)) continue;

    const oo::PList* match = config->get<oo::PList::Dict>("match");
    const oo::PList* vendorExpr =
        (match != nullptr) ? match->find("vendor") : nullptr;

    if (!CheckRegExps(matcher, vendor,
                      vendorExpr != nullptr ? *vendorExpr : oo::PList()))
      continue;

    if (!CheckRegExps(matcher, renderer, StringForKey(match, "renderer")))
      continue;

    if (!CheckRegExps(matcher, versionStr, StringForKey(match, "version")))
      continue;

    if (!CheckRegExps(matcher, extensionsStr,
                      StringForKey(match, "extensions")))
      continue;

    OO_LOG("rendering.opengl.gpuSpecific", "Matched GPU configuration \"{}\".",
           key);
    return *config;
  }

  return oo::PList(oo::PList::Dict{});
}

// The singleton category (+allocWithZone:, and -retain/-release/-autorelease
// doing nothing) is not translated: the one instance is made only by
// sharedManager() and never released.

#if OOLITE_WINDOWS

static void OOBadOpenGLExtensionUsed(void) {
  OO_LOG("rendering.opengl.badExtension", "{}",
         "***** An uninitialized OpenGL extension function has been called, "
         "terminating. This is a serious error, please report it. *****");
  exit(EXIT_FAILURE);
}

#endif
