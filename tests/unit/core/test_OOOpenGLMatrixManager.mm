/*	test_OOOpenGLMatrixManager.mm
	Unit tests for OOOpenGLMatrixManager and OOOpenGLMatrixStack (src/Core/OOOpenGLMatrixManager.h):
	bead oo-vt0o, a Phase 3 class conversion (proposed ADR-0056).

	The expectations were written against the Objective-C API and run on the unconverted class
	first: the stack, the model-view and projection arithmetic (including where translate writes,
	which differs between the two), the degenerate-argument guards of frustum/ortho/perspective,
	the derived matrices and their cache, what sync loads into OpenGL, the uniform locations of a
	real shader program, and the OOGL* functions, which reach the manager through
	[[UNIVERSE gameView] getOpenGLMatrixManager] (this file's Universe and view stubs). The GL
	context is a hidden window's (oo_gl_test_context.hpp); the extension manager, which loads the
	shader entry points, runs with its collaborators stubbed as in test_OOOpenGLExtensionManager.
	The last test pins the facade's contract once the class is C++.
	Run: bash tools/check-core-tests.sh
*/

#import "OOOpenGLMatrixManager.h"
#import "OORegExpMatcher.h"
#import "OOOpenGLExtensionManager.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"
#include "oofnd/PList.hpp"

#include <cmath>
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


// OORegExpMatcher is C++ since its facade was deleted (bead oo-9ht.12): the stub answers no match.
oo::Ref<OORegExpMatcher> OORegExpMatcher::regExpMatcher()  { return oo::makeRef<OORegExpMatcher>(); }
bool OORegExpMatcher::string(const std::string &, const std::string &)  { return false; }
OORegExpMatcher::~OORegExpMatcher()  {}


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	return string == "SHADERS_FULL" ? SHADERS_FULL : SHADERS_NOT_SUPPORTED;
}


// UNIVERSE is gSharedUniverse; its -gameView answers the view whose -getOpenGLMatrixManager the
// OOGL* functions use.
@class Universe;
Universe *gSharedUniverse = nil;

@interface OOTestView: OOObject
{
@public
	OOOpenGLMatrixManager *manager;
}
- (OOOpenGLMatrixManager *) getOpenGLMatrixManager;
@end

@implementation OOTestView
- (OOOpenGLMatrixManager *) getOpenGLMatrixManager  { return manager; }
@end

@interface OOTestUniverse: OOObject
{
@public
	OOTestView *view;
}
- (OOTestView *) gameView;
@end

@implementation OOTestUniverse
- (OOTestView *) gameView  { return view; }
@end


// --- Helpers ------------------------------------------------------------------------------------

namespace {

bool Near(OOMatrix a, OOMatrix b)
{
	for (int i = 0; i < 4; i++)  for (int j = 0; j < 4; j++)
	{
		if (std::fabs(a.m[i][j] - b.m[i][j]) > 1e-5f)  return false;
	}
	return true;
}


bool Same(OOMatrix a, OOMatrix b)
{
	return OOMatrixEqual(a, b);
}


const OOMatrix kSample = OOMatrixConstruct(
	1, 2, 3, 0,
	0, 1, 4, 0,
	5, 6, 0, 0,
	7, 8, 9, 1);


GLuint Shader(GLenum type, const char *source)
{
	GLhandleARB shader = glCreateShaderObjectARB(type);
	glShaderSourceARB(shader, 1, &source, NULL);
	glCompileShaderARB(shader);
	return shader;
}

}	// namespace


// --- Tests --------------------------------------------------------------------------------------

OO_TEST(stack)
{
	@autoreleasepool
	{
		oo::Ref<OOOpenGLMatrixStack> stack = oo::makeRef<OOOpenGLMatrixStack>();
		OO_CHECK(stack->stackCount() == 0);
		OO_CHECK(Same(stack->pop(), kIdentityMatrix));	// empty: identity, and still empty
		OO_CHECK(stack->stackCount() == 0);
		stack->push(kSample);
		stack->push(kZeroMatrix);
		OO_CHECK(stack->stackCount() == 2);
		OO_CHECK(Same(stack->pop(), kZeroMatrix));
		OO_CHECK(Same(stack->pop(), kSample));
		OO_CHECK(stack->stackCount() == 0);
	}
}


OO_TEST(modelView)
{
	@autoreleasepool
	{
		oo::Ref<cxx::OOOpenGLMatrixManager> m = oo::makeRef<cxx::OOOpenGLMatrixManager>();
		OO_CHECK(Same(m->getModelView(), kIdentityMatrix));
		OO_CHECK(Same(m->getProjection(), kIdentityMatrix));
		OO_CHECK(m->countModelView() == 0);

		m->loadModelView(kSample);
		OO_CHECK(Same(m->getModelView(), kSample));
		m->multModelView(OOMatrixForScale(2, 3, 4));
		OO_CHECK(Same(m->getModelView(), OOMatrixMultiply(OOMatrixForScale(2, 3, 4), kSample)));

		m->resetModelView();
		m->translateModelView(make_vector(1, 2, 3));
		OO_CHECK(Same(m->getModelView(), OOMatrixForTranslationComponents(1, 2, 3)));
		OO_CHECK(m->getModelView().m[3][0] == 1 && m->getModelView().m[3][1] == 2 && m->getModelView().m[3][2] == 3);

		m->resetModelView();
		m->scaleModelView(make_vector(2, 3, 4));
		OO_CHECK(Same(m->getModelView(), OOMatrixForScale(2, 3, 4)));
		m->resetModelView();
		m->rotateModelView(0.5f, make_vector(0, 0, 1));
		OO_CHECK(Same(m->getModelView(), OOMatrixForRotation(make_vector(0, 0, 1), 0.5f)));

		m->resetModelView();
		m->lookAtWithEye(make_vector(0, 0, 5), make_vector(0, 0, 0), make_vector(0, 1, 0));
		OO_CHECK(Near(m->getModelView(), OOMatrixConstruct(1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, -5, 1)));

		m->loadModelView(kSample);
		m->pushModelView();
		m->pushModelView();
		OO_CHECK(m->countModelView() == 2);
		m->resetModelView();
		OO_CHECK(Same(m->popModelView(), kSample));
		OO_CHECK(Same(m->getModelView(), kSample));
		OO_CHECK(Same(m->popModelView(), kSample));
		OO_CHECK(m->countModelView() == 0);
		OO_CHECK(Same(m->popModelView(), kIdentityMatrix));	// empty stack
	}
}


OO_TEST(projection)
{
	@autoreleasepool
	{
		oo::Ref<cxx::OOOpenGLMatrixManager> m = oo::makeRef<cxx::OOOpenGLMatrixManager>();

		m->loadProjection(kSample);
		OO_CHECK(Same(m->getProjection(), kSample));
		OO_CHECK(Same(m->getModelView(), kIdentityMatrix));
		m->multProjection(OOMatrixForScale(2, 3, 4));
		OO_CHECK(Same(m->getProjection(), OOMatrixMultiply(OOMatrixForScale(2, 3, 4), kSample)));

		// Unlike the model view, translate writes the last column.
		m->resetProjection();
		m->translateProjection(make_vector(1, 2, 3));
		OO_CHECK(Same(m->getProjection(), OOMatrixConstruct(1, 0, 0, 1,  0, 1, 0, 2,  0, 0, 1, 3,  0, 0, 0, 1)));

		m->resetProjection();
		m->scaleProjection(make_vector(2, 3, 4));
		OO_CHECK(Same(m->getProjection(), OOMatrixForScale(2, 3, 4)));
		m->resetProjection();
		m->rotateProjection(0.25f, make_vector(1, 0, 0));
		OO_CHECK(Same(m->getProjection(), OOMatrixForRotation(make_vector(1, 0, 0), 0.25f)));

		m->resetProjection();
		m->frustumLeft(-1, 1, -2, 2, 1, 3);
		OO_CHECK(Near(m->getProjection(), OOMatrixConstruct(1, 0, 0, 0,  0, 0.5f, 0, 0,  0, 0, -2, -1,  0, 0, -3, 0)));
		m->resetProjection();
		m->orthoLeft(0, 4, 0, 2, -1, 1);
		OO_CHECK(Near(m->getProjection(), OOMatrixConstruct(0.5f, 0, 0, 0,  0, 1, 0, 0,  0, 0, -1, 0,  -1, -1, 0, 1)));
		m->resetProjection();
		m->perspectiveFovy(90, 2, 1, 3);
		OO_CHECK(Near(m->getProjection(), OOMatrixConstruct(0.5f, 0, 0, 0,  0, 1, 0, 0,  0, 0, -2, -1,  0, 0, -3, 0)));

		// Degenerate arguments change nothing.
		m->loadProjection(kSample);
		m->frustumLeft(1, 1, -1, 1, 1, 2);
		m->frustumLeft(-1, 1, 1, 1, 1, 2);
		m->frustumLeft(-1, 1, -1, 1, 2, 2);
		m->frustumLeft(-1, 1, -1, 1, 0, 2);
		m->frustumLeft(-1, 1, -1, 1, 1, -2);
		m->orthoLeft(1, 1, -1, 1, 1, 2);
		m->orthoLeft(-1, 1, 1, 1, 1, 2);
		m->orthoLeft(-1, 1, -1, 1, 2, 2);
		m->perspectiveFovy(60, 0, 1, 2);
		m->perspectiveFovy(60, 1, 2, 2);
		OO_CHECK(Same(m->getProjection(), kSample));

		m->pushProjection();
		m->resetProjection();
		OO_CHECK(Same(m->popProjection(), kSample));
		OO_CHECK(Same(m->popProjection(), kIdentityMatrix));	// empty stack
	}
}


OO_TEST(derivedMatrices)
{
	@autoreleasepool
	{
		oo::Ref<cxx::OOOpenGLMatrixManager> m = oo::makeRef<cxx::OOOpenGLMatrixManager>();
		for (int i = 0; i < OOLITE_GL_MATRIX_END; i++)  OO_CHECK(Same(m->getMatrix(i), kIdentityMatrix));
		OO_CHECK(Same(m->getMatrix(-1), kIdentityMatrix));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_END), kIdentityMatrix));

		const OOMatrix mv = OOMatrixMultiply(OOMatrixForRotation(make_vector(0, 1, 0), 0.3f), OOMatrixForTranslationComponents(1, 2, 3));
		const OOMatrix p = OOMatrixConstruct(1, 0, 0, 0,  0, 2, 0, 0,  0, 0, -2, -1,  0, 0, -3, 0);
		m->loadModelView(mv);
		m->loadProjection(p);
		const OOMatrix mvp = OOMatrixMultiply(mv, p);
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW), mv));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_PROJECTION), p));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION), mvp));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_INVERSE), OOMatrixInverse(mv)));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_PROJECTION_INVERSE), OOMatrixInverse(p)));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE), OOMatrixInverse(mvp)));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_TRANSPOSE), OOMatrixTranspose(mv)));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_PROJECTION_TRANSPOSE), OOMatrixTranspose(p)));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_TRANSPOSE), OOMatrixTranspose(mvp)));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_INVERSE_TRANSPOSE), OOMatrixTranspose(OOMatrixInverse(mv))));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_PROJECTION_INVERSE_TRANSPOSE), OOMatrixTranspose(OOMatrixInverse(p))));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE_TRANSPOSE), OOMatrixTranspose(OOMatrixInverse(mvp))));

		// The normal matrix of a rotation is the rotation (the translation dropped, det 1).
		OO_CHECK(Near(m->getMatrix(OOLITE_GL_MATRIX_NORMAL), OOMatrixForRotation(make_vector(0, 1, 0), 0.3f)));
		// A uniform scale s: inverse-transpose is 1/s, normalised by the cube root of det = 1/s^3.
		m->loadModelView(OOMatrixForScale(2, 2, 2));
		OO_CHECK(Near(m->getMatrix(OOLITE_GL_MATRIX_NORMAL), OOMatrixForScale(1, 1, 1)));
		m->loadModelView(OOMatrixForScale(2, 4, 8));	// det 64, cube root 4
		OO_CHECK(Near(m->getMatrix(OOLITE_GL_MATRIX_NORMAL), OOMatrixForScale(2, 1, 0.5f)));
		// A singular model view: the inverse's determinant is 0 and no normalisation happens.
		m->loadModelView(kZeroMatrix);
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_NORMAL), OOMatrixTranspose(OOMatrixInverse(OOMatrixConstruct(0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 1)))));

		// Derived matrices are cached until their source changes: a projection change leaves the
		// normal matrix and the model view inverse alone, and refreshes the rest.
		m->loadModelView(mv);
		const OOMatrix normal = m->getMatrix(OOLITE_GL_MATRIX_NORMAL);
		const OOMatrix mvInverse = m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_INVERSE);
		(void)m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION);
		m->loadProjection(kIdentityMatrix);
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_NORMAL), normal));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_INVERSE), mvInverse));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION), mv));
		OO_CHECK(Same(m->getMatrix(OOLITE_GL_MATRIX_PROJECTION_INVERSE), kIdentityMatrix));
	}
}


OO_TEST(syncLoadsOpenGL)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		oo::Ref<cxx::OOOpenGLMatrixManager> m = oo::makeRef<cxx::OOOpenGLMatrixManager>();
		m->loadModelView(kSample);
		m->loadProjection(OOMatrixForScale(2, 3, 4));

		glMatrixMode(GL_TEXTURE);
		m->syncModelView();
		GLint mode = 0;
		glGetIntegerv(GL_MATRIX_MODE, &mode);
		OO_CHECK(mode == GL_MODELVIEW);
		OO_CHECK(Same(OOMatrixLoadGLMatrix(GL_MODELVIEW_MATRIX), kSample));

		m->syncProjection();
		glGetIntegerv(GL_MATRIX_MODE, &mode);
		OO_CHECK(mode == GL_PROJECTION);
		OO_CHECK(Same(OOMatrixLoadGLMatrix(GL_PROJECTION_MATRIX), OOMatrixForScale(2, 3, 4)));
		OO_CHECK(Same(OOMatrixLoadGLMatrix(GL_MODELVIEW_MATRIX), kSample));
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
}


OO_TEST(standardUniformLocations)
{
	OO_CHECK(OOTestGLContext());
	OO_CHECK(cxx::OOOpenGLExtensionManager::sharedManager()->shadersSupported());	// loads the ARB entry points
	@autoreleasepool
	{
		oo::Ref<cxx::OOOpenGLMatrixManager> m = oo::makeRef<cxx::OOOpenGLMatrixManager>();

		const char *vertex =
			"uniform mat4 ooliteModelViewProjection;\n"
			"uniform mat3 ooliteNormalMatrix;\n"
			"uniform mat4 ooliteProjectionInverseTranspose;\n"
			"varying vec3 n;\n"
			"void main() { n = ooliteNormalMatrix * gl_Normal; gl_Position = ooliteProjectionInverseTranspose * ooliteModelViewProjection * gl_Vertex; }\n";
		const char *fragment =
			"varying vec3 n;\n"
			"void main() { gl_FragColor = vec4(n, 1.0); }\n";
		GLhandleARB program = glCreateProgramObjectARB();
		glAttachObjectARB(program, Shader(GL_VERTEX_SHADER_ARB, vertex));
		glAttachObjectARB(program, Shader(GL_FRAGMENT_SHADER_ARB, fragment));
		glLinkProgramARB(program);
		GLint linked = 0;
		glGetObjectParameterivARB(program, GL_OBJECT_LINK_STATUS_ARB, &linked);
		OO_CHECK(linked);

		const oo::PList locations = m->standardMatrixUniformLocations(program);
		const oo::PList::Array *array = locations.getIf<oo::PList::Array>();
		OO_CHECK(array != nullptr && array->size() == 3);
		if (array != nullptr && array->size() == 3)
		{
			const int expectedIndex[3] = { OOLITE_GL_MATRIX_MODELVIEW_PROJECTION, OOLITE_GL_MATRIX_NORMAL, OOLITE_GL_MATRIX_PROJECTION_INVERSE_TRANSPOSE };
			const char *expectedName[3] = { "ooliteModelViewProjection", "ooliteNormalMatrix", "ooliteProjectionInverseTranspose" };
			const char *expectedType[3] = { "mat4", "mat3", "mat4" };
			for (int k = 0; k < 3; k++)
			{
				const oo::PList::Array *triple = (*array)[k].getIf<oo::PList::Array>();
				OO_CHECK(triple != nullptr && triple->size() == 3);
				if (triple == nullptr || triple->size() != 3)  continue;
				OO_CHECK((*triple)[0].int64Value() == glGetUniformLocationARB(program, expectedName[k]));
				OO_CHECK((*triple)[1].int64Value() == expectedIndex[k]);
				OO_CHECK((*triple)[2].getIf<std::string>() != nullptr && *(*triple)[2].getIf<std::string>() == expectedType[k]);
			}
		}
		OO_CHECK(std::string(ooliteStandardMatrixUniforms[OOLITE_GL_MATRIX_NORMAL]) == "ooliteNormalMatrix");
		glDeleteObjectARB(program);

		// A program with none of them.
		const oo::PList none = m->standardMatrixUniformLocations(0);
		OO_CHECK(none.getIf<oo::PList::Array>() != nullptr && none.getIf<oo::PList::Array>()->empty());
		glGetError();
	}
}


OO_TEST(openGLFunctionsUseTheGameViewsManager)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		OOOpenGLMatrixManager *facade = [[[OOOpenGLMatrixManager alloc] init] autorelease];
		cxx::OOOpenGLMatrixManager *m = oo::ToCxx(facade);
		OOTestView *view = [[[OOTestView alloc] init] autorelease];
		OOTestUniverse *universe = [[[OOTestUniverse alloc] init] autorelease];
		view->manager = facade;
		universe->view = view;
		gSharedUniverse = (Universe *)universe;

		OOGLResetModelView();
		OOGLLoadModelView(kSample);
		OO_CHECK(Same(m->getModelView(), kSample));
		OO_CHECK(Same(OOMatrixLoadGLMatrix(GL_MODELVIEW_MATRIX), kSample));
		OOGLPushModelView();
		OO_CHECK(m->countModelView() == 1);
		OOGLMultModelView(OOMatrixForScale(2, 2, 2));
		OOGLTranslateModelView(make_vector(1, 0, 0));
		OOGLRotateModelView(0.1f, make_vector(0, 0, 1));
		OOGLScaleModelView(make_vector(1, 2, 1));
		OOGLLookAt(make_vector(0, 0, 1), make_vector(0, 0, 0), make_vector(0, 1, 0));
		OO_CHECK(Same(OOGLGetModelView(), m->getModelView()));
		OO_CHECK(Same(OOMatrixLoadGLMatrix(GL_MODELVIEW_MATRIX), m->getModelView()));
		OO_CHECK(Same(OOGLPopModelView(), kSample));
		OO_CHECK(Same(OOMatrixLoadGLMatrix(GL_MODELVIEW_MATRIX), kSample));

		OOGLResetProjection();
		OOGLPerspective(90, 2, 1, 3);
		OO_CHECK(Same(OOGLGetProjection(), m->getProjection()));
		OO_CHECK(Same(OOMatrixLoadGLMatrix(GL_PROJECTION_MATRIX), m->getProjection()));
		OOGLPushProjection();
		OOGLLoadProjection(kSample);
		OOGLMultProjection(OOMatrixForScale(1, 2, 3));
		OOGLTranslateProjection(make_vector(1, 2, 3));
		OOGLRotateProjection(0.2f, make_vector(0, 1, 0));
		OOGLScaleProjection(make_vector(3, 2, 1));
		OOGLFrustum(-1, 1, -1, 1, 1, 10);
		OOGLOrtho(-1, 1, -1, 1, -1, 1);
		OO_CHECK(Same(OOMatrixLoadGLMatrix(GL_PROJECTION_MATRIX), m->getProjection()));
		const OOMatrix mvp = OOMatrixMultiply(m->getModelView(), m->getProjection());
		OO_CHECK(Same(OOGLGetModelViewProjection(), mvp));
		OO_CHECK(Same(OOGLPopProjection(), OOMatrixConstruct(0.5f, 0, 0, 0,  0, 1, 0, 0,  0, 0, -2, -1,  0, 0, -3, 0)));

		// No universe: nothing is changed, and the getters answer a zero matrix, as nil did.
		gSharedUniverse = nil;
		OOGLLoadModelView(kIdentityMatrix);
		OOGLPushModelView();
		OO_CHECK(Same(m->getModelView(), kSample));
		OO_CHECK(m->countModelView() == 0);
		OO_CHECK(Same(OOGLGetModelView(), kZeroMatrix));
		OO_CHECK(Same(OOGLPopModelView(), kZeroMatrix));
		OO_CHECK(Same(OOGLGetProjection(), kZeroMatrix));
		OO_CHECK(Same(OOGLGetModelViewProjection(), kZeroMatrix));
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
}


// After the conversion: the facade answers as the C++ class does, and identity survives the crossing.
OO_TEST(facadeContract)
{
	oo::Ref<cxx::OOOpenGLMatrixManager> kept;
	@autoreleasepool
	{
		OOOpenGLMatrixManager *facade = [[OOOpenGLMatrixManager alloc] init];
		cxx::OOOpenGLMatrixManager *m = oo::ToCxx(facade);
		OO_CHECK(m != nullptr);
		OO_CHECK(oo::ToObjC(m) == facade);

		[facade loadModelView:kSample];
		OO_CHECK(Same(m->getModelView(), kSample));
		[facade pushModelView];
		OO_CHECK([facade countModelView] == 1 && m->countModelView() == 1);
		[facade frustumLeft:-1 right:1 bottom:-2 top:2 near:1 far:3];
		OO_CHECK(Same([facade getProjection], m->getProjection()));
		OO_CHECK(Same([facade getMatrix:OOLITE_GL_MATRIX_MODELVIEW_PROJECTION], m->getMatrix(OOLITE_GL_MATRIX_MODELVIEW_PROJECTION)));
		m->resetModelView();
		OO_CHECK(Same([facade popModelView], kSample));

		kept = oo::Ref<cxx::OOOpenGLMatrixManager>(m);
		[facade release];
	}
	@autoreleasepool
	{
		// Its facade gone, the C++ manager gets a new one, which reads the same state.
		OOOpenGLMatrixManager *again = oo::ToObjC(kept);
		OO_CHECK(again != nil && oo::ToCxx(again) == kept.get());
		OO_CHECK(oo::ToObjC(kept) == again);
		OO_CHECK(Same([again getModelView], kSample));
	}

	OOOpenGLMatrixManager *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOOpenGLMatrixManager *>(nullptr)) == nil);
	OO_CHECK([none countModelView] == 0);
}


OO_TEST_MAIN()
