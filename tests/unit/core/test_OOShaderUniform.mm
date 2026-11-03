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
	first and now run through the facade. After them: the C++ factories (null where the
	initialiser answered nil) and the facade's identity.
	Run: bash tools/check-core-tests.sh
*/

#import "OOShaderUniform.h"
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


// The shader program (OOShaderProgram.mm reaches the resource manager): the one message the
// uniform sends, -program, answering the program the test linked.
@interface OOShaderProgram: OOObject
{
@public
	GLhandleARB	_program;
}
- (GLhandleARB) program;
@end

@implementation OOShaderProgram
- (GLhandleARB) program	{ return _program; }
@end


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
- (id) colorValue						{ return [OOColor colorWithRed:0.25f green:0.5f blue:0.75f alpha:1.0f]; }
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
OOShaderProgram *gShaderProgram = nil;


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

	gShaderProgram = [[OOShaderProgram alloc] init];
	gShaderProgram->_program = gProgram;
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


OOShaderUniform *Bound(const char *uniform, id target, const char *selector, OOUniformConvertOptions options = 0)
{
	return [[[OOShaderUniform alloc] initWithName:uniform shaderProgram:gShaderProgram boundToObject:target property:OOSelectorFromName(selector) convertOptions:options] autorelease];
}

}	// namespace


OO_TEST(initialisersThatFail)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OO_CHECK([[[OOShaderUniform alloc] initWithName:"uFloat" shaderProgram:nil floatValue:1] autorelease] == nil);
		OO_CHECK([[[OOShaderUniform alloc] initWithName:"uMissing" shaderProgram:gShaderProgram floatValue:1] autorelease] == nil);
		OO_CHECK([[[OOShaderUniform alloc] initWithName:"uVector" shaderProgram:gShaderProgram colorValue:nil] autorelease] == nil);
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		OO_CHECK([[[OOShaderUniform alloc] initWithName:"uFloat" shaderProgram:gShaderProgram boundToObject:target property:NULL convertOptions:0] autorelease] == nil);
		OO_CHECK([[[OOShaderUniform alloc] initWithName:"uFloat" shaderProgram:nil boundToObject:target property:OOSelectorFromName("floatValue") convertOptions:0] autorelease] == nil);
		OO_CHECK(Bound("uMissing", target, "floatValue") == nil);
	}
}


OO_TEST(constants)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		Reset();
		[[[[OOShaderUniform alloc] initWithName:"uInt" shaderProgram:gShaderProgram intValue:3] autorelease] apply];
		[[[[OOShaderUniform alloc] initWithName:"uFloat" shaderProgram:gShaderProgram floatValue:0.75f] autorelease] apply];
		OO_CHECK(Int("uInt") == 3 && Near(Floats("uFloat", 1), { 0.75f }));

		GLfloat v[4] = { 1, 2, 3, 4 };
		[[[[OOShaderUniform alloc] initWithName:"uVector" shaderProgram:gShaderProgram vectorValue:v] autorelease] apply];
		OO_CHECK(Near(Floats("uVector", 4), { 1, 2, 3, 4 }));
		[[[[OOShaderUniform alloc] initWithName:"uVector" shaderProgram:gShaderProgram colorValue:[OOColor colorWithRed:0.1f green:0.2f blue:0.3f alpha:0.4f]] autorelease] apply];
		OO_CHECK(Near(Floats("uVector", 4), { 0.1f, 0.2f, 0.3f, 0.4f }));

		// A quaternion as a vector is x, y, z, w; as a matrix it is its rotation.
		Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		[[[[OOShaderUniform alloc] initWithName:"uVector" shaderProgram:gShaderProgram quaternionValue:q asMatrix:NO] autorelease] apply];
		OO_CHECK(Near(Floats("uVector", 4), { 0.5f, 0.5f, 0.5f, 0.5f }));
		[[[[OOShaderUniform alloc] initWithName:"uMatrix" shaderProgram:gShaderProgram quaternionValue:q asMatrix:YES] autorelease] apply];
		const OOMatrix rotation = OOMatrixForQuaternionRotation(q);
		const std::vector<GLfloat> m = Floats("uMatrix", 16);
		bool same = true;
		for (int i = 0; i < 16; i++)  same = same && std::fabs(m[i] - OOMatrixValuesForOpenGL(rotation)[i]) < 1e-5f;
		OO_CHECK(same);

		[[[[OOShaderUniform alloc] initWithName:"uMatrix" shaderProgram:gShaderProgram matrixValue:OOMatrixForScale(2, 3, 4)] autorelease] apply];
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
		OOShaderUniform *u = Bound("uInt", target, "intValue");
		[u apply];
		OO_CHECK(Int("uInt") == 5);
		target->_int = 6;
		[u apply];
		OO_CHECK(Int("uInt") == 6);
		[Bound("uInt", target, "intValue", kOOUniformConvertClamp) apply];	// clamped: non-zero is 1
		OO_CHECK(Int("uInt") == 1);
		[Bound("uInt", target, "byteValue") apply];
		OO_CHECK(Int("uInt") == 7);

		[Bound("uFloat", target, "floatValue") apply];
		OO_CHECK(Near(Floats("uFloat", 1), { 1.75f }));
		[Bound("uFloat", target, "floatValue", kOOUniformConvertClamp) apply];
		OO_CHECK(Near(Floats("uFloat", 1), { 1.0f }));
		[Bound("uFloat", target, "doubleValue") apply];
		OO_CHECK(Near(Floats("uFloat", 1), { 2.5f }));

		[Bound("uVector", target, "vectorValue") apply];
		OO_CHECK(Near(Floats("uVector", 4), { 3, 0, 4, 1 }));
		[Bound("uVector", target, "vectorValue", kOOUniformConvertNormalize) apply];
		OO_CHECK(Near(Floats("uVector", 4), { 0.6f, 0, 0.8f, 1 }));
		[Bound("uVector", target, "hpVectorValue", kOOUniformConvertNormalize) apply];
		OO_CHECK(Near(Floats("uVector", 4), { 0, 0.6f, 0.8f, 1 }));
		[Bound("uVector", target, "quaternionValue") apply];	// not to matrix: x, y, z, w
		OO_CHECK(Near(Floats("uVector", 4), { 0.5f, 0.5f, 0.5f, 0.5f }));
		[Bound("uVector", target, "colorValue") apply];
		OO_CHECK(Near(Floats("uVector", 4), { 0.25f, 0.5f, 0.75f, 1 }));
		[Bound("uVector", target, "vectorValue") apply];
		[Bound("uVector", target, "notAColor") apply];	// an object that is not a colour: nothing set
		OO_CHECK(Near(Floats("uVector", 4), { 3, 0, 4, 1 }));

		[Bound("uMatrix", target, "matrixValue") apply];
		OO_CHECK(Near(Floats("uMatrix", 16), { 2, 0, 0, 0,  0, 3, 0, 0,  0, 0, 4, 0,  0, 0, 0, 1 }));
		[Bound("uMatrix", target, "quaternionValue", kOOUniformConvertToMatrix) apply];
		const Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		const OOMatrix rotation = OOMatrixForQuaternionRotation(q);
		OO_CHECK(std::fabs(Floats("uMatrix", 16)[1] - OOMatrixValuesForOpenGL(rotation)[1]) < 1e-5f);

		[Bound("uPoint", target, "pointValue") apply];
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
			OOShaderUniform *u = Bound("uFloat", target, selector);
			OO_CHECK(u != nil);
			[u apply];
			OO_CHECK(Near(Floats("uFloat", 1), { 9.0f }));
		}

		// No target yet: inactive until it is given one; nil makes it inactive again.
		OOShaderUniform *u = Bound("uFloat", nil, "floatValue");
		[u apply];
		OO_CHECK(Near(Floats("uFloat", 1), { 9.0f }));
		[u setBindingTarget:target];
		[u apply];
		OO_CHECK(Near(Floats("uFloat", 1), { 0.5f }));
		glUniform1fARB(glGetUniformLocationARB(gProgram, "uFloat"), 9.0f);
		[u setBindingTarget:nil];
		[u apply];
		OO_CHECK(Near(Floats("uFloat", 1), { 9.0f }));

		// A constant ignores a binding target.
		OOShaderUniform *constant = [[[OOShaderUniform alloc] initWithName:"uFloat" shaderProgram:gShaderProgram floatValue:0.25f] autorelease];
		[constant setBindingTarget:target];
		[constant apply];
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

		[Bound("uFloat", child, "floatValue", kOOUniformBindToSuperTarget) apply];
		OO_CHECK(Near(Floats("uFloat", 1), { 0.125f }));
		[Bound("uFloat", child, "floatValue") apply];
		OO_CHECK(Near(Floats("uFloat", 1), { 0.875f }));
	}

	// The uniform holds its target weakly: once it has gone, -apply sets nothing.
	OOShaderUniform *u = nil;
	@autoreleasepool
	{
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		target->_float = 0.5f;
		u = [Bound("uFloat", target, "floatValue") retain];
	}
	@autoreleasepool
	{
		glUniform1fARB(glGetUniformLocationARB(gProgram, "uFloat"), 9.0f);
		[u apply];
		OO_CHECK(Near(Floats("uFloat", 1), { 9.0f }));
		OO_CHECK(oo::DescriptionOf(u).ends_with(": float uFloat = 0;}"));
	}
	[u release];
}


OO_TEST(description)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		const std::string location = std::to_string(glGetUniformLocationARB(gProgram, "uInt"));
		const std::string text = oo::DescriptionOf([[[OOShaderUniform alloc] initWithName:"uInt" shaderProgram:gShaderProgram intValue:1] autorelease]);
		OO_CHECK(text.starts_with("<OOShaderUniform 0x") && text.ends_with(">{" + location + ": int uInt = 1;}"));
		OO_CHECK(oo::DescriptionOf([[[OOShaderUniform alloc] initWithName:"uFloat" shaderProgram:gShaderProgram floatValue:0.5f] autorelease]).ends_with(": float uFloat = 0.5;}"));
		GLfloat v[4] = { 1, 2, 3, 4 };
		OO_CHECK(oo::DescriptionOf([[[OOShaderUniform alloc] initWithName:"uVector" shaderProgram:gShaderProgram vectorValue:v] autorelease]).ends_with(": vec4 uVector = (1, 2, 3);}"));
		OO_CHECK(oo::DescriptionOf([[[OOShaderUniform alloc] initWithName:"uMatrix" shaderProgram:gShaderProgram matrixValue:kIdentityMatrix] autorelease]).ends_with(": matrix uMatrix = " + OOMatrixDescription(kIdentityMatrix) + ";}"));

		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		const std::string bound = oo::DescriptionOf(Bound("uFloat", target, "floatValue"));
		OO_CHECK(bound.find(": float uFloat = [<TestTarget 0x") != std::string::npos && bound.ends_with("> floatValue];}"));
		OO_CHECK(oo::DescriptionOf(Bound("uFloat", target, "nothing")).ends_with(": (null) uFloat = INVALID;}"));
	}
}


// --- The C++ class and the facade (after the conversion) -----------------------------------------

OO_TEST(cxxAPI)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OO_CHECK(cxx::OOShaderUniform::initWithName("uFloat", nil, 1.0f) == nullptr);
		OO_CHECK(cxx::OOShaderUniform::initWithName("uMissing", gShaderProgram, 1.0f) == nullptr);
		OO_CHECK(cxx::OOShaderUniform::initWithName("uVector", gShaderProgram, static_cast<cxx::OOColor *>(nullptr)) == nullptr);

		Reset();
		cxx::OOShaderUniform::initWithName("uInt", gShaderProgram, GLint(4))->apply();
		cxx::OOShaderUniform::initWithName("uFloat", gShaderProgram, 0.5f)->apply();
		OO_CHECK(Int("uInt") == 4 && Near(Floats("uFloat", 1), { 0.5f }));
		cxx::OOShaderUniform::initWithName("uVector", gShaderProgram, cxx::OOColor::colorWithRed(0.1f, 0.2f, 0.3f, 0.4f).get())->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0.1f, 0.2f, 0.3f, 0.4f }));
		const Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		cxx::OOShaderUniform::initWithName("uVector", gShaderProgram, q, false)->apply();
		OO_CHECK(Near(Floats("uVector", 4), { 0.5f, 0.5f, 0.5f, 0.5f }));
		cxx::OOShaderUniform::initWithName("uMatrix", gShaderProgram, OOMatrixForScale(2, 3, 4))->apply();
		OO_CHECK(Near(Floats("uMatrix", 16), { 2, 0, 0, 0,  0, 3, 0, 0,  0, 0, 4, 0,  0, 0, 0, 1 }));

		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		target->_float = 0.375f;
		const oo::Ref<cxx::OOShaderUniform> bound = cxx::OOShaderUniform::initWithName("uFloat", gShaderProgram, target, OOSelectorFromName("floatValue"), 0);
		OO_CHECK(bound != nullptr);
		bound->apply();
		OO_CHECK(Near(Floats("uFloat", 1), { 0.375f }));
		OO_CHECK(cxx::OOShaderUniform::initWithName("uFloat", gShaderProgram, target, nullptr, 0) == nullptr);
		OO_CHECK(bound->description()->find(": float uFloat = [<TestTarget 0x") != std::string::npos);
	}
}


OO_TEST(facade)
{
	if (!SetUpProgram())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OOShaderUniform *made = [[[OOShaderUniform alloc] initWithName:"uFloat" shaderProgram:gShaderProgram floatValue:0.5f] autorelease];
		cxx::OOShaderUniform *part = oo::ToCxx(made);
		OO_CHECK(part != nullptr && oo::ToObjC(part) == made);

		const oo::Ref<cxx::OOShaderUniform> u = cxx::OOShaderUniform::initWithName("uInt", gShaderProgram, GLint(2));
		OOShaderUniform *facade = oo::ToObjC(u);
		OO_CHECK(facade != nil && oo::ToObjC(u.get()) == facade && oo::ToCxx(facade) == u.get());
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOShaderUniform " + oo::str::pointerDescription(facade) + ">{"));

		OOShaderUniform *none = nil;
		OO_CHECK(oo::ToCxx(none) == nullptr && oo::ToObjC(static_cast<cxx::OOShaderUniform *>(nullptr)) == nil);
	}
}

OO_TEST_MAIN()
