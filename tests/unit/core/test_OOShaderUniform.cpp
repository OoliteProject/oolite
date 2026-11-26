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

	Bead oo-4aq6a.7 deleted the Objective-C binding target (the factory bound to an object by
	selector, setBindingTarget(id), the super-target walk over -superShaderBindingTarget): no game
	code bound an Objective-C object. Its convert options (clamp, normalise, quaternion to matrix,
	colour, an object that is not a colour) were re-pinned first through the C++ target factory,
	with the same values (cxxTargetConvertOptions, ADR-0062 item 3), and so was bindingsRefused's
	constant check (constantIgnoresABindingTarget); then bindings, bindingsRefused,
	superTargetsAndLifetime and the Objective-C target's checks of initialisersThatFail,
	description and cxxAPI retired with that path (ADR-0062 item 2; std-2026-10-19 item 2).
	Run: bash tools/check-core-tests.sh
*/

#include "OOShaderUniform.h"
#include "OOShaderUniformMethodType.h"
#include "OORegExpMatcher.h"
#include "OOColor.h"
#include "OODescription.h"

#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"
#include "oofnd/String.hpp"

#include <cmath>
#include <string>
#include <vector>


// --- Stubs --------------------------------------------------------------------------------------

// OOLogging.mm's (it would bring the resource manager into the link).
void OOLogIndent(void)  {}
void OOLogOutdent(void)  {}


// The extension manager's collaborators, as test_OOOpenGLExtensionManager stubs them.
#include "ResourceManager.h"

// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
std::vector<std::string> ResourceManager::paths()  { return {}; }
oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string &/*fileName*/, const std::optional<std::string> &/*folderName*/, bool /*mergeFiles*/)  { return oo::PList(oo::PList::Dict{}); }



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
	OOOpenGLExtensionManager::sharedManager();	// loads the ARB shader entry points
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


// The uniform's description, as the facade's -description printed it (nil: "(null)").
std::string Description(const oo::Ref<OOShaderUniform> &uniform)
{
	return uniform->description().value_or("(null)");
}

}	// namespace


OO_TEST(initialisersThatFail)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	{
		OO_CHECK(OOShaderUniform::initWithName("uFloat", nil, GLfloat(1)) == nullptr);
		OO_CHECK(OOShaderUniform::initWithName("uMissing", gShaderProgram, GLfloat(1)) == nullptr);
		OO_CHECK(OOShaderUniform::initWithName("uVector", gShaderProgram, static_cast<OOColor *>(nullptr)) == nullptr);
	}
}


OO_TEST(constants)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
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


// A constant ignores a binding target (bindingsRefused's check, re-pinned through the entity
// target's setter when bead oo-4aq6a.7 deleted setBindingTarget(id); ADR-0062 item 3).
OO_TEST(constantIgnoresABindingTarget)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	{
		oo::AutoreleaseScope pool;
		Reset();
		const oo::Ref<OOShaderUniform> constant = OOShaderUniform::initWithName("uFloat", gShaderProgram, 0.25f);
		constant->setEntityBindingTarget(nullptr);
		constant->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 0.25f }));
	}
}


OO_TEST(description)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	{
		const std::string location = std::to_string(glGetUniformLocationARB(gProgram, "uInt"));
		const std::string text = Description(OOShaderUniform::initWithName("uInt", gShaderProgram, GLint(1)));
		OO_CHECK(text.starts_with("<OOShaderUniform 0x") && text.ends_with(">{" + location + ": int uInt = 1;}"));
		OO_CHECK(Description(OOShaderUniform::initWithName("uFloat", gShaderProgram, 0.5f)).ends_with(": float uFloat = 0.5;}"));
		GLfloat v[4] = { 1, 2, 3, 4 };
		OO_CHECK(Description(OOShaderUniform::initWithName("uVector", gShaderProgram, v)).ends_with(": vec4 uVector = (1, 2, 3);}"));
		OO_CHECK(Description(OOShaderUniform::initWithName("uMatrix", gShaderProgram, kIdentityMatrix)).ends_with(": matrix uMatrix = " + OOMatrixDescription(kIdentityMatrix) + ";}"));
	}
}


// A uniform bound to a C++ object's member (bead oo-t0e2m: the dust shader's uWarp and
// uOffsetPlayerPosition, which were bound by selector to an Objective-C object forwarding to the
// dust): the value is read from the target on every apply, converted as a method's was, and a
// target that has gone sets nothing.
namespace {

class CxxTarget : public oo::RefCounted
{
public:
	Vector	vector = kZeroVector;
};


void CxxTargetVector(oo::RefCounted *target, OOShaderBindingValue &outValue)
{
	outValue.v = static_cast<CxxTarget *>(target)->vector;
}

}	// namespace


OO_TEST(cxxTargetBindings)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	{
		OO_CHECK(OOShaderUniform::initWithName("uVector", nil, nullptr, "vector", kOOShaderUniformTypeVector, CxxTargetVector, 0) == nullptr);
		OO_CHECK(OOShaderUniform::initWithName("uMissing", gShaderProgram, nullptr, "vector", kOOShaderUniformTypeVector, CxxTargetVector, 0) == nullptr);
		OO_CHECK(OOShaderUniform::initWithName("uVector", gShaderProgram, nullptr, "vector", kOOShaderUniformTypeVector, nullptr, 0) == nullptr);
		OO_CHECK(OOShaderUniform::initWithName("uVector", gShaderProgram, nullptr, "vector", kOOShaderUniformTypeInvalid, CxxTargetVector, 0) == nullptr);

		Reset();
		oo::Ref<CxxTarget> target = oo::makeRef<CxxTarget>();
		target->vector = make_vector(3, 0, 4);
		oo::Ref<OOShaderUniform> u = OOShaderUniform::initWithName("uVector", gShaderProgram, target.get(), "vector", kOOShaderUniformTypeVector, CxxTargetVector, 0);
		OO_CHECK(u != nullptr);
		u->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 3, 0, 4, 1 }));
		target->vector = make_vector(0, 2, 10);
		u->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0, 2, 10, 1 }));
		OOShaderUniform::initWithName("uVector", gShaderProgram, target.get(), "vector", kOOShaderUniformTypeVector, CxxTargetVector, kOOUniformConvertNormalize)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0, 0.196116f, 0.980581f, 1 }));
		OO_CHECK(Description(u).find(": vec4 uVector = [<0x") != std::string::npos && Description(u).ends_with("> vector];}"));

		// The target held weakly: once it has gone, apply sets nothing.
		target = nullptr;
		const GLfloat nine[4] = { 9, 9, 9, 9 };
		glUniform4fvARB(glGetUniformLocationARB(gProgram, "uVector"), 1, nine);
		u->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 9, 9, 9, 9 }));
		OO_CHECK(Description(u).ends_with(": vec4 uVector = 0;}"));

		// No target: nothing set.
		OOShaderUniform::initWithName("uVector", gShaderProgram, nullptr, "vector", kOOShaderUniformTypeVector, CxxTargetVector, 0)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 9, 9, 9, 9 }));
	}
}


// The convert options and value kinds the deleted Objective-C target's case (bindings) pinned, through
// the C++ target factory with the same values (bead oo-4aq6a.7, ADR-0062 item 3): the type is the one
// the bound method's return type gave, the getter answers what the method answered.
namespace {

class ConvertTarget : public oo::RefCounted
{
public:
	int		_int = 0;
	float	_float = 0;
};

ConvertTarget *Target(oo::RefCounted *target)  { return static_cast<ConvertTarget *>(target); }

void IntValue(oo::RefCounted *t, OOShaderBindingValue &v)			{ v.i = Target(t)->_int; }
void ByteValue(oo::RefCounted *, OOShaderBindingValue &v)			{ v.i = 7; }
void FloatValue(oo::RefCounted *t, OOShaderBindingValue &v)			{ v.f = Target(t)->_float; }
void DoubleValue(oo::RefCounted *, OOShaderBindingValue &v)			{ v.f = 2.5; }
void VectorValue(oo::RefCounted *, OOShaderBindingValue &v)			{ v.v = make_vector(3, 0, 4); }
void HPVectorValue(oo::RefCounted *, OOShaderBindingValue &v)		{ v.hpv = make_HPvector(0, 6, 8); }
void QuaternionValue(oo::RefCounted *, OOShaderBindingValue &v)		{ Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f }; v.q = q; }
void MatrixValue(oo::RefCounted *, OOShaderBindingValue &v)			{ v.m = OOMatrixForScale(2, 3, 4); }
void PointValue(oo::RefCounted *, OOShaderBindingValue &v)			{ v.p = NSMakePoint(1.5, -2.5); }
void ColorValue(oo::RefCounted *, OOShaderBindingValue &v)			{ static oo::Ref<OOColor> color = OOColor::colorWithRed(0.25f, 0.5f, 0.75f, 1.0f); v.color = color.get(); }
void NotAColor(oo::RefCounted *, OOShaderBindingValue &)			{}

oo::Ref<OOShaderUniform> BoundCxx(const char *uniform, ConvertTarget *target, OOShaderUniformType type, OOShaderCxxBindingGetter get, OOUniformConvertOptions options = 0)
{
	return OOShaderUniform::initWithName(uniform, gShaderProgram, target, "property", type, get, options);
}

}	// namespace


OO_TEST(cxxTargetConvertOptions)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	{
		oo::AutoreleaseScope pool;
		oo::Ref<ConvertTarget> held = oo::makeRef<ConvertTarget>();
		ConvertTarget *target = held.get();
		target->_int = 5;
		target->_float = 1.75f;
		Reset();

		// Each supported value kind, applied on every apply from the target's current value.
		const oo::Ref<OOShaderUniform> u = BoundCxx("uInt", target, kOOShaderUniformTypeInt, IntValue);
		u->apply();
		OO_CHECK(Int("uInt") == 5);
		target->_int = 6;
		u->apply();
		OO_CHECK(Int("uInt") == 6);
		BoundCxx("uInt", target, kOOShaderUniformTypeInt, IntValue, kOOUniformConvertClamp)->apply();	// clamped: non-zero is 1
		OO_CHECK(Int("uInt") == 1);
		BoundCxx("uInt", target, kOOShaderUniformTypeUnsignedChar, ByteValue)->apply();
		OO_CHECK(Int("uInt") == 7);

		BoundCxx("uFloat", target, kOOShaderUniformTypeFloat, FloatValue)->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 1.75f }));
		BoundCxx("uFloat", target, kOOShaderUniformTypeFloat, FloatValue, kOOUniformConvertClamp)->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 1.0f }));
		BoundCxx("uFloat", target, kOOShaderUniformTypeDouble, DoubleValue)->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 2.5f }));

		BoundCxx("uVector", target, kOOShaderUniformTypeVector, VectorValue)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 3, 0, 4, 1 }));
		BoundCxx("uVector", target, kOOShaderUniformTypeVector, VectorValue, kOOUniformConvertNormalize)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0.6f, 0, 0.8f, 1 }));
		BoundCxx("uVector", target, kOOShaderUniformTypeHPVector, HPVectorValue, kOOUniformConvertNormalize)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0, 0.6f, 0.8f, 1 }));
		BoundCxx("uVector", target, kOOShaderUniformTypeQuaternion, QuaternionValue)->apply();	// not to matrix: x, y, z, w
		OO_CHECK(Near(Floats("uVector", 4), { 0.5f, 0.5f, 0.5f, 0.5f }));
		BoundCxx("uVector", target, kOOShaderUniformTypeColor, ColorValue)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0.25f, 0.5f, 0.75f, 1 }));
		BoundCxx("uVector", target, kOOShaderUniformTypeVector, VectorValue)->apply();
		BoundCxx("uVector", target, kOOShaderUniformTypeObject, NotAColor)->apply();	// an object that is not a colour: nothing set
		OO_CHECK(Near(Floats("uVector", 4), { 3, 0, 4, 1 }));

		BoundCxx("uMatrix", target, kOOShaderUniformTypeMatrix, MatrixValue)->apply();
		OO_CHECK(Near(Floats("uMatrix", 16), { 2, 0, 0, 0,  0, 3, 0, 0,  0, 0, 4, 0,  0, 0, 0, 1 }));
		BoundCxx("uMatrix", target, kOOShaderUniformTypeQuaternion, QuaternionValue, kOOUniformConvertToMatrix)->apply();
		const Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		const OOMatrix rotation = OOMatrixForQuaternionRotation(q);
		OO_CHECK(std::fabs(Floats("uMatrix", 16)[1] - OOMatrixValuesForOpenGL(rotation)[1]) < 1e-5f);

		BoundCxx("uPoint", target, kOOShaderUniformTypePoint, PointValue)->apply();
		OO_CHECK(Near(Floats("uPoint", 2), { 1.5f, -2.5f }));
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
}


// --- The C++ class and the facade (after the conversion) -----------------------------------------

OO_TEST(cxxAPI)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
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
