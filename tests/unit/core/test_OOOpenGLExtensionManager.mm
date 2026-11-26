/*	test_OOOpenGLExtensionManager.mm
	Unit tests for OOOpenGLExtensionManager (src/Core/OOOpenGLExtensionManager.h): bead oo-z1s4,
	a Phase 3 class conversion (proposed ADR-0056).

	The manager reads the machine's own OpenGL (a hidden window's context, oo_gl_test_context.hpp),
	so its answers are checked against what the test reads from OpenGL itself: the version parsed
	from GL_VERSION, the vendor and renderer strings, the extension list, the texture unit limits.
	The GPU settings (gpu-settings.plist) come from this file's ResourceManager stub, so the
	matching is pinned exactly: precedence order, a regexp array ANDed, the first match wins, and
	what a match overrides. OORegExpMatcher and cxx_OOShaderSettingFromString are stubs as well
	(the real ones reach the script engine and the Universe). The expectations were written
	against the Objective-C API and run on the unconverted class first; the last test pins the
	facade's contract once the class is C++.
	Run: bash tools/check-core-tests.sh
*/

#import "OOOpenGLExtensionManager.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Process.hpp"

#include <cstdio>
#include <regex>
#include <sstream>
#include <string>


// --- Stubs of what the manager calls ------------------------------------------------------------

static unsigned sPathsCalls = 0;
static oo::PList sGPUSettings = oo::PList(oo::PList::Dict{});


@interface ResourceManager: OOObject

+ (std::vector<std::string>) cxx_paths;
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles;

@end


@implementation ResourceManager

+ (std::vector<std::string>) cxx_paths
{
	sPathsCalls++;
	return {};
}


+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles
{
	if (fileName != "gpu-settings.plist" || folderName != "Config" || !mergeFiles)  return oo::PList();
	return sGPUSettings;
}

@end


@interface OORegExpMatcher: OOObject

+ (instancetype) regExpMatcher;
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp;

@end


@implementation OORegExpMatcher

+ (instancetype) regExpMatcher
{
	return [[[self alloc] init] autorelease];
}


- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp
{
	return std::regex_search(string, std::regex(regExp)) ? YES : NO;
}

@end


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	if (string == "SHADERS_OFF")  return SHADERS_OFF;
	if (string == "SHADERS_SIMPLE")  return SHADERS_SIMPLE;
	if (string == "SHADERS_FULL")  return SHADERS_FULL;
	return SHADERS_NOT_SUPPORTED;
}


// --- What OpenGL itself says --------------------------------------------------------------------

namespace {

std::string GLString(GLenum name)
{
	const GLubyte *s = glGetString(name);
	return s != nullptr ? std::string(reinterpret_cast<const char *>(s)) : std::string();
}


std::vector<std::string> GLExtensions()
{
	std::vector<std::string> result;
	std::istringstream words(GLString(GL_EXTENSIONS));
	for (std::string word; words >> word; )  result.push_back(word);
	return result;
}


bool GLHasExtension(const std::string &name)
{
	for (const std::string &e : GLExtensions())  if (e == name)  return true;
	return false;
}


bool GLHasShaderExtensions()
{
	return GLHasExtension("GL_ARB_shading_language_100") && GLHasExtension("GL_ARB_fragment_shader") && GLHasExtension("GL_ARB_vertex_shader") && GLHasExtension("GL_ARB_multitexture") && GLHasExtension("GL_ARB_shader_objects");
}


void GLVersion(unsigned *major, unsigned *minor, unsigned *release)
{
	*major = *minor = *release = 0;
	std::sscanf(GLString(GL_VERSION).c_str(), "%u.%u.%u", major, minor, release);
}


oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}


void SetArguments(std::initializer_list<const char *> args)
{
	std::vector<const char *> argv(args);
	oo::process::setArguments(static_cast<int>(argv.size()), argv.data());
}

}	// namespace


// --- Tests --------------------------------------------------------------------------------------

OO_TEST(readsTheDriver)
{
	OO_CHECK(OOTestGLContext());
	SetArguments({ "test_OOOpenGLExtensionManager" });

	@autoreleasepool
	{
		cxx::OOOpenGLExtensionManager *manager = cxx::OOOpenGLExtensionManager::sharedManager();
		OO_CHECK(manager != nullptr);
		OO_CHECK(cxx::OOOpenGLExtensionManager::sharedManager() == manager);
		OO_CHECK(sPathsCalls == 1);	// the resource paths are set up while the manager initialises

		unsigned major, minor, release;
		GLVersion(&major, &minor, &release);
		OO_CHECK(major >= 3);
		OO_CHECK(manager->majorVersionNumber() == major);
		OO_CHECK(manager->minorVersionNumber() == minor);
		OO_CHECK(manager->releaseVersionNumber() == release);
		unsigned gotMajor = 99, gotMinor = 99, gotRelease = 99;
		manager->getVersionMajor(&gotMajor, &gotMinor, &gotRelease);
		OO_CHECK(gotMajor == major && gotMinor == minor && gotRelease == release);
		manager->getVersionMajor(NULL, &gotMinor, NULL);	// NULL outs are skipped
		OO_CHECK(gotMinor == minor);
		OO_CHECK(manager->versionIsAtLeastMajor(major, minor));
		OO_CHECK(manager->versionIsAtLeastMajor(major - 1, minor + 100));
		OO_CHECK(!manager->versionIsAtLeastMajor(major, minor + 1));
		OO_CHECK(!manager->versionIsAtLeastMajor(major + 1, 0));

		OO_CHECK(manager->vendorString() == std::optional<std::string>(GLString(GL_VENDOR)));
		OO_CHECK(manager->rendererString() == std::optional<std::string>(GLString(GL_RENDERER)));

		const std::vector<std::string> extensions = GLExtensions();
		OO_CHECK(!extensions.empty());
		for (const std::string &e : extensions)  OO_CHECK(manager->haveExtension(e));
		OO_CHECK(!manager->haveExtension("GL_OO_no_such_extension"));
		OO_CHECK(!manager->haveExtension(""));

		// The empty GPU settings leave every default in place.
		OO_CHECK(manager->shadersForceDisabled() == NO);
		OO_CHECK(manager->shadersSupported() == (GLHasShaderExtensions() ? YES : NO));
		OO_CHECK(manager->usePointSmoothing() && manager->useLineSmoothing() && manager->useDustShader());
		OO_CHECK(manager->vboSupported() == NO);	// OO_USE_VBO is 0
		OO_CHECK(manager->fboSupported() == (GLHasExtension("GL_EXT_framebuffer_object") ? YES : NO));
		OO_CHECK(manager->textureCombinersSupported() == (GLHasExtension("GL_ARB_texture_env_combine") ? YES : NO));

		GLint units = 1;
		if (manager->textureCombinersSupported())  glGetIntegerv(GL_MAX_TEXTURE_UNITS_ARB, &units);
		OO_CHECK(manager->textureUnitCount() == units);
		if (manager->shadersSupported())
		{
			GLint imageUnits = 0;
			glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS_ARB, &imageUnits);
			OO_CHECK(manager->textureImageUnitCount() == imageUnits);
			OO_CHECK(manager->defaultDetailLevel() == DETAIL_LEVEL_MAXIMUM);
			OO_CHECK(manager->maximumDetailLevel() == DETAIL_LEVEL_MAXIMUM);
		}
		OO_CHECK(OOShadersSupported() == manager->shadersSupported());
	}
}


OO_TEST(gpuSettingsMatchInPrecedenceOrder)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		cxx::OOOpenGLExtensionManager *manager = cxx::OOOpenGLExtensionManager::sharedManager();
		const BOOL shaders = GLHasShaderExtensions() ? YES : NO;

		sGPUSettings = Dict({
			// Highest precedence, but its regexp array needs both to match: it does not.
			{ "a-strict", Dict({ { "precedence", oo::PList(5) },
				{ "match", Dict({ { "vendor", oo::PList(oo::PList::Array{ oo::PList("."), oo::PList("^no such vendor$") }) } }) },
				{ "smooth_lines", oo::PList(false) } }) },
			// Matches everything (every regexp in the array matches), and wins over the default 1.
			{ "b-any", Dict({ { "precedence", oo::PList(2) },
				{ "match", Dict({ { "vendor", oo::PList(oo::PList::Array{ oo::PList("."), oo::PList("") }) },
								  { "version", oo::PList("^[0-9]") } }) },
				{ "default_shader_level", oo::PList("SHADERS_SIMPLE") },
				{ "smooth_points", oo::PList(false) },
				{ "use_dust_shader", oo::PList(false) },
				{ "texture_units", oo::PList(1) },
				{ "texture_image_units", oo::PList(2) } }) },
			// Also matches, but loses on precedence.
			{ "c-any", Dict({ { "match", Dict({}) }, { "smooth_lines", oo::PList(false) } }) },
		});
		manager->reset();
		OO_CHECK(sPathsCalls == 2);

		OO_CHECK(manager->usePointSmoothing() == NO);
		OO_CHECK(manager->useLineSmoothing() == YES);
		OO_CHECK(manager->useDustShader() == NO);
		if (manager->textureCombinersSupported())  OO_CHECK(manager->textureUnitCount() == 1);
		if (shaders)
		{
			OO_CHECK(manager->shadersSupported());
			OO_CHECK(manager->textureImageUnitCount() == 2);
			OO_CHECK(manager->defaultDetailLevel() == DETAIL_LEVEL_MINIMUM);	// SHADERS_SIMPLE < SHADERS_FULL
			OO_CHECK(manager->maximumDetailLevel() == DETAIL_LEVEL_MAXIMUM);
		}

		// An override can only lower a limit; a maximum of SHADERS_OFF turns shaders off.
		sGPUSettings = Dict({
			{ "d-off", Dict({ { "name", oo::PList("test GPU") },
				{ "maximum_shader_level", oo::PList("SHADERS_OFF") },
				{ "texture_units", oo::PList(1000) },
				{ "texture_image_units", oo::PList(-4) } }) },
		});
		manager->reset();
		OO_CHECK(manager->shadersSupported() == NO);
		OO_CHECK(manager->usePointSmoothing() && manager->useLineSmoothing() && manager->useDustShader());
		if (shaders)
		{
			OO_CHECK(manager->textureImageUnitCount() == 0);
			OO_CHECK(manager->defaultDetailLevel() == DETAIL_LEVEL_MINIMUM);
			OO_CHECK(manager->maximumDetailLevel() == DETAIL_LEVEL_MINIMUM);
		}
		GLint units = 1;
		if (manager->textureCombinersSupported())  glGetIntegerv(GL_MAX_TEXTURE_UNITS_ARB, &units);
		OO_CHECK(manager->textureUnitCount() == units);

		sGPUSettings = oo::PList(oo::PList::Dict{});
		manager->reset();
		OO_CHECK(manager->shadersSupported() == shaders);
	}
}


OO_TEST(noShadersArgument)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		cxx::OOOpenGLExtensionManager *manager = cxx::OOOpenGLExtensionManager::sharedManager();
		SetArguments({ "test_OOOpenGLExtensionManager", "--noshaders" });
		manager->reset();
		OO_CHECK(manager->shadersForceDisabled() == YES);
		OO_CHECK(manager->shadersSupported() == NO);
		OO_CHECK(OOShadersSupported() == NO);
		OO_CHECK(manager->defaultDetailLevel() == DETAIL_LEVEL_MINIMUM);
		OO_CHECK(manager->maximumDetailLevel() == DETAIL_LEVEL_MINIMUM);

		SetArguments({ "test_OOOpenGLExtensionManager" });
		manager->reset();
		OO_CHECK(manager->shadersForceDisabled() == NO);
		OO_CHECK(manager->shadersSupported() == (GLHasShaderExtensions() ? YES : NO));
	}
}


// After the conversion: the facade answers as the C++ class does, one facade for the process.
OO_TEST(facadeContract)
{
	OO_CHECK(OOTestGLContext());
	cxx::OOOpenGLExtensionManager *manager = cxx::OOOpenGLExtensionManager::sharedManager();
	@autoreleasepool
	{
		OOOpenGLExtensionManager *facade = [OOOpenGLExtensionManager sharedManager];
		OO_CHECK(facade != nil);
		OO_CHECK(oo::ToCxx(facade) == manager);
		OO_CHECK(oo::ToObjC(manager) == facade);
		OO_CHECK([facade majorVersionNumber] == manager->majorVersionNumber());
		OO_CHECK([facade minorVersionNumber] == manager->minorVersionNumber());
		OO_CHECK([facade rendererString] == manager->rendererString());
		OO_CHECK([facade haveExtension:"GL_OO_no_such_extension"] == NO);
		OO_CHECK([facade shadersSupported] == manager->shadersSupported());
		OO_CHECK([facade textureUnitCount] == manager->textureUnitCount());
		unsigned major = 0;
		[facade getVersionMajor:&major minor:NULL release:NULL];
		OO_CHECK(major == manager->majorVersionNumber());
	}
	@autoreleasepool
	{
		// Still the same facade after its first pool drained.
		OO_CHECK(oo::ToCxx([OOOpenGLExtensionManager sharedManager]) == manager);
		OO_CHECK(oo::ToObjC(manager) == [OOOpenGLExtensionManager sharedManager]);
	}

	OOOpenGLExtensionManager *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOOpenGLExtensionManager *>(nullptr)) == nil);
	OO_CHECK([none textureUnitCount] == 0);
}


OO_TEST_MAIN()
