/*	test_date.cpp
	Unit tests for oofnd/Date.hpp (bead oo-3rb.11): oo::date, the replacement for NSDate. Pins the
	reference-date epoch (2001-01-01 00:00:00 UTC) so timeIntervalSinceReferenceDate() returns the
	number NSDate did, the round trips, NSDate -description's format, and the monotonic clock.
*/

// Included under OOCocoa.h's true/false macros, as the game includes it (see test_cocoa_macros.cpp).
#define true						1
#define false						0
#include "oofnd/Date.hpp"
#include <type_traits>
static_assert(std::is_same_v<decltype(true), int>, "Date.hpp must restore OOCocoa.h's true macro");
#undef true
#undef false

#include "oo_test.hpp"

#include <cmath>
#include <string>

namespace {

using oo::date::Clock;

Clock::time_point unix(std::int64_t seconds)
{
	return Clock::time_point(std::chrono::seconds(seconds));
}

OO_TEST(referenceDateIs2001UTC)
{
	OO_CHECK_EQ(oo::date::kReferenceDateSince1970, 978307200);
	// 2001-01-01 00:00:00 UTC: 31 years of 365 days + 8 leap days (1972 .. 2000) after 1970.
	OO_CHECK_EQ(oo::date::kReferenceDateSince1970, (31LL * 365 + 8) * 86400);
	OO_CHECK(oo::date::timeIntervalSinceReferenceDate(unix(978307200)) == 0.0);
	OO_CHECK(oo::date::timeIntervalSinceReferenceDate(unix(0)) == -978307200.0);
	OO_CHECK(oo::date::timeIntervalSince1970(unix(978307200)) == 978307200.0);
	OO_CHECK_EQ(oo::date::description(oo::date::dateWithTimeIntervalSinceReferenceDate(0.0), 0),
				std::string("2001-01-01 00:00:00 +0000"));
}

OO_TEST(roundTrips)
{
	const double interval = 812345678.25;   // a 2026 date with a quarter second
	const Clock::time_point t = oo::date::dateWithTimeIntervalSinceReferenceDate(interval);
	OO_CHECK(std::fabs(oo::date::timeIntervalSinceReferenceDate(t) - interval) < 1e-6);
	OO_CHECK(std::fabs(oo::date::timeIntervalSince1970(t) - (interval + 978307200.0)) < 1e-6);
	OO_CHECK(oo::date::dateWithTimeIntervalSince1970(interval + 978307200.0) == t);
}

OO_TEST(nowAgreesWithTheSystemClock)
{
	const double before = oo::date::timeIntervalSinceReferenceDate();
	const double sys = std::chrono::duration<double>(Clock::now().time_since_epoch()).count() - 978307200.0;
	const double after = oo::date::timeIntervalSinceReferenceDate();
	OO_CHECK(before <= sys + 1e-3);
	OO_CHECK(sys <= after + 1e-3);
	OO_CHECK(before > 7.5e8);   // after 2024: it is a real wall-clock reading, not an uptime
}

OO_TEST(descriptionFormat)
{
	// 2026-09-23 14:03:12.9 UTC: seconds truncate, as NSCalendarDate's %S does.
	const Clock::time_point t = unix(1790172192) + std::chrono::milliseconds(900);
	OO_CHECK_EQ(oo::date::description(t, 0), std::string("2026-09-23 14:03:12 +0000"));
	OO_CHECK_EQ(oo::date::description(t, 60), std::string("2026-09-23 15:03:12 +0100"));
	OO_CHECK_EQ(oo::date::description(t, -330), std::string("2026-09-23 08:33:12 -0530"));
	OO_CHECK_EQ(oo::date::description(unix(951782400), 0), std::string("2000-02-29 00:00:00 +0000"));   // leap day
	OO_CHECK_EQ(oo::date::description(unix(-1), 0), std::string("1969-12-31 23:59:59 +0000"));
	OO_CHECK_EQ(oo::date::description(unix(1790121600), -60), std::string("2026-09-22 23:00:00 -0100"));   // day rolls back

	// The local form has the same shape and a whole-minute offset within a day.
	const std::string local = oo::date::description(t);
	OO_CHECK_EQ(local.size(), std::string("2026-09-23 14:03:12 +0000").size());
	OO_CHECK(local[4] == '-' && local[7] == '-' && local[10] == ' ' && local[13] == ':' && local[16] == ':');
	OO_CHECK(local[20] == '+' || local[20] == '-');
	const int offset = oo::date::localUTCOffsetMinutes(t);
	OO_CHECK(offset > -24 * 60 && offset < 24 * 60);
	OO_CHECK_EQ(local, oo::date::description(t, offset));
}

OO_TEST(monotonicSecondsNeverGoBack)
{
	double last = oo::date::monotonicSeconds();
	for (int i = 0; i < 1000; i++)
	{
		const double now = oo::date::monotonicSeconds();
		OO_CHECK(now >= last);
		last = now;
	}
}

} // namespace

OO_TEST_MAIN()
