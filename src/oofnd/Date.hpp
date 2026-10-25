/*	oofnd/Date.hpp
	oo::date: the replacement for NSDate (bead oo-3rb.11, ADR-0029 Decision 5), on std::chrono.
	NSTimeInterval stays a double count of seconds (the Foundation-types header keeps the typedef).

	    Foundation                                      oofnd
	    ----------------------------------------------  ------------------------------------------
	    NSDate used as a stopwatch / frame clock:
	      t = [NSDate timeIntervalSinceReferenceDate];  t = oo::date::monotonicSeconds();
	      ... now - t                                    ... (only differences are meaningful)
	      [NSDate dateWithTimeIntervalSinceNow:s]        std::chrono::steady_clock::now() + seconds
	      (a deadline)                                   (a time_point)
	    NSDate used as a wall clock (a value that is stored, shown or compared across runs):
	      [NSDate timeIntervalSinceReferenceDate]        oo::date::timeIntervalSinceReferenceDate()
	      [[NSDate date] timeIntervalSince1970]          oo::date::timeIntervalSince1970()
	      [NSDate date]                                  std::chrono::system_clock::now()
	      [NSDate dateWithTimeIntervalSince1970:s]       oo::date::dateWithTimeIntervalSince1970(s)
	      [date description], "%@" of an NSDate          oo::date::description(t)

	SEMANTICS, each as GNUstep has them:

	  * The reference date is 2001-01-01 00:00:00 UTC, 978307200 s after the Unix epoch, so
	    timeIntervalSinceReferenceDate() returns the same number NSDate did (the unit test pins
	    the conversion). Use it only where the value itself matters; a pure interval should use
	    monotonicSeconds(), which never jumps when the wall clock is set.
	  * description() is NSDate's -description: NSCalendarDate's default format
	    "%Y-%m-%d %H:%M:%S %z" in the local time zone, e.g. "2026-09-23 14:03:12 +0100"; seconds
	    are truncated, not rounded.
*/

#ifndef OOFND_DATE_HPP
#define OOFND_DATE_HPP

// Objective-C++ game code includes this after OOCocoa.h, whose `#define true 1` / `#define false 0`
// break the standard headers' keywords. Suspend the macros here (proposed ADR-0028, Data.hpp).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <ctime>
#include <string>

namespace oo::date {

using Clock = std::chrono::system_clock;

// Seconds from the Unix epoch to NSDate's reference date, 2001-01-01 00:00:00 UTC.
inline constexpr std::int64_t kReferenceDateSince1970 = 978307200;

// Seconds as a double, NSTimeInterval's representation.
inline double secondsSinceEpoch(Clock::time_point t)
{
	return std::chrono::duration<double>(t.time_since_epoch()).count();
}

inline double timeIntervalSince1970(Clock::time_point t = Clock::now())
{
	return secondsSinceEpoch(t);
}

inline double timeIntervalSinceReferenceDate(Clock::time_point t = Clock::now())
{
	return secondsSinceEpoch(t) - static_cast<double>(kReferenceDateSince1970);
}

inline Clock::time_point dateWithTimeIntervalSince1970(double seconds)
{
	return Clock::time_point(std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(seconds)));
}

inline Clock::time_point dateWithTimeIntervalSinceReferenceDate(double seconds)
{
	return dateWithTimeIntervalSince1970(seconds + static_cast<double>(kReferenceDateSince1970));
}

// A monotonic clock in seconds from an arbitrary origin: for intervals only.
inline double monotonicSeconds()
{
	return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

// NSDate -description at a given UTC offset: "YYYY-MM-DD HH:MM:SS +hhmm".
inline std::string description(Clock::time_point t, int utcOffsetMinutes)
{
	const std::int64_t unixSeconds = std::chrono::floor<std::chrono::seconds>(t.time_since_epoch()).count();
	const std::int64_t localSeconds = unixSeconds + static_cast<std::int64_t>(utcOffsetMinutes) * 60;

	// Civil date from days since 1970-01-01 (Howard Hinnant's algorithm): no time-zone database
	// and no gmtime, so the result does not depend on the C runtime.
	std::int64_t days = localSeconds / 86400;
	std::int64_t secOfDay = localSeconds % 86400;
	if (secOfDay < 0)  { secOfDay += 86400; days -= 1; }
	days += 719468;
	const std::int64_t era = (days >= 0 ? days : days - 146096) / 146097;
	const std::int64_t doe = days - era * 146097;
	const std::int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
	const std::int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
	const std::int64_t mp = (5 * doy + 2) / 153;
	const std::int64_t day = doy - (153 * mp + 2) / 5 + 1;
	const std::int64_t month = mp < 10 ? mp + 3 : mp - 9;
	const std::int64_t year = yoe + era * 400 + (month <= 2 ? 1 : 0);

	const int offset = utcOffsetMinutes < 0 ? -utcOffsetMinutes : utcOffsetMinutes;
	char buffer[64];
	std::snprintf(buffer, sizeof buffer, "%04lld-%02lld-%02lld %02lld:%02lld:%02lld %c%02d%02d",
				  static_cast<long long>(year), static_cast<long long>(month), static_cast<long long>(day),
				  static_cast<long long>(secOfDay / 3600), static_cast<long long>(secOfDay / 60 % 60),
				  static_cast<long long>(secOfDay % 60),
				  utcOffsetMinutes < 0 ? '-' : '+', offset / 60, offset % 60);
	return std::string(buffer);
}

// The local time zone's UTC offset at t, in minutes (daylight saving included).
inline int localUTCOffsetMinutes(Clock::time_point t)
{
	const std::time_t secs = Clock::to_time_t(t);
	std::tm local {};
#ifdef _WIN32
	if (localtime_s(&local, &secs) != 0)  return 0;
	const std::time_t asIfUTC = _mkgmtime(&local);
#else
	if (localtime_r(&secs, &local) == nullptr)  return 0;
	const std::time_t asIfUTC = timegm(&local);
#endif
	return static_cast<int>((asIfUTC - secs) / 60);
}

// NSDate -description in the local time zone.
inline std::string description(Clock::time_point t = Clock::now())
{
	return description(t, localUTCOffsetMinutes(t));
}

} // namespace oo::date

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_DATE_HPP
