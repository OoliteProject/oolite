/*	test_OOOpenGLStateManager.mm
	Characterisation tests for the OpenGL state manager (src/Core/OOOpenGLStateManager.mm,
	declared in OOOpenGL.h): bead oo-rlaz.

	OOOpenGLStateManager.mm has no @implementation, so it is not a Phase 3 class conversion
	(CLAUDE.md rule 9, ADR-0012); it is plain C++ over OpenGL and stays as it is. This test pins
	what it does to OpenGL, so that the classes converted around it (and the file's own rename in
	Phase 4) can be shown not to change the GL state: after OOSetOpenGLState(state), from the
	context's initial state and from every other standard state, each item of
	OOOpenGLStates.tbl reads back as the state table says (items the table leaves open,
	kStateMaybe, are not read), including the blend function set with one glBlendFunc call.
	The GL context is a hidden window's (oo_gl_test_context.hpp); the extension manager, which
	loads the multitexture entry points, runs with its collaborators stubbed as in
	test_OOOpenGLExtensionManager.
	Run: bash tools/check-core-tests.sh
*/

#import "OOOpenGL.h"
#import "OOOpenGLExtensionManager.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"
#include "oofnd/PList.hpp"

#include <cstdio>
#include <string>
#include <vector>


// --- Stubs --------------------------------------------------------------------------------------

@interface ResourceManager: OOObject
+ (std::vector<std::string>) cxx_paths;
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles;
@end

@implementation ResourceManager
+ (std::vector<std::string>) cxx_paths  { return {}; }
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles  { return oo::PList(oo::PList::Dict{}); }
@end


@interface OORegExpMatcher: OOObject
+ (instancetype) regExpMatcher;
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp;
@end

@implementation OORegExpMatcher
+ (instancetype) regExpMatcher  { return [[[self alloc] init] autorelease]; }
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp  { return NO; }
@end


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	return string == "SHADERS_FULL" ? SHADERS_FULL : SHADERS_NOT_SUPPORTED;
}


// OOLogging.mm's (it would bring the resource manager into the link); only the state dump uses them.
void OOLogIndent(void)  {}
void OOLogOutdent(void)  {}


// --- The state table, as the test expects it ----------------------------------------------------

namespace {

enum Flag { kOff, kOn, kEither };

struct Expected
{
	const char	*name;
	Flag		lighting, light0, light1, texture2D, blend, fog, depthTest, cullFace;
	bool		vertexArray, normalArray, depthWriteMask;
	GLint		blendSrc, blendDst;
};

// In OOOpenGLStateID order: opaque, translucent pass, additive blending, overlay.
const Expected kStates[OPENGL_STATE_INTERNAL_USE_ONLY] =
{
	{ "opaque",			kOn,  kEither, kEither, kOn,  kOff, kEither, kOn,  kOn,  true,  true,  true,  GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA },
	{ "translucent",	kOff, kEither, kEither, kOff, kOff, kEither, kOn,  kOn,  false, false, false, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA },
	{ "additive",		kOff, kEither, kEither, kOff, kOn,  kEither, kOn,  kOff, true,  false, false, GL_SRC_ALPHA, GL_ONE },
	{ "overlay",		kOff, kEither, kEither, kOff, kOn,  kOff,    kOff, kOff, false, false, false, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA },
};


bool FlagIs(GLenum cap, Flag expected)
{
	if (expected == kEither)  return true;
	return (glIsEnabled(cap) == GL_TRUE) == (expected == kOn);
}


GLint Integer(GLenum name)
{
	GLint value = -1;
	glGetIntegerv(name, &value);
	return value;
}


// Every item of OOOpenGLStates.tbl, against the expectation for <state>.
bool Matches(OOOpenGLStateID state)
{
	const Expected &e = kStates[state];
	GLboolean depthMask = GL_FALSE;
	glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMask);

	bool ok = FlagIs(GL_LIGHTING, e.lighting) && FlagIs(GL_LIGHT0, e.light0) && FlagIs(GL_LIGHT1, e.light1)
		&& FlagIs(GL_LIGHT2, kOff) && FlagIs(GL_LIGHT3, kOff) && FlagIs(GL_LIGHT4, kOff)
		&& FlagIs(GL_LIGHT5, kOff) && FlagIs(GL_LIGHT6, kOff) && FlagIs(GL_LIGHT7, kOff)
		&& FlagIs(GL_TEXTURE_2D, e.texture2D) && FlagIs(GL_COLOR_MATERIAL, kOff)
		&& FlagIs(GL_BLEND, e.blend) && FlagIs(GL_FOG, e.fog) && FlagIs(GL_DEPTH_TEST, e.depthTest)
		&& FlagIs(GL_NORMALIZE, kOff) && FlagIs(GL_RESCALE_NORMAL, kOff) && FlagIs(GL_CULL_FACE, e.cullFace)
		&& (glIsEnabled(GL_VERTEX_ARRAY) == GL_TRUE) == e.vertexArray
		&& (glIsEnabled(GL_NORMAL_ARRAY) == GL_TRUE) == e.normalArray
		&& glIsEnabled(GL_COLOR_ARRAY) == GL_FALSE && glIsEnabled(GL_INDEX_ARRAY) == GL_FALSE
		&& glIsEnabled(GL_TEXTURE_COORD_ARRAY) == GL_FALSE && glIsEnabled(GL_EDGE_FLAG_ARRAY) == GL_FALSE
		&& (depthMask == GL_TRUE) == e.depthWriteMask
		&& Integer(GL_SHADE_MODEL) == GL_SMOOTH
		&& Integer(GL_ACTIVE_TEXTURE_ARB) == GL_TEXTURE0 && Integer(GL_CLIENT_ACTIVE_TEXTURE_ARB) == GL_TEXTURE0
		&& Integer(GL_CULL_FACE_MODE) == GL_BACK && Integer(GL_FRONT_FACE) == GL_CCW
		&& Integer(GL_BLEND_SRC) == e.blendSrc && Integer(GL_BLEND_DST) == e.blendDst;

	GLint envMode = -1;
	glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, &envMode);
	ok = ok && envMode == GL_MODULATE;

	if (!ok)  std::fprintf(stderr, "state %s does not read back as expected\n", e.name);
	return ok;
}

}	// namespace


// --- Tests --------------------------------------------------------------------------------------

OO_TEST(fromTheInitialState)
{
	OO_CHECK(OOTestGLContext());
	(void)cxx::OOOpenGLExtensionManager::sharedManager();	// loads glActiveTextureARB & co.

	for (int s = 0; s < OPENGL_STATE_INTERNAL_USE_ONLY; s++)
	{
		// Put the context back in the canonical initial state (GL's defaults) and say so.
		glDisable(GL_LIGHTING); glDisable(GL_TEXTURE_2D); glDisable(GL_BLEND); glDisable(GL_FOG);
		glDisable(GL_DEPTH_TEST); glDisable(GL_CULL_FACE);
		glDisableClientState(GL_VERTEX_ARRAY); glDisableClientState(GL_NORMAL_ARRAY);
		glDepthMask(GL_TRUE);
		glBlendFunc(GL_ONE, GL_ZERO);
		OOResetGLStateVerifier();

		OOSetOpenGLState((OOOpenGLStateID)s);
		OO_CHECK(Matches((OOOpenGLStateID)s));
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
}


OO_TEST(betweenEveryPairOfStates)
{
	OO_CHECK(OOTestGLContext());
	for (int from = 0; from < OPENGL_STATE_INTERNAL_USE_ONLY; from++)
	{
		for (int to = 0; to < OPENGL_STATE_INTERNAL_USE_ONLY; to++)
		{
			OOSetOpenGLState((OOOpenGLStateID)from);
			OO_CHECK(Matches((OOOpenGLStateID)from));
			OOSetOpenGLState((OOOpenGLStateID)to);
			OO_CHECK(Matches((OOOpenGLStateID)to));
			OOVerifyOpenGLState();
			OO_CHECK(Matches((OOOpenGLStateID)to));
		}
	}
	OO_CHECK(glGetError() == GL_NO_ERROR);
}


OO_TEST(openItemsAreLeftAlone)
{
	OO_CHECK(OOTestGLContext());
	// LIGHT0, LIGHT1 and (but for the overlay) FOG are kStateMaybe. A switch touches a state flag
	// only when it is set in both the source and the target state, so it leaves them alone, and
	// switching from an open FOG to the overlay's "off" leaves fog as it was (on here), where the
	// overlay's own table entry says off.
	OOSetOpenGLState(OPENGL_STATE_OPAQUE);
	glEnable(GL_LIGHT0);
	glDisable(GL_LIGHT1);
	glEnable(GL_FOG);
	OOSetOpenGLState(OPENGL_STATE_TRANSLUCENT_PASS);
	OO_CHECK(glIsEnabled(GL_LIGHT0) && !glIsEnabled(GL_LIGHT1) && glIsEnabled(GL_FOG));
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);
	OO_CHECK(glIsEnabled(GL_LIGHT0) && !glIsEnabled(GL_LIGHT1) && glIsEnabled(GL_FOG));
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	OO_CHECK(glIsEnabled(GL_LIGHT0) && !glIsEnabled(GL_LIGHT1) && glIsEnabled(GL_FOG));
	glDisable(GL_FOG);	// as the overlay expects, so that the next switch has nothing to verify
	OOSetOpenGLState(OPENGL_STATE_OPAQUE);
	OO_CHECK(glIsEnabled(GL_LIGHT0) && !glIsEnabled(GL_LIGHT1) && !glIsEnabled(GL_FOG));
	glDisable(GL_LIGHT0);
	OO_CHECK(glGetError() == GL_NO_ERROR);
}


OO_TEST_MAIN()
