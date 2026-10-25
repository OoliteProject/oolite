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
#include "oofnd/Process.hpp"
#include "OOLogging.h"
#include "OOFunctionAttributes.h"
#include <stdlib.h>

#include "ResourceManager.h"
#include "OORegExpMatcher.h"
#include "OOConstToString.h"
#include "oofnd/objc/OOException.h"

#include "oofnd/String.hpp"
#include "oofnd/Log.hpp"


/*	OpenGL version required, currently 1.1 or later (basic stuff like
	glBindTexture(), glDrawArrays()). We probably have implicit requirements
	for later versions, but I don't feel like auditing.
	-- Ahruman
	We need at least 3.0 for the Frame Buffer Objects now in use. Might as
 	well go all the way to 3.3.
	-- Nikos 20220817
*/
enum
{
	kMinMajorVersion				= 3,
	kMinMinorVersion				= 3
};


#if OOLITE_WINDOWS
/*	Define the function pointers for the OpenGL extensions used in the game
	(required for Windows only).
*/
static void OOBadOpenGLExtensionUsed(void) GCC_ATTR((noreturn, used));

#if OO_SHADERS

PFNGLUSEPROGRAMOBJECTARBPROC			glUseProgramObjectARB			= (PFNGLUSEPROGRAMOBJECTARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLGETUNIFORMLOCATIONARBPROC			glGetUniformLocationARB			= (PFNGLGETUNIFORMLOCATIONARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORM1IARBPROC					glUniform1iARB					= (PFNGLUNIFORM1IARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORM1FARBPROC					glUniform1fARB					= (PFNGLUNIFORM1FARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORMMATRIX3FVARBPROC			glUniformMatrix3fvARB			= (PFNGLUNIFORMMATRIX3FVARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORMMATRIX4FVARBPROC			glUniformMatrix4fvARB			= (PFNGLUNIFORMMATRIX4FVARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORM4FVARBPROC					glUniform4fvARB					= (PFNGLUNIFORM4FVARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLGETOBJECTPARAMETERIVARBPROC		glGetObjectParameterivARB		= (PFNGLGETOBJECTPARAMETERIVARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLCREATESHADEROBJECTARBPROC			glCreateShaderObjectARB			= (PFNGLCREATESHADEROBJECTARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLGETINFOLOGARBPROC					glGetInfoLogARB					= (PFNGLGETINFOLOGARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLCREATEPROGRAMOBJECTARBPROC			glCreateProgramObjectARB		= (PFNGLCREATEPROGRAMOBJECTARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLATTACHOBJECTARBPROC				glAttachObjectARB				= (PFNGLATTACHOBJECTARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETEOBJECTARBPROC				glDeleteObjectARB				= (PFNGLDELETEOBJECTARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLLINKPROGRAMARBPROC					glLinkProgramARB				= (PFNGLLINKPROGRAMARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLCOMPILESHADERARBPROC				glCompileShaderARB				= (PFNGLCOMPILESHADERARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLSHADERSOURCEARBPROC				glShaderSourceARB				= (PFNGLSHADERSOURCEARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORM2FVARBPROC					glUniform2fvARB					= (PFNGLUNIFORM2FVARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLBINDATTRIBLOCATIONARBPROC			glBindAttribLocationARB			= (PFNGLBINDATTRIBLOCATIONARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLENABLEVERTEXATTRIBARRAYARBPROC		glEnableVertexAttribArrayARB	= (PFNGLENABLEVERTEXATTRIBARRAYARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLVERTEXATTRIBPOINTERARBPROC			glVertexAttribPointerARB		= (PFNGLVERTEXATTRIBPOINTERARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLDISABLEVERTEXATTRIBARRAYARBPROC	glDisableVertexAttribArrayARB	= (PFNGLDISABLEVERTEXATTRIBARRAYARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLVALIDATEPROGRAMARBPROC			glValidateProgramARB			= (PFNGLVALIDATEPROGRAMARBPROC)&OOBadOpenGLExtensionUsed;
#endif

#if OO_SHADERS || OO_MULTITEXTURE
PFNGLACTIVETEXTUREARBPROC				glActiveTextureARB				= (PFNGLACTIVETEXTUREARBPROC)&OOBadOpenGLExtensionUsed;
#endif

#if OO_MULTITEXTURE
PFNGLCLIENTACTIVETEXTUREARBPROC			glClientActiveTextureARB		= (PFNGLCLIENTACTIVETEXTUREARBPROC)&OOBadOpenGLExtensionUsed;
#endif

#if OO_USE_VBO
PFNGLGENBUFFERSARBPROC					glGenBuffersARB					= (PFNGLGENBUFFERSARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETEBUFFERSARBPROC				glDeleteBuffersARB				= (PFNGLDELETEBUFFERSARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLBINDBUFFERARBPROC					glBindBufferARB					= (PFNGLBINDBUFFERARBPROC)&OOBadOpenGLExtensionUsed;
PFNGLBUFFERDATAARBPROC					glBufferDataARB					= (PFNGLBUFFERDATAARBPROC)&OOBadOpenGLExtensionUsed;
#endif

#if OO_USE_FBO
PFNGLGENFRAMEBUFFERSEXTPROC				glGenFramebuffersEXT			= (PFNGLGENFRAMEBUFFERSEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLBINDFRAMEBUFFEREXTPROC				glBindFramebufferEXT			= (PFNGLBINDFRAMEBUFFEREXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLGENRENDERBUFFERSEXTPROC			glGenRenderbuffersEXT			= (PFNGLGENRENDERBUFFERSEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLBINDRENDERBUFFEREXTPROC			glBindRenderbufferEXT			= (PFNGLBINDRENDERBUFFEREXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLRENDERBUFFERSTORAGEEXTPROC			glRenderbufferStorageEXT		= (PFNGLRENDERBUFFERSTORAGEEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC		glFramebufferRenderbufferEXT	= (PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLFRAMEBUFFERTEXTURE2DEXTPROC		glFramebufferTexture2DEXT		= (PFNGLFRAMEBUFFERTEXTURE2DEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC		glCheckFramebufferStatusEXT		= (PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETEFRAMEBUFFERSEXTPROC			glDeleteFramebuffersEXT			= (PFNGLDELETEFRAMEBUFFERSEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETERENDERBUFFERSEXTPROC			glDeleteRenderbuffersEXT		= (PFNGLDELETERENDERBUFFERSEXTPROC)&OOBadOpenGLExtensionUsed;
PFNGLGENRENDERBUFFERSPROC				glGenRenderbuffers				= (PFNGLGENRENDERBUFFERSPROC)&OOBadOpenGLExtensionUsed;
PFNGLBINDRENDERBUFFERPROC				glBindRenderbuffer				= (PFNGLBINDRENDERBUFFERPROC)&OOBadOpenGLExtensionUsed;		 
PFNGLRENDERBUFFERSTORAGEPROC			glRenderbufferStorage			= (PFNGLRENDERBUFFERSTORAGEPROC)&OOBadOpenGLExtensionUsed;	  
PFNGLGENFRAMEBUFFERSPROC				glGenFramebuffers				= (PFNGLGENFRAMEBUFFERSPROC)&OOBadOpenGLExtensionUsed;		  
PFNGLBINDFRAMEBUFFERPROC				glBindFramebuffer				= (PFNGLBINDFRAMEBUFFERPROC)&OOBadOpenGLExtensionUsed;		  
PFNGLFRAMEBUFFERRENDERBUFFERPROC		glFramebufferRenderbuffer		= (PFNGLFRAMEBUFFERRENDERBUFFERPROC)&OOBadOpenGLExtensionUsed;  
PFNGLFRAMEBUFFERTEXTURE2DPROC			glFramebufferTexture2D			= (PFNGLFRAMEBUFFERTEXTURE2DPROC)&OOBadOpenGLExtensionUsed;	  
PFNGLGENVERTEXARRAYSPROC				glGenVertexArrays				= (PFNGLGENVERTEXARRAYSPROC)&OOBadOpenGLExtensionUsed;		  
PFNGLGENBUFFERSPROC						glGenBuffers					= (PFNGLGENBUFFERSPROC)&OOBadOpenGLExtensionUsed;				  
PFNGLBINDVERTEXARRAYPROC				glBindVertexArray				= (PFNGLBINDVERTEXARRAYPROC)&OOBadOpenGLExtensionUsed;		  
PFNGLBINDBUFFERPROC						glBindBuffer					= (PFNGLBINDBUFFERPROC)&OOBadOpenGLExtensionUsed;				  
PFNGLBUFFERDATAPROC						glBufferData					= (PFNGLBUFFERDATAPROC)&OOBadOpenGLExtensionUsed;				  
PFNGLVERTEXATTRIBPOINTERPROC			glVertexAttribPointer			= (PFNGLVERTEXATTRIBPOINTERPROC)&OOBadOpenGLExtensionUsed;	  
PFNGLENABLEVERTEXATTRIBARRAYPROC		glEnableVertexAttribArray		= (PFNGLENABLEVERTEXATTRIBARRAYPROC)&OOBadOpenGLExtensionUsed;  
PFNGLUSEPROGRAMPROC						glUseProgram					= (PFNGLUSEPROGRAMPROC)&OOBadOpenGLExtensionUsed;				  
PFNGLGETUNIFORMLOCATIONPROC				glGetUniformLocation			= (PFNGLGETUNIFORMLOCATIONPROC)&OOBadOpenGLExtensionUsed;		  
PFNGLUNIFORM1IPROC						glUniform1i						= (PFNGLUNIFORM1IPROC)&OOBadOpenGLExtensionUsed;				  
PFNGLACTIVETEXTUREPROC					glActiveTexture					= (PFNGLACTIVETEXTUREPROC)&OOBadOpenGLExtensionUsed;
PFNGLBLENDFUNCSEPARATEPROC				glBlendFuncSeparate				= (PFNGLBLENDFUNCSEPARATEPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORM1FPROC						glUniform1f						= (PFNGLUNIFORM1FPROC)&OOBadOpenGLExtensionUsed;
PFNGLUNIFORM2FVPROC						glUniform2fv					= (PFNGLUNIFORM2FVPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETERENDERBUFFERSPROC			glDeleteRenderbuffers			= (PFNGLDELETERENDERBUFFERSPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETEFRAMEBUFFERSPROC				glDeleteFramebuffers			= (PFNGLDELETEFRAMEBUFFERSPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETEVERTEXARRAYSPROC				glDeleteVertexArrays			= (PFNGLDELETEVERTEXARRAYSPROC)&OOBadOpenGLExtensionUsed;
PFNGLDELETEBUFFERSPROC					glDeleteBuffers					= (PFNGLDELETEBUFFERSPROC)&OOBadOpenGLExtensionUsed;
PFNGLDRAWBUFFERSPROC						glDrawBuffers					= (PFNGLDRAWBUFFERSPROC)&OOBadOpenGLExtensionUsed;
PFNGLCHECKFRAMEBUFFERSTATUSPROC			glCheckFramebufferStatus			= (PFNGLCHECKFRAMEBUFFERSTATUSPROC)&OOBadOpenGLExtensionUsed;
PFNGLTEXIMAGE2DMULTISAMPLEPROC				glTexImage2DMultisample			= (PFNGLTEXIMAGE2DMULTISAMPLEPROC)&OOBadOpenGLExtensionUsed;
PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC		glRenderbufferStorageMultisample	= (PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC)&OOBadOpenGLExtensionUsed;
PFNGLBLITFRAMEBUFFERPROC					glBlitFramebuffer					= (PFNGLBLITFRAMEBUFFERPROC)&OOBadOpenGLExtensionUsed;
PFNGLCLAMPCOLORPROC						glClampColor					= (PFNGLCLAMPCOLORPROC)&OOBadOpenGLExtensionUsed;
#endif                                                                    
#endif


namespace {
constexpr const char *kOOLogOpenGLShaderSupport		= "rendering.opengl.shader.support";
}


namespace {

OOOpenGLExtensionManager *sSingleton = nullptr;	// +1, never released (the retained singleton)

}	// namespace


// Read integer from string, advancing string to end of read data.
static unsigned IntegerFromString(const GLubyte **ioString);


namespace {

std::vector<std::string> ArrayOfExtensions(const std::optional<std::string> &extensionString)
{
	std::vector<std::string> result;
	if (!extensionString.has_value())  return result;
	for (std::string &extStr : oo::str::split(*extensionString, " "))
	{
		if (!extStr.empty())  result.push_back(std::move(extStr));
	}
	return result;
}


// What -initWithUTF8String: gave for a glGetString() result: nil for NULL.
std::optional<std::string> OptionalGLString(const GLubyte *string)
{
	if (string == NULL)  return std::nullopt;
	return std::string(reinterpret_cast<const char *>(string));
}

}	// namespace


void OOOpenGLExtensionManager::reset()
{
	const GLubyte		*versionString = NULL, *curr = NULL;
	
	const std::optional<std::string> extensionsStr = OptionalGLString(glGetString(GL_EXTENSIONS));
	{
		const std::vector<std::string> extensionList = ArrayOfExtensions(extensionsStr);
		extensions = std::set<std::string>(extensionList.begin(), extensionList.end());
	}
	
	vendor = OptionalGLString(glGetString(GL_VENDOR));
	renderer = OptionalGLString(glGetString(GL_RENDERER));
	
	versionString = glGetString(GL_VERSION);
	if (versionString != NULL)
	{
		/*	String is supposed to be "major.minorFOO" or
		 "major.minor.releaseFOO" where FOO is an empty string or
		 a string beginning with space.
		 */
		curr = versionString;
		major = IntegerFromString(&curr);
		if (*curr == '.')
		{
			curr++;
			minor = IntegerFromString(&curr);
		}
		if (*curr == '.')
		{
			curr++;
			release_ = IntegerFromString(&curr);
		}
	}
	
	/*	For aesthetic reasons, cause the ResourceManager to initialize its
	 search paths here. If we don't, the search path dump ends up in
	 the middle of the OpenGL stuff.
	 */
	ResourceManager::paths();
	
	OO_LOG("rendering.opengl.version", "OpenGL renderer version: {}.{}.{} (\"{}\"). Vendor: \"{}\". Renderer: \"{}\".", major, minor, release_, versionString ? reinterpret_cast<const char *>(versionString) : "(null)", vendor.value_or("(null)"), renderer.value_or("(null)"));
	{
		// Listed in byte order of the name (the set's hash order before; proposed ADR-0043).
		std::string extensionList;
		for (const std::string &extension : extensions)
		{
			if (!extensionList.empty())  extensionList += ", ";
			extensionList += extension;
		}
		OO_LOG("rendering.opengl.extensions", "OpenGL extensions ({}):\n{}", extensions.size(), extensionList);
	}
	
	if (!versionIsAtLeastMajor(kMinMajorVersion, kMinMinorVersion))
	{
		OO_LOG("rendering.opengl.version.insufficient", "***** Oolite requires OpenGL version {}.{} or later.", static_cast<unsigned>(kMinMajorVersion), static_cast<unsigned>(kMinMinorVersion));
		OORaiseException("OoliteOpenGLTooOldException", "Oolite requires at least OpenGL %u.%u. You have %u.%u (\"%s\").", kMinMajorVersion, kMinMinorVersion, major, minor, versionString);
	}
	
	const std::optional<std::string> versionStr = OptionalGLString(versionString);
	const oo::PList gpuConfig = lookUpPerGPUSettingsWithVersionString(versionStr, extensionsStr);
	
#if OO_SHADERS
	checkShadersSupported();
	
	if (shadersAvailable)
	{
		defaultShaderSetting = cxx_OOShaderSettingFromString(gpuConfig.get<std::string>("default_shader_level",
																   "SHADERS_FULL"));
		maximumShaderSetting = cxx_OOShaderSettingFromString(gpuConfig.get<std::string>("maximum_shader_level",
																   "SHADERS_FULL"));
		if (maximumShaderSetting <= SHADERS_OFF)
		{
			shadersAvailable = NO;
			maximumShaderSetting = SHADERS_NOT_SUPPORTED;
			{
				// A name that is not a string fell back to the renderer, which may itself be nil.
				const oo::PList *name = gpuConfig.find("name");
				const bool hasName = name != nullptr && (name->isString() || name->isNumber());
				OO_LOG(kOOLogOpenGLShaderSupport, "Shaders will not be used (disallowed for GPU type \"{}\").", hasName ? gpuConfig.get<std::string>("name") : renderer.value_or("(null)"));
			}
		}
		if (maximumShaderSetting < defaultShaderSetting)
		{
			defaultShaderSetting = maximumShaderSetting;
		}
		
		if (shadersAvailable)
		{
			OO_LOG(kOOLogOpenGLShaderSupport, "{}", "Shaders are supported.");
		}
	}
	else
	{
		defaultShaderSetting = SHADERS_NOT_SUPPORTED;
		maximumShaderSetting = SHADERS_NOT_SUPPORTED;
	}
	
	GLint texImageUnitOverride = gpuConfig.get<int>("texture_image_units", textureImageUnitCount_);
	if (texImageUnitOverride < textureImageUnitCount_)  textureImageUnitCount_ = MAX(texImageUnitOverride, 0);
#endif
	
#if OO_USE_VBO
	checkVBOSupported();
#endif
#if OO_USE_FBO
	checkFBOSupported();
#endif
#if OO_MULTITEXTURE
	checkTextureCombinersSupported();
	GLint texUnitOverride = gpuConfig.get<int>("texture_units", textureUnitCount_);
	if (texUnitOverride < textureUnitCount_)  textureUnitCount_ = MAX(texUnitOverride, 0);
#endif
	
	usePointSmoothing_ = gpuConfig.get<bool>("smooth_points", YES) ? YES : NO;
	useLineSmoothing_ = gpuConfig.get<bool>("smooth_lines", YES) ? YES : NO;
	useDustShader_ = gpuConfig.get<bool>("use_dust_shader", YES) ? YES : NO;
}


OOOpenGLExtensionManager::~OOOpenGLExtensionManager()
{
	if (sSingleton == this)  sSingleton = nullptr;
}


OOOpenGLExtensionManager *OOOpenGLExtensionManager::sharedManager()
{
	// NOTE: assumes single-threaded first access. See header.
	if (sSingleton == nullptr)
	{
		// The singleton category's +allocWithZone: recorded the instance before -init ran
		// -reset, so it is recorded here before reset() runs too.
		sSingleton = oo::makeRef<OOOpenGLExtensionManager>().leakRef();
		sSingleton->reset();
	}
	return sSingleton;
}


bool OOOpenGLExtensionManager::haveExtension(const std::string &extension)
{
// The Foundation set was documented as thread-safe under OS X, but I'm not sure about GNUstep. -- Ahruman
#if OOOPENGLEXTMGR_LOCK_SET_ACCESS
	lock.lock();
#endif
	
	BOOL result = extensions.contains(extension) ? YES : NO;
	
#if OOOPENGLEXTMGR_LOCK_SET_ACCESS
	lock.unlock();
#endif
	
	return result;
}


bool OOOpenGLExtensionManager::shadersSupported()
{
#if OO_SHADERS
	return shadersAvailable;
#else
	return NO;
#endif
}


bool OOOpenGLExtensionManager::shadersForceDisabled()
{
#if OO_SHADERS
	return shadersForceDisabled_;
#else
	return YES;
#endif
}


OOGraphicsDetail OOOpenGLExtensionManager::defaultDetailLevel()
{
#if OO_SHADERS
	if (defaultShaderSetting < SHADERS_FULL)
	{
		return DETAIL_LEVEL_MINIMUM;
	}
	else
	{
		return DETAIL_LEVEL_MAXIMUM;
	}
#else
	return SHADERS_NOT_SUPPORTED;
#endif
}


OOGraphicsDetail OOOpenGLExtensionManager::maximumDetailLevel()
{
#if OO_SHADERS
	if (maximumShaderSetting < SHADERS_FULL)
	{
		return DETAIL_LEVEL_MINIMUM;
	}
	else
	{
		return DETAIL_LEVEL_MAXIMUM;
	}
#else
	return DETAIL_LEVEL_MINIMUM;
#endif
}


GLint OOOpenGLExtensionManager::textureImageUnitCount()
{
#if OO_SHADERS
	return textureImageUnitCount_;
#else
	return 0;
#endif
}


bool OOOpenGLExtensionManager::vboSupported()
{
#if OO_USE_VBO
	return vboSupported_;
#else
	return NO;
#endif
}


bool OOOpenGLExtensionManager::fboSupported()
{
#if OO_USE_FBO
	return fboSupported_;
#else
	return NO;
#endif
}


bool OOOpenGLExtensionManager::textureCombinersSupported()
{
#if OO_MULTITEXTURE
	return textureCombinersSupported_;
#else
	return NO;
#endif
}


GLint OOOpenGLExtensionManager::textureUnitCount()
{
#if OO_MULTITEXTURE
	return textureUnitCount_;
#else
	return 0;
#endif
}


NSUInteger OOOpenGLExtensionManager::majorVersionNumber()
{
	return major;
}


NSUInteger OOOpenGLExtensionManager::minorVersionNumber()
{
	return minor;
}


NSUInteger OOOpenGLExtensionManager::releaseVersionNumber()
{
	return release_;
}


void OOOpenGLExtensionManager::getVersionMajor(unsigned *outMajor, unsigned *outMinor, unsigned *outRelease)
{
	if (outMajor != NULL)  *outMajor = major;
	if (outMinor != NULL)  *outMinor = minor;
	if (outRelease != NULL)  *outRelease = release_;
}


bool OOOpenGLExtensionManager::versionIsAtLeastMajor(unsigned maj, unsigned min)
{
	return major > maj || (major == maj && minor >= min);
}


std::optional<std::string> OOOpenGLExtensionManager::vendorString()
{
	return vendor;
}


std::optional<std::string> OOOpenGLExtensionManager::rendererString()
{
	return renderer;
}


bool OOOpenGLExtensionManager::usePointSmoothing()
{
	return usePointSmoothing_;
}


bool OOOpenGLExtensionManager::useLineSmoothing()
{
	return useLineSmoothing_;
}


bool OOOpenGLExtensionManager::useDustShader()
{
	return useDustShader_;
}


static unsigned IntegerFromString(const GLubyte **ioString)
{
	if (EXPECT_NOT(ioString == NULL))  return 0;
	
	unsigned		result = 0;
	const GLubyte	*curr = *ioString;
	
	while ('0' <= *curr && *curr <= '9')
	{
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
void OOOpenGLExtensionManager::checkShadersSupported()
{
	shadersAvailable = NO;
	shadersForceDisabled_ = NO;

	/* Some cards claim to support shaders but do so extremely
	 * badly. These are listed in gpu-settings.plist where we know
	 * about them; for those we don't being able to run with
	 * -noshaders may help get the game up and running at a frame rate
	 * where thegraphics settings can be changed.  - CIM */
	// scan for shader overrides: -noshaders || --noshaders
	for (const std::string &arg : oo::process::arguments())
	{
		if (arg == "-noshaders" || arg == "--noshaders")
		{
			shadersForceDisabled_ = YES;
			OO_LOG(kOOLogOpenGLShaderSupport, "{}", "Shaders will not be used (disabled on command line).");
			return;
		}
	}	

	const char * const requiredExtension[] =
						{
							"GL_ARB_shading_language_100",
							"GL_ARB_fragment_shader",
							"GL_ARB_vertex_shader",
							"GL_ARB_multitexture",
							"GL_ARB_shader_objects",
							NULL	// sentinel - don't remove!
						};
	const char * const *required = NULL;
	
	for (required = requiredExtension; *required != NULL; ++required)
	{
		if (!haveExtension(*required))
		{
			OO_LOG(kOOLogOpenGLShaderSupport, "Shaders will not be used (OpenGL extension {} is not available).", *required);
			return;
		}
	}
	
#if OOLITE_WINDOWS
	glGetObjectParameterivARB	=	(PFNGLGETOBJECTPARAMETERIVARBPROC)wglGetProcAddress("glGetObjectParameterivARB");
	glCreateShaderObjectARB		=	(PFNGLCREATESHADEROBJECTARBPROC)wglGetProcAddress("glCreateShaderObjectARB");
	glGetInfoLogARB				=	(PFNGLGETINFOLOGARBPROC)wglGetProcAddress("glGetInfoLogARB");
	glCreateProgramObjectARB	=	(PFNGLCREATEPROGRAMOBJECTARBPROC)wglGetProcAddress("glCreateProgramObjectARB");
	glAttachObjectARB			=	(PFNGLATTACHOBJECTARBPROC)wglGetProcAddress("glAttachObjectARB");
	glDeleteObjectARB			=	(PFNGLDELETEOBJECTARBPROC)wglGetProcAddress("glDeleteObjectARB");
	glLinkProgramARB			=	(PFNGLLINKPROGRAMARBPROC)wglGetProcAddress("glLinkProgramARB");
	glCompileShaderARB			=	(PFNGLCOMPILESHADERARBPROC)wglGetProcAddress("glCompileShaderARB");
	glShaderSourceARB			=	(PFNGLSHADERSOURCEARBPROC)wglGetProcAddress("glShaderSourceARB");
	glUseProgramObjectARB		=	(PFNGLUSEPROGRAMOBJECTARBPROC)wglGetProcAddress("glUseProgramObjectARB");
	glActiveTextureARB			=	(PFNGLACTIVETEXTUREARBPROC)wglGetProcAddress("glActiveTextureARB");
	glGetUniformLocationARB		=	(PFNGLGETUNIFORMLOCATIONARBPROC)wglGetProcAddress("glGetUniformLocationARB");
	glUniform1iARB				=	(PFNGLUNIFORM1IARBPROC)wglGetProcAddress("glUniform1iARB");
	glUniform1fARB				=	(PFNGLUNIFORM1FARBPROC)wglGetProcAddress("glUniform1fARB");
	glUniformMatrix3fvARB		=	(PFNGLUNIFORMMATRIX3FVARBPROC)wglGetProcAddress("glUniformMatrix3fvARB");
	glUniformMatrix4fvARB		=	(PFNGLUNIFORMMATRIX4FVARBPROC)wglGetProcAddress("glUniformMatrix4fvARB");
	glUniform4fvARB				=	(PFNGLUNIFORM4FVARBPROC)wglGetProcAddress("glUniform4fvARB");
	glUniform2fvARB				=	(PFNGLUNIFORM2FVARBPROC)wglGetProcAddress("glUniform2fvARB");
	glBindAttribLocationARB		=	(PFNGLBINDATTRIBLOCATIONARBPROC)wglGetProcAddress("glBindAttribLocationARB");
	glEnableVertexAttribArrayARB =	(PFNGLENABLEVERTEXATTRIBARRAYARBPROC)wglGetProcAddress("glEnableVertexAttribArrayARB");
	glVertexAttribPointerARB	=	(PFNGLVERTEXATTRIBPOINTERARBPROC)wglGetProcAddress("glVertexAttribPointerARB");
	glDisableVertexAttribArrayARB =	(PFNGLDISABLEVERTEXATTRIBARRAYARBPROC)wglGetProcAddress("glDisableVertexAttribArrayARB");
	glValidateProgramARB		=	(PFNGLVALIDATEPROGRAMARBPROC)wglGetProcAddress("glValidateProgramARB");
#endif
	
	glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS_ARB, &textureImageUnitCount_);
	
	shadersAvailable = YES;
}
#endif


#if OO_USE_VBO
void OOOpenGLExtensionManager::checkVBOSupported()
{
	vboSupported_ = NO;
	
	if (versionIsAtLeastMajor(1, 5) || haveExtension("GL_ARB_vertex_buffer_object"))
	{
		vboSupported_ = YES;
	}
	
#if OOLITE_WINDOWS
	if (vboSupported_)
	{
		glGenBuffersARB = (PFNGLGENBUFFERSARBPROC)wglGetProcAddress("glGenBuffersARB");
		glDeleteBuffersARB = (PFNGLDELETEBUFFERSARBPROC)wglGetProcAddress("glDeleteBuffersARB");
		glBindBufferARB = (PFNGLBINDBUFFERARBPROC)wglGetProcAddress("glBindBufferARB");
		glBufferDataARB = (PFNGLBUFFERDATAARBPROC)wglGetProcAddress("glBufferDataARB");
	}
#endif
}
#endif


#if OO_USE_FBO
void OOOpenGLExtensionManager::checkFBOSupported()
{
	fboSupported_ = NO;
	
	if (haveExtension("GL_EXT_framebuffer_object"))
	{
		fboSupported_ = YES;
	}
	
#if OOLITE_WINDOWS
	if (fboSupported_)
	{
		glGenFramebuffersEXT = (PFNGLGENFRAMEBUFFERSEXTPROC)wglGetProcAddress("glGenFramebuffersEXT");
		glBindFramebufferEXT = (PFNGLBINDFRAMEBUFFEREXTPROC)wglGetProcAddress("glBindFramebufferEXT");
		glGenRenderbuffersEXT = (PFNGLGENRENDERBUFFERSEXTPROC)wglGetProcAddress("glGenRenderbuffersEXT");
		glBindRenderbufferEXT = (PFNGLBINDRENDERBUFFEREXTPROC)wglGetProcAddress("glBindRenderbufferEXT");
		glRenderbufferStorageEXT = (PFNGLRENDERBUFFERSTORAGEEXTPROC)wglGetProcAddress("glRenderbufferStorageEXT");
		glFramebufferRenderbufferEXT = (PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC)wglGetProcAddress("glFramebufferRenderbufferEXT");
		glFramebufferTexture2DEXT = (PFNGLFRAMEBUFFERTEXTURE2DEXTPROC)wglGetProcAddress("glFramebufferTexture2DEXT");
		glCheckFramebufferStatusEXT = (PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC)wglGetProcAddress("glCheckFramebufferStatusEXT");
		glDeleteFramebuffersEXT = (PFNGLDELETEFRAMEBUFFERSEXTPROC)wglGetProcAddress("glDeleteFramebuffersEXT");
		glDeleteRenderbuffersEXT = (PFNGLDELETERENDERBUFFERSEXTPROC)wglGetProcAddress("glDeleteRenderbuffersEXT");
		glGenRenderbuffers = (PFNGLGENRENDERBUFFERSPROC)wglGetProcAddress("glGenRenderbuffers");
		glBindRenderbuffer			= (PFNGLBINDRENDERBUFFERPROC)wglGetProcAddress			("glBindRenderbuffer"			);
		glRenderbufferStorage		= (PFNGLRENDERBUFFERSTORAGEPROC)wglGetProcAddress		("glRenderbufferStorage"		);
		glGenFramebuffers			= (PFNGLGENFRAMEBUFFERSPROC)wglGetProcAddress			("glGenFramebuffers"			);
		glBindFramebuffer			= (PFNGLBINDFRAMEBUFFERPROC)wglGetProcAddress			("glBindFramebuffer"			);
		glFramebufferRenderbuffer	= (PFNGLFRAMEBUFFERRENDERBUFFERPROC)wglGetProcAddress	("glFramebufferRenderbuffer"	);
		glFramebufferTexture2D		= (PFNGLFRAMEBUFFERTEXTURE2DPROC)wglGetProcAddress		("glFramebufferTexture2D"		);
		glGenVertexArrays			= (PFNGLGENVERTEXARRAYSPROC)wglGetProcAddress			("glGenVertexArrays"			);
		glGenBuffers				= (PFNGLGENBUFFERSPROC)wglGetProcAddress				("glGenBuffers"					);
		glBindVertexArray			= (PFNGLBINDVERTEXARRAYPROC)wglGetProcAddress			("glBindVertexArray"			);
		glBindBuffer				= (PFNGLBINDBUFFERPROC)wglGetProcAddress				("glBindBuffer"					);
		glBufferData				= (PFNGLBUFFERDATAPROC)wglGetProcAddress				("glBufferData"					);
		glVertexAttribPointer		= (PFNGLVERTEXATTRIBPOINTERPROC)wglGetProcAddress		("glVertexAttribPointer"		);
		glEnableVertexAttribArray	= (PFNGLENABLEVERTEXATTRIBARRAYPROC)wglGetProcAddress	("glEnableVertexAttribArray"	);
		glUseProgram				= (PFNGLUSEPROGRAMPROC)	wglGetProcAddress				("glUseProgram"					);
		glGetUniformLocation		= (PFNGLGETUNIFORMLOCATIONPROC)wglGetProcAddress		("glGetUniformLocation"			);
		glUniform1i					= (PFNGLUNIFORM1IPROC)wglGetProcAddress					("glUniform1i"					);
		glActiveTexture				= (PFNGLACTIVETEXTUREPROC)wglGetProcAddress				("glActiveTexture"				);
		glBlendFuncSeparate			= (PFNGLBLENDFUNCSEPARATEPROC)wglGetProcAddress			("glBlendFuncSeparate"			);
		glUniform1f					= (PFNGLUNIFORM1FPROC)wglGetProcAddress					("glUniform1f"					);
		glUniform2fv				= (PFNGLUNIFORM2FVPROC)wglGetProcAddress				("glUniform2fv"					);
		glDeleteRenderbuffers		= (PFNGLDELETERENDERBUFFERSPROC)wglGetProcAddress		("glDeleteRenderbuffer"			);
		glDeleteFramebuffers		= (PFNGLDELETEFRAMEBUFFERSPROC)wglGetProcAddress		("glDeleteFramebuffers"			);
		glDeleteVertexArrays		= (PFNGLDELETEVERTEXARRAYSPROC)wglGetProcAddress		("glDeleteVertexArrays"			);
		glDeleteBuffers				= (PFNGLDELETEBUFFERSPROC)wglGetProcAddress				("glDeleteBuffers"				);
		glDrawBuffers				= (PFNGLDRAWBUFFERSPROC)wglGetProcAddress				("glDrawBuffers"				);
		glCheckFramebufferStatus		= (PFNGLCHECKFRAMEBUFFERSTATUSPROC)wglGetProcAddress		("glCheckFramebufferStatus"				);
		glTexImage2DMultisample		= (PFNGLTEXIMAGE2DMULTISAMPLEPROC)wglGetProcAddress		("glTexImage2DMultisample"					);
		glRenderbufferStorageMultisample = (PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC)wglGetProcAddress ("glRenderbufferStorageMultisample"	);
		glBlitFramebuffer			= (PFNGLBLITFRAMEBUFFERPROC)wglGetProcAddress			("glBlitFramebuffer"			);
		glClampColor				= (PFNGLCLAMPCOLORPROC)wglGetProcAddress				("glClampColor"					);
	}
#endif
}
#endif


#if OO_MULTITEXTURE
void OOOpenGLExtensionManager::checkTextureCombinersSupported()
{
	textureCombinersSupported_ = haveExtension("GL_ARB_texture_env_combine");
	
	if (textureCombinersSupported_)
	{
		OOGL(glGetIntegerv(GL_MAX_TEXTURE_UNITS_ARB, &textureUnitCount_));
		
#if OOLITE_WINDOWS
		// Duplicated in checkShadersSupported. but that's not really a problem.
		glActiveTextureARB = (PFNGLACTIVETEXTUREARBPROC)wglGetProcAddress("glActiveTextureARB");
		
		glClientActiveTextureARB = (PFNGLCLIENTACTIVETEXTUREARBPROC)wglGetProcAddress("glClientActiveTextureARB");
#endif
	}
	else
	{
		textureUnitCount_ = 1;
	}

}
#endif


namespace {

// The regexp test sent to a string that may be nil (a nil string matched nothing). matcher is the
// one pass's matcher, taken on first use and held by the caller: the autoreleased Objective-C
// matcher lived until the pool drained, so one pass compiled one tester (ADR-0056 amendment
// oo-ct7c item 3). A null matcher (the tester did not compile) answers NO and is asked again.
BOOL MatchesRegExp(oo::Ref<::OORegExpMatcher> &matcher, const std::optional<std::string> &string, const std::string &regexp)
{
	if (!string.has_value())  return NO;
	if (matcher == nullptr)  matcher = ::OORegExpMatcher::regExpMatcher();
	if (matcher == nullptr)  return NO;
	return matcher->string(*string, regexp);
}


// regexps may be a single string or an array of strings (in which case results are ANDed).
BOOL CheckRegExps(oo::Ref<::OORegExpMatcher> &matcher, const std::optional<std::string> &string, const oo::PList &regexps)
{
	if (regexps.isNull())  return YES;	// No restriction == match.
	if (const std::string *regexp = regexps.getIf<std::string>())
	{
		return MatchesRegExp(matcher, string, *regexp);
	}
	if (const oo::PList::Array *array = regexps.getIf<oo::PList::Array>())
	{
		for (const oo::PList &element : *array)
		{
			const std::string *regexp = element.getIf<std::string>();
			if (EXPECT_NOT(regexp == nullptr))
			{
				// Invalid type -- match fails.
				return NO;
			}

			if (!MatchesRegExp(matcher, string, *regexp))  return NO;
		}
		return YES;
	}

	// Invalid type -- match fails.
	return NO;
}


// oo_stringForKey: on a dictionary that may be nil: a string, a number's string value, or nil.
oo::PList StringForKey(const oo::PList *dict, std::string_view key)
{
	const oo::PList *value = (dict != nullptr) ? dict->find(key) : nullptr;
	if (value == nullptr || !(value->isString() || value->isNumber()))  return oo::PList();
	return oo::PList(dict->get<std::string>(key));
}

}	// namespace


oo::PList OOOpenGLExtensionManager::lookUpPerGPUSettingsWithVersionString(const std::optional<std::string> &versionStr, const std::optional<std::string> &extensionsStr)
{
	const oo::PList configurations = ResourceManager::dictionaryFromFilesNamed("gpu-settings.plist", "Config", YES);

	// Highest precedence first, then case-insensitive name order (keys were taken in hash order
	// before sorting; ties between names equal but for case now keep byte order).
	std::vector<std::string> keys;
	if (const oo::PList::Dict *dict = configurations.getIf<oo::PList::Dict>())
	{
		for (const auto &entry : *dict)  keys.push_back(entry.first);
	}
	std::stable_sort(keys.begin(), keys.end(), [&configurations](const std::string &keyA, const std::string &keyB)
	{
		const oo::PList	*dictA = configurations.get<oo::PList::Dict>(keyA);
		const oo::PList	*dictB = configurations.get<oo::PList::Dict>(keyB);
		const double	precedenceA = dictA != nullptr ? dictA->get<double>("precedence", 1) : 0;
		const double	precedenceB = dictB != nullptr ? dictB->get<double>("precedence", 1) : 0;

		if (precedenceA != precedenceB)  return precedenceA > precedenceB;
		return oo::str::caseInsensitiveCompare(keyA, keyB) < 0;
	});

	oo::Ref<::OORegExpMatcher> matcher;	// one for the pass (see MatchesRegExp)
	for (const std::string &key : keys)
	{
		const oo::PList *config = configurations.get<oo::PList::Dict>(key);
		if (EXPECT_NOT(config == nullptr))  continue;

		const oo::PList *match = config->get<oo::PList::Dict>("match");
		const oo::PList *vendorExpr = (match != nullptr) ? match->find("vendor") : nullptr;

		if (!CheckRegExps(matcher, vendor, vendorExpr != nullptr ? *vendorExpr : oo::PList()))  continue;

		if (!CheckRegExps(matcher, renderer, StringForKey(match, "renderer")))  continue;

		if (!CheckRegExps(matcher, versionStr, StringForKey(match, "version")))  continue;

		if (!CheckRegExps(matcher, extensionsStr, StringForKey(match, "extensions")))  continue;

		OO_LOG("rendering.opengl.gpuSpecific", "Matched GPU configuration \"{}\".", key);
		return *config;
	}

	return oo::PList(oo::PList::Dict{});
}

// The singleton category (+allocWithZone:, and -retain/-release/-autorelease doing nothing) is
// not translated: the one instance is made only by sharedManager() and never released (proposed
// ADR-0056 amendment oo-r7m0).


#if OOLITE_WINDOWS

static void OOBadOpenGLExtensionUsed(void)
{
	OO_LOG("rendering.opengl.badExtension", "{}", "***** An uninitialized OpenGL extension function has been called, terminating. This is a serious error, please report it. *****");
	exit(EXIT_FAILURE);
}

#endif
