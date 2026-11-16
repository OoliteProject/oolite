/*	test_OOFullScreenController.mm
	Unit tests for OOFullScreenController (src/Core/OOFullScreenController.h): bead oo-bgmb, a
	Phase 3 conversion in the house style of the OOColor exemplar (proposed ADR-0056).

	OOFullScreenController is the abstract base of the Mac full-screen controllers (Mac-only, not
	in this tree), so on this build nothing makes one. This pins what the base computed before the
	conversion: the game view it keeps (retained until the controller goes), every "subclass
	responsibility" method's log call and default answer, and -currentDisplayMode, the one method
	with a body, which picks the current index out of the subclass's mode list (null for no list,
	an index past the end, or NSNotFound). The expectations were written against the Objective-C
	API, with an Objective-C subclass, and run on the unconverted class first (commit a9b218647);
	the class has no facade (no compiled caller), so they are ported to the C++ class, and the
	subclass to a C++ one.
	Run: bash tools/check-core-tests.sh
*/

#import "OOFullScreenController.h"
#import "oofnd/objc/OOObject.h"

#import "OOLogging.h"
#include "oo_test.hpp"


/*	The game's OOLogging.mm reaches the resource manager, so it is not linked. The one function of
	it that the base calls is defined here instead, and counts.
*/
static int gSubclassResponsibilities = 0;

void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
	gSubclassResponsibilities++;
}


namespace {

oo::PList Mode(unsigned width, unsigned height, unsigned refresh)
{
	oo::PList::Dict mode;
	mode.emplace(std::string(kOODisplayWidth), oo::PList(width));
	mode.emplace(std::string(kOODisplayHeight), oo::PList(height));
	mode.emplace(std::string(kOODisplayRefreshRate), oo::PList(refresh));
	return oo::PList(std::move(mode));
}


oo::PList Modes()
{
	return oo::PList(oo::PList::Array{Mode(640, 480, 60), Mode(1024, 768, 75), Mode(1920, 1080, 60)});
}

}	// namespace


// A subclass that answers the two methods currentDisplayMode() asks.
class TestFullScreenController final : public OOFullScreenController
{
public:
	using OOFullScreenController::OOFullScreenController;

	oo::PList displayModes() override
	{
		return modes;
	}

	NSUInteger indexOfCurrentDisplayMode() override
	{
		return index;
	}

	oo::PList		modes;
	NSUInteger		index = 0;
};


OO_TEST(baseDefaults)
{
	@autoreleasepool
	{
		OOObject *view = [[OOObject alloc] init];
		const NSUInteger viewRetains = [view retainCount];
		oo::Ref<OOFullScreenController> controller = oo::makeRef<OOFullScreenController>((MyOpenGLView *)view);
		OO_CHECK(controller != nullptr);
		OO_CHECK(controller->gameView() == (MyOpenGLView *)view);
		OO_CHECK([view retainCount] == viewRetains + 1);

		gSubclassResponsibilities = 0;
		OO_CHECK(!controller->inFullScreenMode());
		OO_CHECK(gSubclassResponsibilities == 1);
		controller->setFullScreenMode(true);
		OO_CHECK(gSubclassResponsibilities == 2);
		OO_CHECK(controller->displayModes().isNull());
		OO_CHECK(gSubclassResponsibilities == 3);
		OO_CHECK(controller->indexOfCurrentDisplayMode() == NSNotFound);
		OO_CHECK(gSubclassResponsibilities == 4);
		OO_CHECK(!controller->setDisplayWidth(800, 600, 60));
		OO_CHECK(gSubclassResponsibilities == 5);
		OO_CHECK(controller->findDisplayModeForWidth(800, 600, 60).isNull());
		OO_CHECK(gSubclassResponsibilities == 6);

		// No mode list: null, after asking only for the list.
		OO_CHECK(controller->currentDisplayMode().isNull());
		OO_CHECK(gSubclassResponsibilities == 7);

		// The one method with an empty body.
		controller->noteMouseInteractionModeChangedFrom(MOUSE_MODE_UI_SCREEN_NO_INTERACTION, MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL);
		OO_CHECK(gSubclassResponsibilities == 7);

		controller = nullptr;
		OO_CHECK([view retainCount] == viewRetains);
		[view release];
	}
}


OO_TEST(nilGameView)
{
	@autoreleasepool
	{
		oo::Ref<OOFullScreenController> controller = oo::makeRef<OOFullScreenController>(nil);
		OO_CHECK(controller != nullptr);
		OO_CHECK(controller->gameView() == nil);
	}
}


OO_TEST(currentDisplayMode)
{
	@autoreleasepool
	{
		oo::Ref<TestFullScreenController> controller = oo::makeRef<TestFullScreenController>(nil);
		gSubclassResponsibilities = 0;

		controller->modes = Modes();
		controller->index = 1;
		OO_CHECK(controller->currentDisplayMode() == Mode(1024, 768, 75));
		controller->index = 0;
		OO_CHECK(controller->currentDisplayMode() == Mode(640, 480, 60));
		controller->index = 2;
		OO_CHECK(controller->currentDisplayMode() == Mode(1920, 1080, 60));
		OO_CHECK(controller->currentDisplayMode().get<NSUInteger>(std::string(kOODisplayWidth)) == 1920);

		// An index past the end, and NSNotFound: null.
		controller->index = 3;
		OO_CHECK(controller->currentDisplayMode().isNull());
		controller->index = NSNotFound;
		OO_CHECK(controller->currentDisplayMode().isNull());

		// A mode list that is not an array, and an empty one: null.
		controller->index = 0;
		controller->modes = Mode(640, 480, 60);
		OO_CHECK(controller->currentDisplayMode().isNull());
		controller->modes = oo::PList(oo::PList::Array{});
		OO_CHECK(controller->currentDisplayMode().isNull());

		// The subclass's overrides were used: the base logged nothing.
		OO_CHECK(gSubclassResponsibilities == 0);
	}
}


OO_TEST_MAIN()
