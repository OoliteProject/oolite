/*	oofnd/Date.hpp
        oo::date: the replacement for NSDate, on std::chrono. double
   stays a double count of seconds (the Foundation-types header keeps the
   typedef).

            Foundation                                      oofnd
            ----------------------------------------------
   ------------------------------------------ NSDate used as a stopwatch / frame
   clock: t = [NSDate timeIntervalSinceReferenceDate];  t =
   oo::date::monotonicSeconds();
              ... now - t                                    ... (only
   differences are meaningful) [NSDate dateWithTimeIntervalSinceNow:s]
   std::chrono::steady_clock::now() + seconds (a deadline) (a time_point) NSDate
   used as a wall clock (a value that is stored, shown or compared across runs):
              [NSDate timeIntervalSinceReferenceDate]
   oo::date::timeIntervalSinceReferenceDate()
              [[NSDate date] timeIntervalSince1970]
   oo::date::timeIntervalSince1970() [NSDate date]
   std::chrono::system_clock::now() [NSDate dateWithTimeIntervalSince1970:s]
   oo::date::dateWithTimeIntervalSince1970(s) [date description], "%@" of an
   NSDate          oo::date::description(t)

        SEMANTICS, each as GNUstep has them:

          * The reference date is 2001-01-01 00:00:00 UTC, 978307200 s after the
   Unix epoch, so timeIntervalSinceReferenceDate() returns the same number
   NSDate did (the unit test pins the conversion). Use it only where the value
   itself matters; a pure interval should use monotonicSeconds(), which never
   jumps when the wall clock is set.
          * description() is NSDate's -description: NSCalendarDate's default
   format
            "%Y-%m-%d %H:%M:%S %z" in the local time zone, e.g. "2026-09-23
   14:03:12 +0100"; seconds are truncated, not rounded.
*/

#pragma once

#include <chrono>
#include <cstdint>
#include <ctime>
#include <format>
#include <string>

namespace oo::date {

using Clock = std::chrono::system_clock;

// Seconds from the Unix epoch to NSDate's reference date, 2001-01-01 00:00:00
// UTC.
inline constexpr std::int64_t kReferenceDateSince1970 = 978307200;

// Seconds as a double, double's representation.
inline double secondsSinceEpoch(Clock::time_point t) {
  return std::chrono::duration<double>(t.time_since_epoch()).count();
}

inline double timeIntervalSince1970(Clock::time_point t = Clock::now()) {
  return secondsSinceEpoch(t);
}

inline double timeIntervalSinceReferenceDate(
    Clock::time_point t = Clock::now()) {
  return secondsSinceEpoch(t) - static_cast<double>(kReferenceDateSince1970);
}

inline Clock::time_point dateWithTimeIntervalSince1970(double seconds) {
  return Clock::time_point(std::chrono::duration_cast<Clock::duration>(
      std::chrono::duration<double>(seconds)));
}

inline Clock::time_point dateWithTimeIntervalSinceReferenceDate(
    double seconds) {
  return dateWithTimeIntervalSince1970(
      seconds + static_cast<double>(kReferenceDateSince1970));
}

// A monotonic clock in seconds from an arbitrary origin: for intervals only.
inline double monotonicSeconds() {
  return std::chrono::duration<double>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

// NSDate -description at a given UTC offset: "YYYY-MM-DD HH:MM:SS +hhmm".
inline std::string description(Clock::time_point t, int utcOffsetMinutes) {
  using namespace std::chrono;
  // The calendar date of t shifted by the offset, from std::chrono's civil
  // calendar: no time-zone database and no gmtime, so the result does not
  // depend on the C runtime.
  const sys_seconds local =
      floor<seconds>(t) + minutes(static_cast<long long>(utcOffsetMinutes));
  const sys_days day = floor<days>(local);
  const year_month_day date{day};
  const hh_mm_ss<seconds> time{local - day};
  const int offset =
      utcOffsetMinutes < 0 ? -utcOffsetMinutes : utcOffsetMinutes;
  return std::format(
      "{:04}-{:02}-{:02} {:02}:{:02}:{:02} {}{:02}{:02}",
      static_cast<int>(date.year()), static_cast<unsigned>(date.month()),
      static_cast<unsigned>(date.day()), time.hours().count(),
      time.minutes().count(), time.seconds().count(),
      utcOffsetMinutes < 0 ? '-' : '+', offset / 60, offset % 60);
}

// The local time zone's UTC offset at t, in minutes (daylight saving included).
inline int localUTCOffsetMinutes(Clock::time_point t) {
  const std::time_t secs = Clock::to_time_t(t);
  std::tm local{};
#ifdef _WIN32
  if (localtime_s(&local, &secs) != 0) return 0;
  const std::time_t asIfUTC = _mkgmtime(&local);
#else
  if (localtime_r(&secs, &local) == nullptr) return 0;
  const std::time_t asIfUTC = timegm(&local);
#endif
  return static_cast<int>((asIfUTC - secs) / 60);
}

// NSDate -description in the local time zone.
inline std::string description(Clock::time_point t = Clock::now()) {
  return description(t, localUTCOffsetMinutes(t));
}

}  // namespace oo::date
