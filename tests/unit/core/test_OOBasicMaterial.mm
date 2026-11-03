/*	test_OOBasicMaterial.mm
	Unit tests for OOBasicMaterial (src/Core/Materials/OOBasicMaterial.h): bead oo-vl43, converted
	after its root (bead oo-smy, proposed ADR-0056 amendment oo-smy); its Objective-C facade deleted
	by bead oo-9ht.33.

	OOBasicMaterial is the fixed-function material and the superclass of the three texture and
	shader materials. This pins what it computed before the conversion, through its C++ API: the
	defaults, what a configuration dictionary sets (through OOMaterialSpecifier), the colour and
	component accessors, the clamped shininess, permitSpecular(), the GL state doApply() sets (read
	back from a real context), unapplyWithNext() falling back to the default material, and the
	description; and a C++ subclass overriding permitSpecular() and calling the base class. Last,
	how Objective-C sees one (as an OOMaterial).
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


// A C++ subclass, as OOSingleTextureMaterial is: it denies specular, and asks the base class.
class TestSubMaterial : public OOBasicMaterial
{
public:
	bool permitSpecular() override	{ return false; }
	bool doApply() override			{ doApplies++; return OOBasicMaterial::doApply(); }

	int doApplies = 0;
};


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


Components Diffuse(OOBasicMaterial *m)	{ Components c = {}; m->getDiffuseComponents(c.v); return c; }
Components Ambient(OOBasicMaterial *m)	{ Components c = {}; m->getAmbientComponents(c.v); return c; }
Components Specular(OOBasicMaterial *m)	{ Components c = {}; m->getSpecularComponents(c.v); return c; }
Components Emission(OOBasicMaterial *m)	{ Components c = {}; m->getEmissionComponents(c.v); return c; }


bool SameColor(const oo::Ref<OOColor> &color, std::initializer_list<GLfloat> b)
{
	if (color == nullptr)  return false;
	const GLfloat v[4] = { color->redComponent(), color->greenComponent(), color->blueComponent(), color->alphaComponent() };
	return Same(v, b);
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


oo::Ref<OOBasicMaterial> Named(const char *name)
{
	return OOBasicMaterial::materialWithName(std::string(name));
}


oo::Ref<TestSubMaterial> NamedSub(const std::optional<std::string> &name, const oo::PList &configuration = oo::PList())
{
	oo::Ref<TestSubMaterial> result = oo::makeRef<TestSubMaterial>();
	result->initWithName(name, configuration);
	return result;
}

}	// namespace


OO_TEST(defaults)
{
	@autoreleasepool
	{
		const oo::Ref<OOBasicMaterial> m = Named("Hull");
		OO_CHECK(m->name() == std::optional<std::string>("Hull"));
		OO_CHECK(Same(Diffuse(m.get()).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(Ambient(m.get()).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(Specular(m.get()).v, { 0, 0, 0, 1 }));
		OO_CHECK(Same(Emission(m.get()).v, { 0, 0, 0, 1 }));
		OO_CHECK(m->shininess() == 0);
		OO_CHECK(m->permitSpecular());	// no universe: not reduced detail
		OO_CHECK(m->isFinishedLoading() && !m->wantsNormalsAsTextureCoordinates());
#ifndef NDEBUG
		OO_CHECK(m->allTextures().empty());
#endif
		OO_CHECK(!OOBasicMaterial::materialWithName(std::nullopt)->name().has_value());
	}
}


OO_TEST(emptyConfiguration)
{
	@autoreleasepool
	{
		// A null configuration is an empty one: the specifier's defaults apply (exponent 10, 0.2 white).
		const oo::Ref<OOBasicMaterial> m = OOBasicMaterial::materialWithName(std::string("Plain"), oo::PList());
		OO_CHECK(m->name() == std::optional<std::string>("Plain"));
		OO_CHECK(Same(Diffuse(m.get()).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(Ambient(m.get()).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(Specular(m.get()).v, { 0.2f, 0.2f, 0.2f, 1 }));
		OO_CHECK(Same(Emission(m.get()).v, { 0, 0, 0, 1 }));
		OO_CHECK(m->shininess() == 10);
	}
}


OO_TEST(configuration)
{
	@autoreleasepool
	{
		oo::Ref<OOBasicMaterial> m = OOBasicMaterial::materialWithName(std::string("Painted"), Config({
			{ "diffuse_color", oo::PList("redColor") },
			{ "emission_color", oo::PList("greenColor") },
			{ "specular_color", oo::PList("blueColor") },
			{ "specular_exponent", oo::PList(std::int64_t(200)) },
		}));
		OO_CHECK(Same(Diffuse(m.get()).v, { 1, 0, 0, 1 }));
		OO_CHECK(Same(Ambient(m.get()).v, { 1, 0, 0, 1 }));	// no ambient: the diffuse colour
		OO_CHECK(Same(Emission(m.get()).v, { 0, 1, 0, 1 }));
		OO_CHECK(Same(Specular(m.get()).v, { 0, 0, 1, 1 }));
		OO_CHECK(m->shininess() == 128);	// clamped

		// Legacy names; white diffuse and black emission count as none; exponent 0: no specular.
		m = OOBasicMaterial::materialWithName(std::string("Legacy"), Config({
			{ "diffuse", oo::PList("whiteColor") },
			{ "ambient", oo::PList("yellowColor") },
			{ "emission", oo::PList("blackColor") },
			{ "shininess", oo::PList(std::int64_t(0)) },
			{ "specular", oo::PList("blueColor") },
		}));
		OO_CHECK(Same(Diffuse(m.get()).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(Ambient(m.get()).v, { 1, 1, 0, 1 }));
		OO_CHECK(Same(Emission(m.get()).v, { 0, 0, 0, 1 }));
		OO_CHECK(Same(Specular(m.get()).v, { 0, 0, 0, 1 }));
		OO_CHECK(m->shininess() == 0);
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
		const oo::Ref<OOBasicMaterial> m = OOBasicMaterial::materialWithName(std::string("Reduced"), config);
		OO_CHECK(!m->permitSpecular());
		OO_CHECK(m->shininess() == 0 && Same(Specular(m.get()).v, { 0, 0, 0, 1 }));
		universe->_reducedDetail = NO;
		OO_CHECK(m->permitSpecular());
		gSharedUniverse = nil;

		// A subclass's override is asked while the superclass initialises.
		const oo::Ref<TestSubMaterial> sub = NamedSub(std::string("Sub"), config);
		OO_CHECK(sub->shininess() == 0 && Same(Specular(sub.get()).v, { 0, 0, 0, 1 }));
		OO_CHECK(sub->name() == std::optional<std::string>("Sub"));
		OO_CHECK(Same(Diffuse(sub.get()).v, { 1, 1, 1, 1 }));
	}
}


OO_TEST(accessors)
{
	@autoreleasepool
	{
		const oo::Ref<OOBasicMaterial> mRef = Named("Accessors");
		OOBasicMaterial *m = mRef.get();

		m->setDiffuseRed(0.1f, 0.2f, 0.3f, 0.4f);
		OO_CHECK(SameColor(m->diffuseColor(), { 0.1f, 0.2f, 0.3f, 0.4f }));
		m->setDiffuseColor(nullptr);	// null: unchanged
		OO_CHECK(Same(Diffuse(m).v, { 0.1f, 0.2f, 0.3f, 0.4f }));
		m->setDiffuseColor(OOColor::redColor().get());
		OO_CHECK(Same(Diffuse(m).v, { 1, 0, 0, 1 }));

		m->setAmbientAndDiffuseColor(OOColor::greenColor().get());
		OO_CHECK(Same(Diffuse(m).v, { 0, 1, 0, 1 }) && Same(Ambient(m).v, { 0, 1, 0, 1 }));
		m->setAmbientColor(OOColor::blueColor().get());
		OO_CHECK(SameColor(m->ambientColor(), { 0, 0, 1, 1 }));
		m->setAmbientColor(nullptr);
		OO_CHECK(Same(Ambient(m).v, { 0, 0, 1, 1 }));

		m->setSpecularColor(OOColor::yellowColor().get());
		OO_CHECK(SameColor(m->specularColor(), { 1, 1, 0, 1 }));
		m->setSpecularColor(nullptr);
		OO_CHECK(Same(Specular(m).v, { 1, 1, 0, 1 }));
		m->setEmissionColor(OOColor::magentaColor().get());
		OO_CHECK(SameColor(m->emmisionColor(), { 1, 0, 1, 1 }));
		m->setEmissionColor(nullptr);
		OO_CHECK(Same(Emission(m).v, { 1, 0, 1, 1 }));

		const GLfloat c[4] = { 0.5f, 0.25f, 0.125f, 1 };
		m->setDiffuseComponents(c);
		m->setSpecularComponents(c);
		m->setEmissionComponents(c);
		m->setAmbientComponents(c);
		OO_CHECK(Same(Diffuse(m).v, { 0.5f, 0.25f, 0.125f, 1 }) && Same(Specular(m).v, { 0.5f, 0.25f, 0.125f, 1 }));
		OO_CHECK(Same(Emission(m).v, { 0.5f, 0.25f, 0.125f, 1 }) && Same(Ambient(m).v, { 0.5f, 0.25f, 0.125f, 1 }));
		const GLfloat d[4] = { 0, 0.5f, 0, 0.5f };
		m->setAmbientAndDiffuseComponents(d);
		OO_CHECK(Same(Diffuse(m).v, { 0, 0.5f, 0, 0.5f }) && Same(Ambient(m).v, { 0, 0.5f, 0, 0.5f }));

		m->setAmbientAndDiffuseRed(1, 0, 1, 1);
		OO_CHECK(Same(Diffuse(m).v, { 1, 0, 1, 1 }) && Same(Ambient(m).v, { 1, 0, 1, 1 }));
		m->setAmbientRed(0.25f, 0.25f, 0.25f, 1);
		m->setSpecularRed(0.75f, 0.75f, 0.75f, 1);
		m->setEmissionRed(0.5f, 0, 0, 0);
		OO_CHECK(Same(Ambient(m).v, { 0.25f, 0.25f, 0.25f, 1 }) && Same(Specular(m).v, { 0.75f, 0.75f, 0.75f, 1 }));
		OO_CHECK(Same(Emission(m).v, { 0.5f, 0, 0, 0 }));

		m->setShininess(5);
		OO_CHECK(m->shininess() == 5);
		m->setShininess(200);
		OO_CHECK(m->shininess() == 128);
	}
}


OO_TEST(doApplySetsTheGLMaterial)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		const oo::Ref<OOBasicMaterial> m = Named("Applied");
		m->setDiffuseRed(0.1f, 0.2f, 0.3f, 0.4f);
		m->setAmbientRed(0.5f, 0.6f, 0.7f, 0.8f);
		m->setSpecularRed(0.9f, 0.8f, 0.7f, 0.6f);
		m->setEmissionRed(0.4f, 0.3f, 0.2f, 0.1f);
		m->setShininess(64);

		const int applyNones = gTextureApplyNones;
		OO_CHECK(m->doApply());
		OO_CHECK(gTextureApplyNones == applyNones + 1);	// exactly an OOBasicMaterial: no texture
		OO_CHECK(Same(GLMaterial(GL_DIFFUSE).v, { 0.1f, 0.2f, 0.3f, 0.4f }));
		OO_CHECK(Same(GLMaterial(GL_AMBIENT).v, { 0.5f, 0.6f, 0.7f, 0.8f }));
		OO_CHECK(Same(GLMaterial(GL_SPECULAR).v, { 0.9f, 0.8f, 0.7f, 0.6f }));
		OO_CHECK(Same(GLMaterial(GL_EMISSION).v, { 0.4f, 0.3f, 0.2f, 0.1f }));
		OO_CHECK(GLShininess() == 64);

		// A subclass's base-class doApply() sets the same state, and leaves the texture to the subclass.
		const oo::Ref<TestSubMaterial> sub = NamedSub(std::string("Sub"));
		sub->setShininess(3);
		OO_CHECK(sub->doApply() && sub->doApplies == 1);
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
		const oo::Ref<OOBasicMaterial> m = Named("Current");
		m->setDiffuseRed(0.1f, 0.2f, 0.3f, 0.4f);
		m->setSpecularRed(0.9f, 0.8f, 0.7f, 0.6f);
		m->setShininess(64);
		m->doApply();

		// Followed by another basic material (or a subclass): that one sets its own state.
		const int applyNones = gTextureApplyNones;
		m->unapplyWithNext(Named("Next").get());
		m->unapplyWithNext(NamedSub(std::nullopt).get());
		OO_CHECK(gTextureApplyNones == applyNones);
		OO_CHECK(Same(GLMaterial(GL_DIFFUSE).v, { 0.1f, 0.2f, 0.3f, 0.4f }) && GLShininess() == 64);

		// Followed by nothing, or by a material that is not a basic one: the default material's state.
		m->unapplyWithNext(nullptr);
		OO_CHECK(gTextureApplyNones == applyNones + 1);
		OO_CHECK(Same(GLMaterial(GL_DIFFUSE).v, { 1, 1, 1, 1 }) && Same(GLMaterial(GL_AMBIENT).v, { 1, 1, 1, 1 }));
		OO_CHECK(Same(GLMaterial(GL_SPECULAR).v, { 0, 0, 0, 1 }) && Same(GLMaterial(GL_EMISSION).v, { 0, 0, 0, 1 }));
		OO_CHECK(GLShininess() == 0);

		m->doApply();
		const oo::Ref<cxx::OOMaterial> plainMaterial = oo::makeRef<cxx::OOMaterial>();
		m->unapplyWithNext(plainMaterial.get());
		OO_CHECK(gTextureApplyNones == applyNones + 3);
		OO_CHECK(Same(GLMaterial(GL_DIFFUSE).v, { 1, 1, 1, 1 }) && GLShininess() == 0);
	}
}


OO_TEST(applyAndCurrent)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		const oo::Ref<OOBasicMaterial> a = Named("A");
		const oo::Ref<TestSubMaterial> b = NamedSub(std::string("B"));
		a->apply();
		OO_CHECK(cxx::OOMaterial::current().get() == a.get());
		b->apply();
		OO_CHECK(cxx::OOMaterial::current().get() == b.get() && b->doApplies == 1);
		cxx::OOMaterial::applyNone();
		OO_CHECK(cxx::OOMaterial::current() == nullptr);
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		const oo::Ref<OOBasicMaterial> m = Named("Hull");
		const std::string text = oo::DescriptionOf(oo::ToObjC(static_cast<cxx::OOMaterial *>(m.get())));
		OO_CHECK(text.starts_with("<OOBasicMaterial 0x"));
		OO_CHECK(text.ends_with(">{\"Hull\"}"));
		const oo::Ref<TestSubMaterial> sub = NamedSub(std::string("Sub"));
		const std::string subText = oo::DescriptionOf(oo::ToObjC(static_cast<cxx::OOMaterial *>(sub.get())));
		OO_CHECK(subText.starts_with("<TestSubMaterial 0x") && subText.ends_with(">{\"Sub\"}"));
	}
}


OO_TEST(cxxAPI)
{
	@autoreleasepool
	{
		const oo::Ref<OOBasicMaterial> m = OOBasicMaterial::materialWithName(std::string("Cxx"));
		OO_CHECK(m->name() == std::optional<std::string>("Cxx") && m->shininess() == 0);
		GLfloat c[4] = {};
		m->getDiffuseComponents(c);
		OO_CHECK(Same(c, { 1, 1, 1, 1 }));
		m->getSpecularComponents(c);
		OO_CHECK(Same(c, { 0, 0, 0, 1 }));
		m->setShininess(200);
		OO_CHECK(m->shininess() == 128);
		m->setAmbientAndDiffuseColor(OOColor::redColor().get());
		m->setDiffuseColor(nullptr);
		OO_CHECK(m->diffuseColor()->redComponent() == 1 && m->ambientColor()->greenComponent() == 0);
		OO_CHECK(m->descriptionComponents() == std::optional<std::string>("\"Cxx\""));
		OO_CHECK(m->permitSpecular() && m->isFinishedLoading());

		const oo::Ref<OOBasicMaterial> configured = OOBasicMaterial::materialWithName(std::nullopt, Config({
			{ "diffuse_color", oo::PList("blueColor") },
			{ "specular_exponent", oo::PList(std::int64_t(20)) },
		}));
		OO_CHECK(!configured->name().has_value());
		configured->getAmbientComponents(c);
		OO_CHECK(Same(c, { 0, 0, 1, 1 }) && configured->shininess() == 20);
		configured->getSpecularComponents(c);
		OO_CHECK(Same(c, { 0.2f, 0.2f, 0.2f, 1 }));

		// The C++ subclass's override is asked by the initialiser.
		const oo::Ref<TestSubMaterial> denying = NamedSub(std::string("Denying"), Config({ { "specular_exponent", oo::PList(std::int64_t(20)) } }));
		OO_CHECK(denying->shininess() == 0 && denying->name() == std::optional<std::string>("Denying"));
	}
}


// Objective-C sees a basic material, and a C++ subclass of one, as an OOMaterial (bead oo-9ht.33).
OO_TEST(crossesAsAnOOMaterial)
{
	@autoreleasepool
	{
		const oo::Ref<OOBasicMaterial> m = OOBasicMaterial::materialWithName(std::string("Cxx"));
		OOMaterial *facade = oo::ToObjC(static_cast<cxx::OOMaterial *>(m.get()));
		OO_CHECK([facade isMemberOfClass:[OOMaterial class]]);
		OO_CHECK(oo::ToObjC(static_cast<cxx::OOMaterial *>(m.get())) == facade && oo::ToCxx(facade) == m.get());
		OO_CHECK(oo::AsObjCMaterial(m.get()) == nullptr);
		OO_CHECK([facade cxx_name] == std::optional<std::string>("Cxx"));

		const oo::Ref<TestSubMaterial> sub = NamedSub(std::string("CxxSub"));
		OOMaterial *subFacade = oo::ToObjC(static_cast<cxx::OOMaterial *>(sub.get()));
		OO_CHECK([subFacade isMemberOfClass:[OOMaterial class]] && oo::ToCxx(subFacade) == sub.get());
	}
}


OO_TEST(nilCrossesAsNull)
{
	OOMaterial *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOMaterial *>(nullptr)) == nil);
}

OO_TEST_MAIN()
