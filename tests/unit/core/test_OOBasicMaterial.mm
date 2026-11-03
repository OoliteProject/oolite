/*	test_OOBasicMaterial.mm
	Unit tests for OOBasicMaterial (src/Core/Materials/OOBasicMaterial.h): bead oo-vl43, converted
	after its root (bead oo-smy, proposed ADR-0056 amendment oo-smy).

	OOBasicMaterial is the fixed-function material and the superclass of the three texture and
	shader materials, which convert in their own beads and stay Objective-C subclasses until then.
	This pins, through the Objective-C API its callers use, what it computed before the conversion:
	the defaults, what a configuration dictionary sets (through OOMaterialSpecifier), the colour and
	component accessors, the clamped shininess, -permitSpecular, the GL state -doApply sets (read
	back from a real context), -unapplyWithNext: falling back to the default material, and the
	description; and an Objective-C subclass overriding -permitSpecular and calling [super ...].
	Those checks ran on the Objective-C class first and now run through the facade. After them:
	the C++ API, and the crossing both ways (an Objective-C subclass behind a cxx::OOBasicMaterial
	pointer, a C++ subclass behind the facade), identity, nil and the facade class.
	Run: bash tools/check-core-tests.sh
*/

#import "OOBasicMaterial.h"
#import "OODescription.h"

#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"

#include <cmath>
#include <cstdlib>
#include <typeinfo>


/*	The game's OOLogging.mm reaches the resource manager, so it is not linked; what the material
	and the GL error check call of it is defined here.
*/
void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)	{ (void)inFunction; }
void OOLogGenericParameterErrorForFunction(const char *inFunction)			{ (void)inFunction; }
void OOLogIndent(void)  {}	// OOOpenGL.mm's error check (OOGL) indents what it logs
void OOLogOutdent(void)  {}


/*	OOTexture (OOTexture.mm links the texture loaders and the game) stands in for the one class
	method the material sends, and counts it (proposed ADR-0056, amendment oo-z1s4 item 4).
*/
static int gTextureApplyNones = 0;

@interface OOTexture: OOObject
+ (void) applyNone;
@end

@implementation OOTexture
+ (void) applyNone	{ gTextureApplyNones++; }
@end


// Link stubs (amendment oo-zffj item 2), never reached here: OOMaterialSpecifier.mm's texture
// specifiers, and OOOpenGL.mm's GL state dump.
oo::PList cxx_OOTextureSpecFromObject(const oo::PList &, const std::optional<std::string> &)	{ std::abort(); }
cxx::OOOpenGLExtensionManager *cxx::OOOpenGLExtensionManager::sharedManager()				{ std::abort(); }
GLint cxx::OOOpenGLExtensionManager::textureUnitCount()										{ std::abort(); }


/*	UNIVERSE is gSharedUniverse. The material asks it -reducedDetail (-permitSpecular), and the
	specifier asks it -useShaders; a stand-in answers both (amendment oo-vt0o item 4).
*/
@class Universe;
Universe *gSharedUniverse = nil;

@interface TestUniverse: OOObject
{
@public
	BOOL	_reducedDetail;
}
- (BOOL) reducedDetail;
- (BOOL) useShaders;
@end

@implementation TestUniverse
- (BOOL) reducedDetail	{ return _reducedDetail; }
- (BOOL) useShaders		{ return NO; }
@end


// An unconverted subclass, as OOSingleTextureMaterial is: it denies specular, and asks super.
@interface TestSubMaterial: OOBasicMaterial
{
@public
	int		_doApplies;
}
@end

@implementation TestSubMaterial

- (BOOL) permitSpecular	{ return NO; }

- (BOOL) doApply
{
	_doApplies++;
	return [super doApply];
}

@end


namespace {

struct Components
{
	GLfloat v[4];
};


bool Same(const GLfloat *a, std::initializer_list<GLfloat> b)
{
	const GLfloat *e = b.begin();
	for (int i = 0; i < 4; i++)
	{
		if (std::fabs(a[i] - e[i]) > 1e-5f)  return false;
	}
	return true;
}


Components Diffuse(OOBasicMaterial *m)	{ Components c = {}; [m getDiffuseComponents:c.v]; return c; }
Components Ambient(OOBasicMaterial *m)	{ Components c = {}; [m getAmbientComponents:c.v]; return c; }
Components Specular(OOBasicMaterial *m)	{ Components c = {}; [m getSpecularComponents:c.v]; return c; }
Components Emission(OOBasicMaterial *m)	{ Components c = {}; [m getEmissionComponents:c.v]; return c; }


bool SameColor(OOColor *color, std::initializer_list<GLfloat> b)
{
	const GLfloat v[4] = { [color redComponent], [color greenComponent], [color blueComponent], [color alphaComponent] };
	return color != nil && Same(v, b);
}


Components GLMaterial(GLenum which)
{
	Components c = {};
	glGetMaterialfv(GL_FRONT, which, c.v);
	return c;
}


GLfloat GLShininess()
{
	GLfloat value = -1;
	glGetMaterialfv(GL_FRONT, GL_SHININESS, &value);
	return value;
}


oo::PList Config(oo::PList::Dict dict)
{
	return oo::PList(std::move(dict));
}


OOBasicMaterial *Named(const char *name)
{
	return [[[OOBasicMaterial alloc] cxx_initWithName:std::string(name)] autorelease];
}

}	// namespace


OO_TEST(defaults)
{
	@autoreleasepool
	{
		OOBasicMaterial *m = Named("Hull");
		OO_CHECK([m cxx_name] == std::optional<std::string>("Hull"));
		OO_CHECK(Same(Diffuse(m).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(Ambient(m).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(Specular(m).v, { 0, 0, 0, 1 }));
		OO_CHECK(Same(Emission(m).v, { 0, 0, 0, 1 }));
		OO_CHECK([m shininess] == 0);
		OO_CHECK([m permitSpecular]);	// no universe: not reduced detail
		OO_CHECK([m isFinishedLoading] && ![m wantsNormalsAsTextureCoordinates]);
#ifndef NDEBUG
		OO_CHECK([m cxx_allTextures].empty());
#endif
		OO_CHECK(![[[[OOBasicMaterial alloc] cxx_initWithName:std::nullopt] autorelease] cxx_name].has_value());
	}
}


OO_TEST(emptyConfiguration)
{
	@autoreleasepool
	{
		// A null configuration is an empty one: the specifier's defaults apply (exponent 10, 0.2 white).
		OOBasicMaterial *m = [[[OOBasicMaterial alloc] initWithName:std::string("Plain") configuration:oo::PList()] autorelease];
		OO_CHECK([m cxx_name] == std::optional<std::string>("Plain"));
		OO_CHECK(Same(Diffuse(m).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(Ambient(m).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(Specular(m).v, { 0.2f, 0.2f, 0.2f, 1 }));
		OO_CHECK(Same(Emission(m).v, { 0, 0, 0, 1 }));
		OO_CHECK([m shininess] == 10);
	}
}


OO_TEST(configuration)
{
	@autoreleasepool
	{
		OOBasicMaterial *m = [[[OOBasicMaterial alloc] initWithName:std::string("Painted") configuration:Config({
			{ "diffuse_color", oo::PList("redColor") },
			{ "emission_color", oo::PList("greenColor") },
			{ "specular_color", oo::PList("blueColor") },
			{ "specular_exponent", oo::PList(std::int64_t(200)) },
		})] autorelease];
		OO_CHECK(Same(Diffuse(m).v, { 1, 0, 0, 1 }));
		OO_CHECK(Same(Ambient(m).v, { 1, 0, 0, 1 }));	// no ambient: the diffuse colour
		OO_CHECK(Same(Emission(m).v, { 0, 1, 0, 1 }));
		OO_CHECK(Same(Specular(m).v, { 0, 0, 1, 1 }));
		OO_CHECK([m shininess] == 128);	// clamped

		// Legacy names; white diffuse and black emission count as none; exponent 0: no specular.
		m = [[[OOBasicMaterial alloc] initWithName:std::string("Legacy") configuration:Config({
			{ "diffuse", oo::PList("whiteColor") },
			{ "ambient", oo::PList("yellowColor") },
			{ "emission", oo::PList("blackColor") },
			{ "shininess", oo::PList(std::int64_t(0)) },
			{ "specular", oo::PList("blueColor") },
		})] autorelease];
		OO_CHECK(Same(Diffuse(m).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(Ambient(m).v, { 1, 1, 0, 1 }));
		OO_CHECK(Same(Emission(m).v, { 0, 0, 0, 1 }));
		OO_CHECK(Same(Specular(m).v, { 0, 0, 0, 1 }));
		OO_CHECK([m shininess] == 0);
	}
}


OO_TEST(permitSpecular)
{
	@autoreleasepool
	{
		const oo::PList config = Config({ { "specular_exponent", oo::PList(std::int64_t(20)) } });

		// Reduced detail denies specular: the exponent and colour are not applied.
		TestUniverse *universe = [[[TestUniverse alloc] init] autorelease];
		universe->_reducedDetail = YES;
		gSharedUniverse = (Universe *)universe;
		OOBasicMaterial *m = [[[OOBasicMaterial alloc] initWithName:std::string("Reduced") configuration:config] autorelease];
		OO_CHECK(![m permitSpecular]);
		OO_CHECK([m shininess] == 0 && Same(Specular(m).v, { 0, 0, 0, 1 }));
		universe->_reducedDetail = NO;
		OO_CHECK([m permitSpecular]);
		gSharedUniverse = nil;

		// A subclass's override is asked while the superclass initialises.
		TestSubMaterial *sub = [[[TestSubMaterial alloc] initWithName:std::string("Sub") configuration:config] autorelease];
		OO_CHECK([sub shininess] == 0 && Same(Specular(sub).v, { 0, 0, 0, 1 }));
		OO_CHECK([sub cxx_name] == std::optional<std::string>("Sub"));
		OO_CHECK(Same(Diffuse(sub).v, { 1, 1, 1, 1 }));
	}
}


OO_TEST(accessors)
{
	@autoreleasepool
	{
		OOBasicMaterial *m = Named("Accessors");

		[m setDiffuseRed:0.1f green:0.2f blue:0.3f alpha:0.4f];
		OO_CHECK(SameColor([m diffuseColor], { 0.1f, 0.2f, 0.3f, 0.4f }));
		[m setDiffuseColor:nil];	// nil: unchanged
		OO_CHECK(Same(Diffuse(m).v, { 0.1f, 0.2f, 0.3f, 0.4f }));
		[m setDiffuseColor:[OOColor redColor]];
		OO_CHECK(Same(Diffuse(m).v, { 1, 0, 0, 1 }));

		[m setAmbientAndDiffuseColor:[OOColor greenColor]];
		OO_CHECK(Same(Diffuse(m).v, { 0, 1, 0, 1 }) && Same(Ambient(m).v, { 0, 1, 0, 1 }));
		[m setAmbientColor:[OOColor blueColor]];
		OO_CHECK(SameColor([m ambientColor], { 0, 0, 1, 1 }));
		[m setAmbientColor:nil];
		OO_CHECK(Same(Ambient(m).v, { 0, 0, 1, 1 }));

		[m setSpecularColor:[OOColor yellowColor]];
		OO_CHECK(SameColor([m specularColor], { 1, 1, 0, 1 }));
		[m setSpecularColor:nil];
		OO_CHECK(Same(Specular(m).v, { 1, 1, 0, 1 }));
		[m setEmissionColor:[OOColor magentaColor]];
		OO_CHECK(SameColor([m emmisionColor], { 1, 0, 1, 1 }));
		[m setEmissionColor:nil];
		OO_CHECK(Same(Emission(m).v, { 1, 0, 1, 1 }));

		const GLfloat c[4] = { 0.5f, 0.25f, 0.125f, 1 };
		[m setDiffuseComponents:c];
		[m setSpecularComponents:c];
		[m setEmissionComponents:c];
		[m setAmbientComponents:c];
		OO_CHECK(Same(Diffuse(m).v, { 0.5f, 0.25f, 0.125f, 1 }) && Same(Specular(m).v, { 0.5f, 0.25f, 0.125f, 1 }));
		OO_CHECK(Same(Emission(m).v, { 0.5f, 0.25f, 0.125f, 1 }) && Same(Ambient(m).v, { 0.5f, 0.25f, 0.125f, 1 }));
		const GLfloat d[4] = { 0, 0.5f, 0, 0.5f };
		[m setAmbientAndDiffuseComponents:d];
		OO_CHECK(Same(Diffuse(m).v, { 0, 0.5f, 0, 0.5f }) && Same(Ambient(m).v, { 0, 0.5f, 0, 0.5f }));

		[m setAmbientAndDiffuseRed:1 green:0 blue:1 alpha:1];
		OO_CHECK(Same(Diffuse(m).v, { 1, 0, 1, 1 }) && Same(Ambient(m).v, { 1, 0, 1, 1 }));
		[m setAmbientRed:0.25f green:0.25f blue:0.25f alpha:1];
		[m setSpecularRed:0.75f green:0.75f blue:0.75f alpha:1];
		[m setEmissionRed:0.5f green:0 blue:0 alpha:0];
		OO_CHECK(Same(Ambient(m).v, { 0.25f, 0.25f, 0.25f, 1 }) && Same(Specular(m).v, { 0.75f, 0.75f, 0.75f, 1 }));
		OO_CHECK(Same(Emission(m).v, { 0.5f, 0, 0, 0 }));

		[m setShininess:5];
		OO_CHECK([m shininess] == 5);
		[m setShininess:200];
		OO_CHECK([m shininess] == 128);
	}
}


OO_TEST(doApplySetsTheGLMaterial)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OOBasicMaterial *m = Named("Applied");
		[m setDiffuseRed:0.1f green:0.2f blue:0.3f alpha:0.4f];
		[m setAmbientRed:0.5f green:0.6f blue:0.7f alpha:0.8f];
		[m setSpecularRed:0.9f green:0.8f blue:0.7f alpha:0.6f];
		[m setEmissionRed:0.4f green:0.3f blue:0.2f alpha:0.1f];
		[m setShininess:64];

		const int applyNones = gTextureApplyNones;
		OO_CHECK([m doApply]);
		OO_CHECK(gTextureApplyNones == applyNones + 1);	// exactly an OOBasicMaterial: no texture
		OO_CHECK(Same(GLMaterial(GL_DIFFUSE).v, { 0.1f, 0.2f, 0.3f, 0.4f }));
		OO_CHECK(Same(GLMaterial(GL_AMBIENT).v, { 0.5f, 0.6f, 0.7f, 0.8f }));
		OO_CHECK(Same(GLMaterial(GL_SPECULAR).v, { 0.9f, 0.8f, 0.7f, 0.6f }));
		OO_CHECK(Same(GLMaterial(GL_EMISSION).v, { 0.4f, 0.3f, 0.2f, 0.1f }));
		OO_CHECK(GLShininess() == 64);

		// A subclass's [super doApply] sets the same state, and leaves the texture to the subclass.
		TestSubMaterial *sub = [[[TestSubMaterial alloc] cxx_initWithName:std::string("Sub")] autorelease];
		[sub setShininess:3];
		OO_CHECK([sub doApply] && sub->_doApplies == 1);
		OO_CHECK(gTextureApplyNones == applyNones + 1);
		OO_CHECK(Same(GLMaterial(GL_DIFFUSE).v, { 1, 1, 1, 1 }) && GLShininess() == 3);
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
}


OO_TEST(unapplyFallsBackToTheDefaultMaterial)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OOBasicMaterial *m = Named("Current");
		[m setDiffuseRed:0.1f green:0.2f blue:0.3f alpha:0.4f];
		[m setSpecularRed:0.9f green:0.8f blue:0.7f alpha:0.6f];
		[m setShininess:64];
		[m doApply];

		// Followed by another basic material (or a subclass): that one sets its own state.
		const int applyNones = gTextureApplyNones;
		[m unapplyWithNext:Named("Next")];
		[m unapplyWithNext:[[[TestSubMaterial alloc] cxx_initWithName:std::nullopt] autorelease]];
		OO_CHECK(gTextureApplyNones == applyNones);
		OO_CHECK(Same(GLMaterial(GL_DIFFUSE).v, { 0.1f, 0.2f, 0.3f, 0.4f }) && GLShininess() == 64);

		// Followed by nothing, or by a material that is not a basic one: the default material's state.
		[m unapplyWithNext:nil];
		OO_CHECK(gTextureApplyNones == applyNones + 1);
		OO_CHECK(Same(GLMaterial(GL_DIFFUSE).v, { 1, 1, 1, 1 }) && Same(GLMaterial(GL_AMBIENT).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(GLMaterial(GL_SPECULAR).v, { 0, 0, 0, 1 }) && Same(GLMaterial(GL_EMISSION).v, { 0, 0, 0, 1 }));
		OO_CHECK(GLShininess() == 0);

		[m doApply];
		[m unapplyWithNext:[[[OOMaterial alloc] init] autorelease]];
		OO_CHECK(gTextureApplyNones == applyNones + 3);
		OO_CHECK(Same(GLMaterial(GL_DIFFUSE).v, { 1, 1, 1, 1 }) && GLShininess() == 0);
	}
}


OO_TEST(applyAndCurrent)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OOBasicMaterial *a = Named("A");
		TestSubMaterial *b = [[[TestSubMaterial alloc] cxx_initWithName:std::string("B")] autorelease];
		[a apply];
		OO_CHECK([OOMaterial current] == a);
		[b apply];
		OO_CHECK([OOMaterial current] == b && b->_doApplies == 1);
		[OOMaterial applyNone];
		OO_CHECK([OOMaterial current] == nil);
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		const std::string text = oo::DescriptionOf(Named("Hull"));
		OO_CHECK(text.starts_with("<OOBasicMaterial 0x"));
		OO_CHECK(text.ends_with(">{\"Hull\"}"));
		const std::string sub = oo::DescriptionOf([[[TestSubMaterial alloc] cxx_initWithName:std::string("Sub")] autorelease]);
		OO_CHECK(sub.starts_with("<TestSubMaterial 0x") && sub.ends_with(">{\"Sub\"}"));
	}
}


// --- The C++ class and the crossing (after the conversion) ---------------------------------------

// A converted subclass, global as a game class with no outside caller would be: it denies specular.
class TestCxxBasicMaterial : public cxx::OOBasicMaterial
{
public:
	bool permitSpecular() override	{ return false; }
	bool doApply() override			{ doApplies++; return cxx::OOBasicMaterial::doApply(); }

	int doApplies = 0;
};


OO_TEST(cxxAPI)
{
	@autoreleasepool
	{
		const oo::Ref<cxx::OOBasicMaterial> m = cxx::OOBasicMaterial::materialWithName(std::string("Cxx"));
		OO_CHECK(m->name() == std::optional<std::string>("Cxx") && m->shininess() == 0);
		GLfloat c[4] = {};
		m->getDiffuseComponents(c);
		OO_CHECK(Same(c, { 1, 1, 1, 1 }));
		m->getSpecularComponents(c);
		OO_CHECK(Same(c, { 0, 0, 0, 1 }));
		m->setShininess(200);
		OO_CHECK(m->shininess() == 128);
		m->setAmbientAndDiffuseColor(cxx::OOColor::redColor().get());
		m->setDiffuseColor(nullptr);
		OO_CHECK(m->diffuseColor()->redComponent() == 1 && m->ambientColor()->greenComponent() == 0);
		OO_CHECK(m->descriptionComponents() == std::optional<std::string>("\"Cxx\""));
		OO_CHECK(m->permitSpecular() && m->isFinishedLoading());

		const oo::Ref<cxx::OOBasicMaterial> configured = cxx::OOBasicMaterial::materialWithName(std::nullopt, Config({
			{ "diffuse_color", oo::PList("blueColor") },
			{ "specular_exponent", oo::PList(std::int64_t(20)) },
		}));
		OO_CHECK(!configured->name().has_value());
		configured->getAmbientComponents(c);
		OO_CHECK(Same(c, { 0, 0, 1, 1 }) && configured->shininess() == 20);
		configured->getSpecularComponents(c);
		OO_CHECK(Same(c, { 0.2f, 0.2f, 0.2f, 1 }));

		// The C++ subclass's override is asked by the initialiser.
		const oo::Ref<TestCxxBasicMaterial> denying = oo::makeRef<TestCxxBasicMaterial>();
		denying->initWithName(std::string("Denying"), Config({ { "specular_exponent", oo::PList(std::int64_t(20)) } }));
		OO_CHECK(denying->shininess() == 0 && denying->name() == std::optional<std::string>("Denying"));
	}
}


OO_TEST(facadeOfACxxMaterial)
{
	@autoreleasepool
	{
		// [[OOBasicMaterial alloc] init...]: a C++ basic material, whose facade is the object made.
		OOBasicMaterial *made = Named("Made");
		cxx::OOBasicMaterial *part = oo::ToCxx(made);
		OO_CHECK(part != nullptr && typeid(*part) == typeid(cxx::OOBasicMaterial));
		OO_CHECK(oo::ToObjC(part) == made && oo::AsObjCMaterial(part) == nullptr);
		OO_CHECK(oo::ToCxx(static_cast<OOMaterial *>(made)) == part);
		cxx::OOBasicMaterial *plain = oo::ToCxx(static_cast<OOBasicMaterial *>([[[OOBasicMaterial alloc] init] autorelease]));
		OO_CHECK(typeid(*plain) == typeid(cxx::OOBasicMaterial));

		// A C++ basic material's facade is an OOBasicMaterial, one live one, however the pointer is typed.
		const oo::Ref<cxx::OOBasicMaterial> m = cxx::OOBasicMaterial::materialWithName(std::string("Cxx"));
		OOMaterial *facade = oo::ToObjC(static_cast<cxx::OOMaterial *>(m.get()));
		OO_CHECK([facade isMemberOfClass:[OOBasicMaterial class]]);
		OO_CHECK(oo::ToObjC(m.get()) == facade && oo::ToCxx(oo::ToObjC(m)) == m.get());
		OO_CHECK([oo::ToObjC(m) cxx_name] == std::optional<std::string>("Cxx"));
		[oo::ToObjC(m) setShininess:7];
		OO_CHECK(m->shininess() == 7);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOBasicMaterial 0x") && oo::DescriptionOf(facade).ends_with(">{\"Cxx\"}"));

		// A global C++ subclass is seen as its nearest converted class, the basic material.
		const oo::Ref<TestCxxBasicMaterial> sub = oo::makeRef<TestCxxBasicMaterial>();
		sub->initWithName(std::string("CxxSub"));
		OOBasicMaterial *subFacade = oo::ToObjC(sub.get());
		OO_CHECK([subFacade isMemberOfClass:[OOBasicMaterial class]]);
		OO_CHECK(![subFacade permitSpecular]);	// its override
		OO_CHECK(oo::DescriptionOf(subFacade).starts_with("<TestCxxBasicMaterial 0x"));
		if (OOTestGLContext())
		{
			const int applyNones = gTextureApplyNones;
			OO_CHECK([subFacade doApply] && sub->doApplies == 1);
			OO_CHECK(gTextureApplyNones == applyNones);	// not exactly a basic material
		}
	}
}


OO_TEST(objCSubclassBehindACxxPointer)
{
	@autoreleasepool
	{
		TestSubMaterial *sub = [[[TestSubMaterial alloc] cxx_initWithName:std::string("ObjC")] autorelease];
		cxx::OOBasicMaterial *part = oo::ToCxx(sub);
		OO_CHECK(part != nullptr && oo::AsObjCMaterial(part) != nullptr);
		OO_CHECK(oo::ToObjC(part) == sub);	// the object itself

		// Virtual calls from C++ reach the Objective-C overrides, or this class's own answers.
		OO_CHECK(!part->permitSpecular());
		OO_CHECK(part->name() == std::optional<std::string>("ObjC"));
		part->setShininess(9);
		OO_CHECK([sub shininess] == 9);
		part->initWithName(std::string("Again"), Config({ { "specular_exponent", oo::PList(std::int64_t(20)) } }));
		OO_CHECK([sub shininess] == 9 && [sub cxx_name] == std::optional<std::string>("Again"));
		if (OOTestGLContext())
		{
			OO_CHECK(part->doApply() && sub->_doApplies == 1);
		}

		// An Objective-C subclass counts as a basic material to one that is unapplied: no default.
		if (OOTestGLContext())
		{
			const int applyNones = gTextureApplyNones;
			cxx::OOBasicMaterial::materialWithName(std::nullopt)->unapplyWithNext(part);
			OO_CHECK(gTextureApplyNones == applyNones);
		}
	}
}


OO_TEST(nilAndLifetime)
{
	OOBasicMaterial *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOBasicMaterial *>(nullptr)) == nil);
	OO_CHECK([none shininess] == 0 && ![none permitSpecular]);

	// An Objective-C subclass's C++ part outlives it only as a reference C++ holds; it then answers
	// as a message to nil would.
	oo::Ref<cxx::OOBasicMaterial> part;
	@autoreleasepool
	{
		TestSubMaterial *gone = [[[TestSubMaterial alloc] cxx_initWithName:std::string("Gone")] autorelease];
		part = oo::Ref<cxx::OOBasicMaterial>(oo::ToCxx(gone));
	}
	OO_CHECK(!part->permitSpecular() && !part->name().has_value());
	OO_CHECK(oo::ToObjC(part) == nil);
}

OO_TEST_MAIN()
