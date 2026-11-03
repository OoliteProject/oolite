/*	test_OOShaderUniform.mm
	Unit tests for OOShaderUniform (src/Core/Materials/OOShaderUniform.h): bead oo-n99o.

	A uniform of a GLSL program, a constant or bound to a property of an object that it asks for
	the value on every -apply. This pins, through the Objective-C API its callers use
	(OOShaderMaterial, DustEntity), what it computed before the conversion, on a real program
	compiled in a hidden GL context and read back with glGetUniform: which initialisers fail (no
	program, no uniform of that name, a nil colour, no selector); each constant's value as GL gets
	it (int, float, vector, colour, quaternion as vector or matrix, matrix); a binding to each
	supported return type with its conversions (clamp, normalise, quaternion to matrix), the
	methods it refuses (arguments, unsupported types, not implemented), the super-target chain,
	and a target that has gone; and the description. Those checks ran on the Objective-C class
	first and then through the facade. After them: the C++ factories (null where the
	initialiser answered nil) and the facade's identity.

	Bead oo-9ht.55 deleted the facade (ADR-0056 amendment "deleting a facade"). The cases that asked
	through its selectors ask the C++ class with the same expectations (each [[alloc] initWith...]
	is the factory of its arguments, nil is null, retain/release a held Ref, the description is
	description(), which prints the uniform's own address); the facade's own case (facade) was
	retired with it (ADR-0049, standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#import "OOShaderUniform.h"
#import "OORegExpMatcher.h"
#import "OOColor.h"
#import "OODescription.h"

#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"
#include "oofnd/objc/OORuntime.h"
#include "oofnd/String.hpp"

#include <cmath>
#include <string>
#include <vector>


// --- Stubs --------------------------------------------------------------------------------------

// OOLogging.mm's (it would bring the resource manager into the link).
void OOLogIndent(void)  {}
void OOLogOutdent(void)  {}


// The extension manager's collaborators, as test_OOOpenGLExtensionManager stubs them.
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


// The shader program (OOShaderProgram.mm reaches the resource manager): the one member the
// uniform calls, program(), answering the program the test linked. OOShaderProgram is C++ since
// its facade was deleted (bead oo-9ht.58): the stand-in is definitions of the members it uses.
static GLhandleARB gStandInProgram = 0;

OOShaderProgram::~OOShaderProgram()  {}
GLhandleARB OOShaderProgram::program()  { return _program; }
oo::Ref<OOShaderProgram> OOShaderProgram::shaderProgramWithVertexShaderName(const std::string &, const std::string &, const std::optional<std::string> &, const oo::PList &)
{
	oo::Ref<OOShaderProgram> made = oo::adopt(new OOShaderProgram());
	made->_program = gStandInProgram;
	return made;
}


// A binding target: one property per supported return type, and some that are not.
@interface TestTarget: OOWeakRefObject
{
@public
	id		_super;
	int		_int;
	float	_float;
}
@end

@implementation TestTarget
- (id<OOWeakReferenceSupport>) superShaderBindingTarget	{ return _super; }
- (int) intValue						{ return _int; }
- (unsigned char) byteValue				{ return 7; }
- (float) floatValue					{ return _float; }
- (double) doubleValue					{ return 2.5; }
- (Vector) vectorValue					{ return make_vector(3, 0, 4); }
- (HPVector) hpVectorValue				{ return make_HPvector(0, 6, 8); }
- (Quaternion) quaternionValue			{ Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f }; return q; }
- (OOMatrix) matrixValue				{ return OOMatrixForScale(2, 3, 4); }
- (NSPoint) pointValue					{ return NSMakePoint(1.5, -2.5); }
- (OOColor *) colorValue				{ static oo::Ref<OOColor> color = OOColor::colorWithRed(0.25f, 0.5f, 0.75f, 1.0f); return color.get(); }	// a colour binding answers the C++ colour (bead oo-9ht.1)
- (id) notAColor						{ return self; }
- (float) withArgument:(int)argument	{ return (float)argument; }
- (void) nothing						{}
- (long long) longLongValue				{ return 1; }
@end


// A target that forwards its bindings to another (as a subentity to its parent).
@interface TestSubTarget: TestTarget
@end

@implementation TestSubTarget
@end


namespace {

typedef void (APIENTRY *GetUniformfv)(GLhandleARB, GLint, GLfloat *);
typedef void (APIENTRY *GetUniformiv)(GLhandleARB, GLint, GLint *);

GLhandleARB gProgram = 0;
GetUniformfv gGetUniformfv = nullptr;
GetUniformiv gGetUniformiv = nullptr;
OOShaderProgram *gShaderProgram = nullptr;
oo::Ref<OOShaderProgram> gShaderProgramHeld;


// A program with one uniform of each kind, each used so that the linker keeps it.
bool SetUpProgram()
{
	if (gProgram != 0)  return true;
	if (!OOTestGLContext())  return false;
	[OOOpenGLExtensionManager sharedManager];	// loads the ARB shader entry points
	gGetUniformfv = (GetUniformfv)SDL_GL_GetProcAddress("glGetUniformfvARB");
	gGetUniformiv = (GetUniformiv)SDL_GL_GetProcAddress("glGetUniformivARB");
	if (gGetUniformfv == nullptr || gGetUniformiv == nullptr)  return false;

	const char *vertex =
		"uniform mat4 uMatrix;\n"
		"uniform vec4 uVector;\n"
		"uniform vec2 uPoint;\n"
		"void main() { gl_Position = uMatrix * gl_Vertex + uVector + vec4(uPoint, 0.0, 0.0); }\n";
	const char *fragment =
		"uniform int uInt;\n"
		"uniform float uFloat;\n"
		"void main() { gl_FragColor = vec4(float(uInt), uFloat, 0.0, 1.0); }\n";

	GLhandleARB vs = glCreateShaderObjectARB(GL_VERTEX_SHADER_ARB);
	glShaderSourceARB(vs, 1, &vertex, NULL);
	glCompileShaderARB(vs);
	GLhandleARB fs = glCreateShaderObjectARB(GL_FRAGMENT_SHADER_ARB);
	glShaderSourceARB(fs, 1, &fragment, NULL);
	glCompileShaderARB(fs);
	gProgram = glCreateProgramObjectARB();
	glAttachObjectARB(gProgram, vs);
	glAttachObjectARB(gProgram, fs);
	glLinkProgramARB(gProgram);
	glUseProgramObjectARB(gProgram);

	gStandInProgram = gProgram;
	gShaderProgramHeld = OOShaderProgram::shaderProgramWithVertexShaderName("", "", std::nullopt, oo::PList());
	gShaderProgram = gShaderProgramHeld.get();
	return glGetUniformLocationARB(gProgram, "uFloat") != -1;
}


std::vector<GLfloat> Floats(const char *name, int count)
{
	std::vector<GLfloat> values(16, -99.0f);
	gGetUniformfv(gProgram, glGetUniformLocationARB(gProgram, name), values.data());
	values.resize(count);
	return values;
}


GLint Int(const char *name)
{
	GLint value = -99;
	gGetUniformiv(gProgram, glGetUniformLocationARB(gProgram, name), &value);
	return value;
}


bool Near(const std::vector<GLfloat> &a, std::initializer_list<GLfloat> b)
{
	if (a.size() != b.size())  return false;
	size_t i = 0;
	for (GLfloat e : b)
	{
		if (std::fabs(a[i++] - e) > 1e-5f)  return false;
	}
	return true;
}


void Reset()
{
	glUseProgramObjectARB(gProgram);
	glUniform1iARB(glGetUniformLocationARB(gProgram, "uInt"), 0);
	glUniform1fARB(glGetUniformLocationARB(gProgram, "uFloat"), 0.0f);
	const GLfloat zero[16] = {};
	glUniform4fvARB(glGetUniformLocationARB(gProgram, "uVector"), 1, zero);
	glUniform2fvARB(glGetUniformLocationARB(gProgram, "uPoint"), 1, zero);
	glUniformMatrix4fvARB(glGetUniformLocationARB(gProgram, "uMatrix"), 1, GL_FALSE, zero);
}


oo::Ref<OOShaderUniform> Bound(const char *uniform, id target, const char *selector, OOUniformConvertOptions options = 0)
{
	return OOShaderUniform::initWithName(uniform, gShaderProgram, target, OOSelectorFromName(selector), options);
}


// The uniform's description, as the facade's -description printed it (nil: "(null)").
std::string Description(const oo::Ref<OOShaderUniform> &uniform)
{
	return uniform->description().value_or("(null)");
}

}	// namespace


OO_TEST(initialisersThatFail)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OO_CHECK(OOShaderUniform::initWithName("uFloat", nil, GLfloat(1)) == nullptr);
		OO_CHECK(OOShaderUniform::initWithName("uMissing", gShaderProgram, GLfloat(1)) == nullptr);
		OO_CHECK(OOShaderUniform::initWithName("uVector", gShaderProgram, static_cast<OOColor *>(nullptr)) == nullptr);
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		OO_CHECK(OOShaderUniform::initWithName("uFloat", gShaderProgram, target, NULL, 0) == nullptr);
		OO_CHECK(OOShaderUniform::initWithName("uFloat", nil, target, OOSelectorFromName("floatValue"), 0) == nullptr);
		OO_CHECK(Bound("uMissing", target, "floatValue") == nullptr);
	}
}


OO_TEST(constants)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		Reset();
		OOShaderUniform::initWithName("uInt", gShaderProgram, GLint(3))->apply();
		OOShaderUniform::initWithName("uFloat", gShaderProgram, 0.75f)->apply();
		OO_CHECK(Int("uInt") == 3 && Near(Floats("uFloat", 1), { 0.75f }));

		GLfloat v[4] = { 1, 2, 3, 4 };
		OOShaderUniform::initWithName("uVector", gShaderProgram, v)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 1, 2, 3, 4 }));
		OOShaderUniform::initWithName("uVector", gShaderProgram, OOColor::colorWithRed(0.1f, 0.2f, 0.3f, 0.4f).get())->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0.1f, 0.2f, 0.3f, 0.4f }));

		// A quaternion as a vector is x, y, z, w; as a matrix it is its rotation.
		Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		OOShaderUniform::initWithName("uVector", gShaderProgram, q, false)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0.5f, 0.5f, 0.5f, 0.5f }));
		OOShaderUniform::initWithName("uMatrix", gShaderProgram, q, true)->apply();
		const OOMatrix rotation = OOMatrixForQuaternionRotation(q);
		const std::vector<GLfloat> m = Floats("uMatrix", 16);
		bool same = true;
		for (int i = 0; i < 16; i++)  same = same && std::fabs(m[i] - OOMatrixValuesForOpenGL(rotation)[i]) < 1e-5f;
		OO_CHECK(same);

		OOShaderUniform::initWithName("uMatrix", gShaderProgram, OOMatrixForScale(2, 3, 4))->apply();
		OO_CHECK(Near(Floats("uMatrix", 16), { 2, 0, 0, 0,  0, 3, 0, 0,  0, 0, 4, 0,  0, 0, 0, 1 }));
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
}


OO_TEST(bindings)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		target->_int = 5;
		target->_float = 1.75f;
		Reset();

		// Each supported return type, applied on every -apply from the target's current value.
		const oo::Ref<OOShaderUniform> u = Bound("uInt", target, "intValue");
		u->apply();
		OO_CHECK(Int("uInt") == 5);
		target->_int = 6;
		u->apply();
		OO_CHECK(Int("uInt") == 6);
		Bound("uInt", target, "intValue", kOOUniformConvertClamp)->apply();	// clamped: non-zero is 1
		OO_CHECK(Int("uInt") == 1);
		Bound("uInt", target, "byteValue")->apply();
		OO_CHECK(Int("uInt") == 7);

		Bound("uFloat", target, "floatValue")->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 1.75f }));
		Bound("uFloat", target, "floatValue", kOOUniformConvertClamp)->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 1.0f }));
		Bound("uFloat", target, "doubleValue")->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 2.5f }));

		Bound("uVector", target, "vectorValue")->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 3, 0, 4, 1 }));
		Bound("uVector", target, "vectorValue", kOOUniformConvertNormalize)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0.6f, 0, 0.8f, 1 }));
		Bound("uVector", target, "hpVectorValue", kOOUniformConvertNormalize)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0, 0.6f, 0.8f, 1 }));
		Bound("uVector", target, "quaternionValue")->apply();	// not to matrix: x, y, z, w
		OO_CHECK(Near(Floats("uVector", 4), { 0.5f, 0.5f, 0.5f, 0.5f }));
		Bound("uVector", target, "colorValue")->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0.25f, 0.5f, 0.75f, 1 }));
		Bound("uVector", target, "vectorValue")->apply();
		Bound("uVector", target, "notAColor")->apply();	// an object that is not a colour: nothing set
		OO_CHECK(Near(Floats("uVector", 4), { 3, 0, 4, 1 }));

		Bound("uMatrix", target, "matrixValue")->apply();
		OO_CHECK(Near(Floats("uMatrix", 16), { 2, 0, 0, 0,  0, 3, 0, 0,  0, 0, 4, 0,  0, 0, 0, 1 }));
		Bound("uMatrix", target, "quaternionValue", kOOUniformConvertToMatrix)->apply();
		const Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		const OOMatrix rotation = OOMatrixForQuaternionRotation(q);
		OO_CHECK(std::fabs(Floats("uMatrix", 16)[1] - OOMatrixValuesForOpenGL(rotation)[1]) < 1e-5f);

		Bound("uPoint", target, "pointValue")->apply();
		OO_CHECK(Near(Floats("uPoint", 2), { 1.5f, -2.5f }));
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
}


OO_TEST(bindingsRefused)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		target->_float = 0.5f;
		Reset();
		glUniform1fARB(glGetUniformLocationARB(gProgram, "uFloat"), 9.0f);

		// Made, but inactive: -apply sets nothing.
		for (const char *selector : { "withArgument:", "nothing", "longLongValue", "noSuchMethod" })
		{
			const oo::Ref<OOShaderUniform> u = Bound("uFloat", target, selector);
			OO_CHECK(u != nullptr);
			u->apply();
			OO_CHECK(Near(Floats("uFloat", 1), { 9.0f }));
		}

		// No target yet: inactive until it is given one; nil makes it inactive again.
		const oo::Ref<OOShaderUniform> u = Bound("uFloat", nil, "floatValue");
		u->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 9.0f }));
		u->setBindingTarget(target);
		u->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 0.5f }));
		glUniform1fARB(glGetUniformLocationARB(gProgram, "uFloat"), 9.0f);
		u->setBindingTarget(nil);
		u->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 9.0f }));

		// A constant ignores a binding target.
		const oo::Ref<OOShaderUniform> constant = OOShaderUniform::initWithName("uFloat", gShaderProgram, 0.25f);
		constant->setBindingTarget(target);
		constant->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 0.25f }));
	}
}


OO_TEST(superTargetsAndLifetime)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		TestTarget *parent = [[[TestTarget alloc] init] autorelease];
		parent->_float = 0.125f;
		TestSubTarget *child = [[[TestSubTarget alloc] init] autorelease];
		child->_float = 0.875f;
		child->_super = parent;
		parent->_super = parent;	// a target that is its own super ends the chain
		Reset();

		Bound("uFloat", child, "floatValue", kOOUniformBindToSuperTarget)->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 0.125f }));
		Bound("uFloat", child, "floatValue")->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 0.875f }));
	}

	// The uniform holds its target weakly: once it has gone, -apply sets nothing.
	oo::Ref<OOShaderUniform> u;
	@autoreleasepool
	{
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		target->_float = 0.5f;
		u = Bound("uFloat", target, "floatValue");
	}
	@autoreleasepool
	{
		glUniform1fARB(glGetUniformLocationARB(gProgram, "uFloat"), 9.0f);
		u->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 9.0f }));
		OO_CHECK(Description(u).ends_with(": float uFloat = 0;}"));
	}
	u = nullptr;
}


OO_TEST(description)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		const std::string location = std::to_string(glGetUniformLocationARB(gProgram, "uInt"));
		const std::string text = Description(OOShaderUniform::initWithName("uInt", gShaderProgram, GLint(1)));
		OO_CHECK(text.starts_with("<OOShaderUniform 0x") && text.ends_with(">{" + location + ": int uInt = 1;}"));
		OO_CHECK(Description(OOShaderUniform::initWithName("uFloat", gShaderProgram, 0.5f)).ends_with(": float uFloat = 0.5;}"));
		GLfloat v[4] = { 1, 2, 3, 4 };
		OO_CHECK(Description(OOShaderUniform::initWithName("uVector", gShaderProgram, v)).ends_with(": vec4 uVector = (1, 2, 3);}"));
		OO_CHECK(Description(OOShaderUniform::initWithName("uMatrix", gShaderProgram, kIdentityMatrix)).ends_with(": matrix uMatrix = " + OOMatrixDescription(kIdentityMatrix) + ";}"));

		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		const std::string bound = Description(Bound("uFloat", target, "floatValue"));
		OO_CHECK(bound.find(": float uFloat = [<TestTarget 0x") != std::string::npos && bound.ends_with("> floatValue];}"));
		OO_CHECK(Description(Bound("uFloat", target, "nothing")).ends_with(": (null) uFloat = INVALID;}"));
	}
}


// --- The C++ class and the facade (after the conversion) -----------------------------------------

OO_TEST(cxxAPI)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OO_CHECK(OOShaderUniform::initWithName("uFloat", nil, 1.0f) == nullptr);
		OO_CHECK(OOShaderUniform::initWithName("uMissing", gShaderProgram, 1.0f) == nullptr);
		OO_CHECK(OOShaderUniform::initWithName("uVector", gShaderProgram, static_cast<OOColor *>(nullptr)) == nullptr);

		Reset();
		OOShaderUniform::initWithName("uInt", gShaderProgram, GLint(4))->apply();
		OOShaderUniform::initWithName("uFloat", gShaderProgram, 0.5f)->apply();
		OO_CHECK(Int("uInt") == 4 && Near(Floats("uFloat", 1), { 0.5f }));
		OOShaderUniform::initWithName("uVector", gShaderProgram, OOColor::colorWithRed(0.1f, 0.2f, 0.3f, 0.4f).get())->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0.1f, 0.2f, 0.3f, 0.4f }));
		const Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		OOShaderUniform::initWithName("uVector", gShaderProgram, q, false)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0.5f, 0.5f, 0.5f, 0.5f }));
		OOShaderUniform::initWithName("uMatrix", gShaderProgram, OOMatrixForScale(2, 3, 4))->apply();
		OO_CHECK(Near(Floats("uMatrix", 16), { 2, 0, 0, 0,  0, 3, 0, 0,  0, 0, 4, 0,  0, 0, 0, 1 }));

		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		target->_float = 0.375f;
		const oo::Ref<OOShaderUniform> bound = OOShaderUniform::initWithName("uFloat", gShaderProgram, target, OOSelectorFromName("floatValue"), 0);
		OO_CHECK(bound != nullptr);
		bound->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 0.375f }));
		OO_CHECK(OOShaderUniform::initWithName("uFloat", gShaderProgram, target, nullptr, 0) == nullptr);
		OO_CHECK(bound->description()->find(": float uFloat = [<TestTarget 0x") != std::string::npos);
	}
}


// The description prints the uniform's own address (bead oo-9ht.55: there is no facade to print).
OO_TEST(descriptionPrintsTheUniform)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	const oo::Ref<OOShaderUniform> u = OOShaderUniform::initWithName("uInt", gShaderProgram, GLint(2));
	OO_CHECK(Description(u).starts_with("<OOShaderUniform " + oo::str::pointerDescription(u.get()) + ">{"));
}

OO_TEST_MAIN()
