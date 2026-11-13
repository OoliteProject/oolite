/*	test_OOVisualEffectEntity.mm
	Unit tests for OOVisualEffectEntity (src/Core/Entities/OOVisualEffectEntity.h), the scripted
	visual effects (initialisers, flags, mesh, subentities and flashers, scaling, orientation
	vectors, drawing, update, the break pattern flag and the subentity relationship).

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']), starts
	the JavaScript engine (the effect names its script events with OOJSID) in a scratch folder with
	no scripts (so an effect has no script), and uses a Universe that was never initialised, which
	makes the standard subentities the effects ask it for, and a plain entity as PLAYER. No effect
	has a model, so nothing is drawn. The tests pin an effect's flags, key, class and status; its
	scales and the radii they scale; its flasher and standard subentities (made from the definition,
	owned, listed, counted, scaled with it, removed and cleared); its orientation vectors; and the
	break pattern flag. An effect is the global C++ class, made with oo::NewVisualEffectObject()
	as a C++ entity, and the cases call its members. Run: bash
	tools/check-core-tests.sh test_OOVisualEffectEntity
*/

#include "OOVisualEffectEntity.h"
#include "PlayerEntity.h"	// PLAYER is C++
#include "OOFlasherEntity.h"
#include "OOJavaScriptEngine.h"
#include "Universe.h"
#include "ShipEntity.h"
#include "OOColor.h"
#include "OOJSPropID.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OOJSEntity.h"
#include "OOJSVisualEffect.h"

#include "oofnd/FileSystem.hpp"
#include "oo_test.hpp"

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>
#include "EntityManualRefs.h"  // the tests' manual entity references (T095)


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


class TestPlayer : public PlayerEntity
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};

// NewTestPlayer<TestPlayer>(): a C++ player, as PlayerEntity::sharedPlayer() makes the game's,
// retained (+1).
template <class T>
T *NewTestPlayer()
{
	std::shared_ptr<T> player = oo::makeRef<T>();
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}


// UNIVERSE: never initialised; makes the standard subentities, an effect with no definition, by
// key ("missing" has none).
class TestUniverse : public Universe
{
public:
	std::shared_ptr<Entity> newVisualEffectWithName(const std::string &effectKey) override	// the effect, owned by the caller
	{
		if (effectKey == "missing")  return nullptr;
		return oo::NewVisualEffect(effectKey, oo::PList());
	}
};


namespace {

namespace stdfs = std::filesystem;

void SetUp()
{
	static stdfs::path root;
	if (root.empty())
	{
		root = stdfs::temp_directory_path() / ("oo-test-visualeffect-" + std::to_string(static_cast<unsigned long>(::_getpid())));
		stdfs::remove_all(root);
		stdfs::create_directories(root / "Resources");
		OO_CHECK(::_putenv_s("HOMEPATH", root.string().c_str()) == 0);
		stdfs::current_path(root);
		OO_CHECK(oo::fs::writeFile(root / "Resources" / "Info-gnustep.plist", oo::Data("{ CFBundleVersion = \"9.9.9-test\"; }", 35), oo::fs::WriteMode::direct).has_value());
		{
			(void)OOJavaScriptEngine::sharedEngine();
		}
	}
	static Universe *universe = nullptr;
	if (universe == nullptr)
	{
		universe = new TestUniverse();	// never released
	}
	gSharedUniverse = universe;
	static TestPlayer *player = nullptr;
	if (player == nullptr)
	{
		{	// what the stand-in player's -init autoreleases is freed
       // while the engine is alive
			player = NewTestPlayer<TestPlayer>();
		}
	}
	gOOPlayer = player;
}


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-4;
}


oo::PList Dict(oo::PList::Dict entries)
{
	return oo::PList(std::move(entries));
}


oo::PList Numbers(double x, double y, double z)
{
	return oo::PList(oo::PList::Array{ oo::PList(x), oo::PList(y), oo::PList(z) });
}


// A flasher subentity of diameter 4 (collision radius 2) at (x, 0, 0).
oo::PList Flasher(double x)
{
	return Dict({ { "type", oo::PList(std::string("flasher")) }, { "size", oo::PList(4.0) }, { "position", Numbers(x, 0, 0) } });
}


// An effect, as the universe makes it (oo::RetainedEntity(oo::NewVisualEffect()),
// An effect, as the universe makes it (oo::RetainedEntity(oo::NewVisualEffect())): the C++ effect,
// autoreleased.
OOVisualEffectEntity *Effect(const std::string &key, const oo::PList &definition)
{
	return oo::ToEffect(oo::autorelease(oo::NewVisualEffect(key, definition)));
}


GLfloat NoDrawDistance(Entity *e)	{ return e->no_draw_distance; }

}	// namespace


OO_TEST(defaults)
{
	SetUp();
	{
		OOVisualEffectEntity *effect = Effect("test-effect", Dict({}));
		OO_CHECK(effect != nullptr);
		OO_CHECK(effect->isEffect());
		OO_CHECK(effect->getIsVisualEffect());
		OO_CHECK(!effect->canCollide());
		OO_CHECK(effect->effectKey() == std::optional<std::string>("test-effect"));
		OO_CHECK(effect->mesh() == nullptr);
		OO_CHECK(effect->getScanClass() == OOScanClass::kVisualEffect);
		OO_CHECK(effect->status() == OOEntityStatus::kEffect);
		OO_CHECK(!effect->isBreakPattern());
		OO_CHECK(effect->effectInfoDictionary() == Dict({}));

		OO_CHECK(effect->scaleX() == 1.0f && effect->scaleY() == 1.0f && effect->scaleZ() == 1.0f);
		OO_CHECK(effect->scaleMax() == 1.0f);
		OO_CHECK(effect->collisionRadius() == 0.0f);
		OO_CHECK(effect->frustumRadius() == 0.0f);
		OO_CHECK(NoDrawDistance(effect) == 0.0f);

		OO_CHECK_EQ(effect->subEntityCount(), 0u);
		OO_CHECK(effect->subEntities().empty());
		OO_CHECK(effect->subEntityEnumerator().empty());
		OO_CHECK(!effect->visualEffectSubEntityEnumerator().has_value());
		OO_CHECK(effect->effectSubEntityEnumerator().empty());
		OO_CHECK(effect->flasherEnumerator().empty());

		// A null definition is an empty one; -init has the empty key.
		OOVisualEffectEntity *plain = Effect(std::string{}, oo::PList());	// what -init made
		OO_CHECK(plain != nullptr);
		OO_CHECK(plain->effectKey() == std::optional<std::string>(""));
		OO_CHECK(plain->effectInfoDictionary() == Dict({}));
	}
}


OO_TEST(breakPatternFlag)
{
	SetUp();
	{
		OOVisualEffectEntity *effect = Effect("bp", Dict({ { "is_break_pattern", oo::PList(true) } }));
		OO_CHECK(effect->isBreakPattern());
		effect->setIsBreakPattern(false);
		OO_CHECK(!effect->isBreakPattern());
		effect->setIsBreakPattern(true);
		OO_CHECK(effect->isBreakPattern());
	}
}


OO_TEST(flasherSubentities)
{
	SetUp();
	{
		OOVisualEffectEntity *effect = Effect("lights", Dict({ { "subentities", oo::PList(oo::PList::Array{ Flasher(10), oo::PList(std::string("not a dictionary")) }) } }));
		OO_CHECK_EQ(effect->subEntityCount(), 1u);	// the string made no subentity
		std::vector<oo::EntityHold> flashers = effect->flasherEnumerator();	// the flashers (held C++ entities)
		OO_CHECK_EQ(flashers.size(), 1u);
		OO_CHECK(effect->effectSubEntityEnumerator().empty());
		OO_CHECK(effect->visualEffectSubEntityEnumerator().has_value() && effect->visualEffectSubEntityEnumerator()->empty());
		if (flashers.size() != 1)  return;

		Entity *flasher = flashers[0].get();
		OO_CHECK(effect->subEntities().size() == 1 && effect->subEntities()[0].get() == flasher);
		OO_CHECK(flasher->owner() == effect);
		OO_CHECK(flasher->getIsSubEntity());
		OO_CHECK(effect->hasSubEntity(flasher));
		OO_CHECK(Near(flasher->getPosition().x, 10.0));

		// The profile radius reaches the flasher's far side: 10 + 2.
		OO_CHECK(Near(effect->frustumRadius(), 12.0));
		OO_CHECK(Near(NoDrawDistance(effect), 12.0 * 12.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2.0));

		// Scaling one axis moves the flasher along it and resizes it by the cube root.
		const GLfloat flasherRadius = flasher->collisionRadius();
		effect->setScaleX(2.0f);
		OO_CHECK(effect->scaleX() == 2.0f);
		OO_CHECK(effect->scaleMax() == 2.0f);
		OO_CHECK(Near(flasher->getPosition().x, 20.0));
		OO_CHECK(Near(flasher->collisionRadius(), flasherRadius * std::pow(2.0, 1.0 / 3.0)));
		OO_CHECK(Near(effect->frustumRadius(), 24.0));
		effect->setScaleY(3.0f);
		OO_CHECK(effect->scaleMax() == 3.0f);
		effect->setScaleZ(0.5f);
		OO_CHECK(effect->scaleZ() == 0.5f);
		OO_CHECK(effect->scaleMax() == 3.0f);

		effect->removeSubEntity(flasher);
		OO_CHECK_EQ(effect->subEntityCount(), 0u);
		OO_CHECK(flasher->owner() == nullptr);
		OO_CHECK(!effect->hasSubEntity(flasher));
	}
}


OO_TEST(standardSubentities)
{
	SetUp();
	{
		oo::PList::Array subs;
		subs.push_back(Dict({ { "subentity_key", oo::PList(std::string("child")) }, { "position", Numbers(0, 5, 0) } }));
		subs.push_back(Dict({ { "subentity_key", oo::PList(std::string("missing")) } }));	// the universe has none
		subs.push_back(Dict({ { "position", Numbers(1, 1, 1) } }));							// no key
		subs.push_back(Flasher(-3));
		// Made, and the snapshot taken, in a pool of their own: what is left after it drains is what
		// owns the child (pending autoreleases are not ownership).
		OOVisualEffectEntity *effect = nullptr;
		std::vector<oo::EntityHold> effects;	// the subentities (held C++ entities)
		Entity *effectObject = nullptr;
		{
			effectObject = oo::RetainedEntity(oo::NewVisualEffect("parent", Dict({ { "subentities", oo::PList(std::move(subs)) } })));
			effect = oo::ToEffect(effectObject);
			effects = effect->effectSubEntityEnumerator();
		}
		oo::AutoreleaseEntity(effectObject);

		OO_CHECK_EQ(effect->subEntityCount(), 2u);
		OO_CHECK_EQ(effects.size(), 1u);
		OO_CHECK(effect->visualEffectSubEntityEnumerator().has_value() && effect->visualEffectSubEntityEnumerator()->size() == 1);
		OO_CHECK_EQ(effect->flasherEnumerator().size(), 1u);
		if (effects.size() != 1)  return;

		Entity *childObject = effects[0].get();	// the child, +0 and not autoreleased
		OOVisualEffectEntity *child = oo::ToEffect(childObject);
		OO_CHECK(child->effectKey() == std::optional<std::string>("child"));
		OO_CHECK(Near(child->getPosition().y, 5.0));
		OO_CHECK(child->owner() == effect);
		OO_CHECK(child->getIsSubEntity());
		OO_CHECK(childObject->weak_from_this().use_count() == 2);	// the parent's list and the enumerator's snapshot (effects)
		OO_CHECK(effect->isShipWithSubEntityShip(child));
		OO_CHECK(child->parentEntity() == effect);
		OO_CHECK(!child->isShipWithSubEntityShip(effect));

		// Rescaling the whole effect moves and rescales its subentities.
		effect->rescaleBy(2.0f);
		OO_CHECK(Near(child->getPosition().y, 10.0));
		OO_CHECK_EQ(effect->subEntityCount(), 2u);

		// A scale of one axis is passed on to a visual-effect subentity.
		effect->setScaleY(4.0f);
		OO_CHECK(child->scaleY() == 4.0f);
		OO_CHECK(Near(child->getPosition().y, 40.0));

		effect->clearSubEntities();
		OO_CHECK_EQ(effect->subEntityCount(), 0u);
		OO_CHECK(effect->subEntities().empty());
		OO_CHECK(!effect->visualEffectSubEntityEnumerator().has_value());
		OO_CHECK(effect->frustumRadius() == 0.0f);
	}
}


OO_TEST(orientationVectors)
{
	SetUp();
	{
		OOVisualEffectEntity *effect = Effect("turned", Dict({}));
		Quaternion q = kIdentityQuaternion;
		quaternion_rotate_about_y(&q, 0.5);
		quaternion_rotate_about_x(&q, 0.25);
		effect->setOrientation(q);
		const Quaternion o = effect->getOrientation();
		const Vector f = vector_forward_from_quaternion(o), u = vector_up_from_quaternion(o), r = vector_right_from_quaternion(o);
		OO_CHECK(Near(effect->forwardVector().x, f.x) && Near(effect->forwardVector().y, f.y) && Near(effect->forwardVector().z, f.z));
		OO_CHECK(Near(effect->upVector().x, u.x) && Near(effect->upVector().y, u.y) && Near(effect->upVector().z, u.z));
		OO_CHECK(Near(effect->rightVector().x, r.x) && Near(effect->rightVector().y, r.y) && Near(effect->rightVector().z, r.z));
		OO_CHECK(!Near(effect->forwardVector().z, 1.0));
	}
}


// The scanner colours, the script, the beacons and the shader uniforms.
OO_TEST(scannerColours)
{
	SetUp();
	{
		OOVisualEffectEntity *plain = Effect("plain", Dict({}));
		OO_CHECK(plain->scannerDisplayColor1() == nullptr);
		OO_CHECK(plain->scannerDisplayColor2() == nullptr);
		OO_CHECK(plain->scannerDisplayColorForShip(true, nullptr, nullptr)[3] == 0.0f);	// transparent black

		OOVisualEffectEntity *effect = Effect("coloured", Dict({ { "scanner_display_color1", oo::PList(std::string("redColor")) }, { "scanner_display_color2", oo::PList(std::string("blueColor")) } }));
		OOColor *c1 = effect->scannerDisplayColor1();
		OOColor *c2 = effect->scannerDisplayColor2();
		OO_CHECK(c1 != nullptr && c2 != nullptr);
		float r, g, b, a;
		c1->getRed(&r, &g, &b, &a);
		OO_CHECK(r == 1.0f && g == 0.0f && b == 0.0f && a == 1.0f);

		GLfloat *flashOn = effect->scannerDisplayColorForShip(true, c1, c2);
		OO_CHECK(flashOn[0] == 1.0f && flashOn[2] == 0.0f);
		GLfloat *flashOff = effect->scannerDisplayColorForShip(false, c1, c2);
		OO_CHECK(flashOff[0] == 0.0f && flashOff[2] == 1.0f);
		OO_CHECK(effect->scannerDisplayColorForShip(false, c1, nullptr)[0] == 1.0f);
		OO_CHECK(effect->scannerDisplayColorForShip(true, nullptr, c2)[2] == 1.0f);

		// A new colour replaces it; nil takes the definition's again.
		effect->setScannerDisplayColor1(OOColor::greenColor().get());
		effect->scannerDisplayColor1()->getRed(&r, &g, &b, &a);
		OO_CHECK(r == 0.0f && g == 1.0f && b == 0.0f);
		effect->setScannerDisplayColor1(nullptr);
		effect->scannerDisplayColor1()->getRed(&r, &g, &b, &a);
		OO_CHECK(r == 1.0f && g == 0.0f && b == 0.0f);
	}
}


OO_TEST(scriptAndScriptInfo)
{
	SetUp();
	{
		// No scripts in the scratch folder: neither the named script nor the default one is found.
		OOVisualEffectEntity *effect = Effect("scripted", Dict({ { "script", oo::PList(std::string("no-such-script.js")) }, { "script_info", Dict({ { "k", oo::PList(std::string("v")) } }) } }));
		OO_CHECK(effect->script() == nullptr);
		OO_CHECK(effect->scriptInfo() == Dict({ { "k", oo::PList(std::string("v")) } }));
		OO_CHECK(Effect("bare", Dict({}))->scriptInfo() == Dict({}));
		effect->doScriptEvent(OOJSID("anEvent"));	// no script: nothing happens
	}
}


OO_TEST(beacons)
{
	SetUp();
	{
		OOVisualEffectEntity *effect = Effect("unlit", Dict({}));
		OO_CHECK(!effect->isBeacon());
		OO_CHECK(!effect->beaconCode().has_value());
		OO_CHECK(!effect->beaconLabel().has_value());
		OO_CHECK(!effect->isJammingScanning());
		OO_CHECK(effect->prevBeacon() == nullptr && effect->nextBeacon() == nullptr);

		OOVisualEffectEntity *other = Effect("other", Dict({}));
		effect->setPrevBeacon(other);
		effect->setNextBeacon(other);
		OO_CHECK(effect->prevBeacon() == other && effect->nextBeacon() == other);
		effect->setNextBeacon(nullptr);
		OO_CHECK(effect->nextBeacon() == nullptr);
		effect->setPrevBeacon(nullptr);

		// An empty code is none.
		effect->setBeaconCode(std::optional<std::string>(""));
		OO_CHECK(!effect->beaconCode().has_value());
		OO_CHECK(effect->compareBeaconCodeWith(other) == OOComparisonResult::kSame);
	}
}


OO_TEST(shaderUniforms)
{
	SetUp();
	{
		OOVisualEffectEntity *effect = Effect("shaded", Dict({}));
		OO_CHECK(Near(effect->hullHeatLevel(), 60.0 / 256.0));
		effect->setHullHeatLevel(2.0f);
		OO_CHECK(effect->hullHeatLevel() == 1.0f);	// clamped
		effect->setHullHeatLevel(-1.0f);
		OO_CHECK(effect->hullHeatLevel() == 0.0f);
		OO_CHECK(effect->shaderFloat1() == 0.0f && effect->shaderFloat2() == 0.0f);
		OO_CHECK(effect->shaderInt1() == 0 && effect->shaderInt2() == 0);
		effect->setShaderFloat1(1.5f);
		effect->setShaderFloat2(2.5f);
		effect->setShaderInt1(3);
		effect->setShaderInt2(4);
		effect->setShaderVector1(make_vector(1, 2, 3));
		effect->setShaderVector2(make_vector(4, 5, 6));
		OO_CHECK(effect->shaderFloat1() == 1.5f && effect->shaderFloat2() == 2.5f);
		OO_CHECK(effect->shaderInt1() == 3 && effect->shaderInt2() == 4);
		OO_CHECK(effect->shaderVector1().y == 2.0f && effect->shaderVector2().z == 6.0f);
	}
}


// An effect is a C++ entity made by the initialiser the universe sends; the C++
// members give its answers, and the selectors still answer on the entity.
OO_TEST(facadeContract)
{
	SetUp();
	{
		OOVisualEffectEntity *effect = Effect("facade", Dict({ { "subentities", oo::PList(oo::PList::Array{ Flasher(1) }) } }));
		OOVisualEffectEntity *cxxEffect = effect;
		OO_CHECK(cxxEffect != nullptr);
		OO_CHECK(oo::ToEffect(cxxEffect) == effect);
		OO_CHECK(oo::ToEffect(static_cast<Entity *>(nullptr)) == nullptr);
		OO_CHECK(static_cast<OOVisualEffectEntity *>(nullptr) == nullptr);

		OO_CHECK(cxxEffect->effectKey() == effect->effectKey());
		OO_CHECK(cxxEffect->subEntityCount() == effect->subEntityCount());
		OO_CHECK(cxxEffect->getIsVisualEffect() && cxxEffect->isEffect() && !cxxEffect->canCollide());
		OO_CHECK(Near(cxxEffect->frustumRadius(), effect->frustumRadius()));
		cxxEffect->setScaleZ(5.0f);
		OO_CHECK(effect->scaleZ() == 5.0f);
		OO_CHECK(effect->scaleMax() == 5.0f);

		// The flasher's owner is the façade the C++ member handed it.
		std::vector<oo::EntityHold> flashers = cxxEffect->flasherEnumerator();
		OO_CHECK(flashers.size() == 1 && flashers[0].get()->owner() == effect);

		// The members, on the façade, read the state the class keeps.
		OO_CHECK(Near(effect->hullHeatLevel(), 60.0 / 256.0));
		effect->setShaderFloat1(0.5f);
		OO_CHECK(cxxEffect->_shaderFloat1 == 0.5f);
	}
}


// The scanner-colour, script, beacon and shader-uniform members answer as the
// façade does.
OO_TEST(slice2Members)
{
	SetUp();
	{
		OOVisualEffectEntity *effect = Effect("members", Dict({ { "scanner_display_color1", oo::PList(std::string("redColor")) } }));
		OOVisualEffectEntity *cxxEffect = effect;
		OO_CHECK(cxxEffect->scannerDisplayColor1() == effect->scannerDisplayColor1());
		OO_CHECK(cxxEffect->scannerDisplayColor2() == nullptr);
		cxxEffect->setShaderInt2(7);
		OO_CHECK(effect->shaderInt2() == 7);
		cxxEffect->setHullHeatLevel(0.25f);
		OO_CHECK(effect->hullHeatLevel() == 0.25f);
		OO_CHECK(cxxEffect->script() == effect->script());
		OO_CHECK(!cxxEffect->isBeacon() && !cxxEffect->isJammingScanning());
		OO_CHECK(cxxEffect->scannerDisplayColorForShip(true, cxxEffect->scannerDisplayColor1(), nullptr)[0] == 1.0f);
	}
}



// Registers Entity's JS class and the given class (a child of Entity) in the test's context, as the
// engine's start does; the context is made here if the test has none yet.
static void RegisterJSClasses(void (*initClass)(JSContext *, JSValueConst))
{
	extern JSContext *gOOJSMainThreadContext;
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
	JSContext *context = OOJSAcquireContext();
	JSValue global = JS_GetGlobalObject(context);
	InitOOJSEntity(context, global);
	initClass(context, global);
	JS_FreeValue(context, global);
}


// The binding's category: what the engine asks an effect's object for by
// selector is what OOJSVisualEffect.mm answers.
OO_TEST(jsExtensions)
{
	SetUp();
	{
		OOVisualEffectEntity *effect = Effect("js-effect", Dict({}));
		RegisterJSClasses(InitOOJSVisualEffect);
		Entity *object = effect;	// the engine asks the object
		const JSClassID jsClass = OOJSEntityJSClassID(object);
		const JSClassID expectedClass = JSVisualEffectClassID();
		OO_CHECK(jsClass != 0 && jsClass == expectedClass);
		OO_CHECK(OOJSEntityJSClassName(object) == std::optional<std::string>("VisualEffect"));
		OO_CHECK(OOJSEntityIsVisibleToScripts(object) == true);
	}
}


OO_TEST_MAIN()
