/*	oofnd/Thread.hpp
        oo::thread: what Oolite asked of NSThread, on std::thread (bead oo-3rb.6, proposed ADR-0029
        Decision 5).

            Foundation                                    oofnd
            --------------------------------------------  ----------------------------------------------
            [NSThread detachNewThreadSelector:s           oo::thread::detach([obj] { { oo::AutoreleaseScope p;
                                     toTarget:obj                              [obj s]; } ... })
                                   withObject:arg]        (the caller retains obj for the thread's life
                                                          and opens the pool: see below)
            [NSThread isMainThread],                      oo::thread::isMainThread()
              [[NSThread currentThread] isMainThread]
            [[NSThread currentThread] setName:n],         oo::thread::setCurrentName(utf8)
              +[NSThread ooSetCurrentThreadName:]
            [NSThread setThreadPriority:p]  (0.0 .. 1.0)  oo::thread::setCurrentPriority(p)
            [[NSThread currentThread] threadDictionary]   a C++ thread_local

        SEMANTICS:

          * detach() runs the callable on a new, detached std::thread. NSThread retained its target
            until the selector returned and gave the thread no autorelease pool; an Objective-C caller
            therefore retains the target before detach() and releases it at the end of the callable,
            and opens an oo::AutoreleaseScope inside it (a thread without one leaks what it autoreleases).
          * The main thread is the thread that ran static initialisation, i.e. the one that calls
            main(): its id is captured then (kMainThreadId below), before any code in main() runs.
            isMainThread() is false only when asked during another TU's static initialisation before
            this header's inline variable is initialised; nothing in the game does that.
          * setCurrentName(): SetThreadDescription on Windows (what GNUstep's -setName: calls there,
            measured: GetThreadDescription reads the name back), pthread_setname_np elsewhere (Linux
            truncates to 15 bytes, as GNUstep's call did).
          * setCurrentPriority(): GNUstep's mapping, measured on Windows against gnustep-base 1.31:
            p <= 0 IDLE, <= 0.25 LOWEST, < 0.5 BELOW_NORMAL, == 0.5 NORMAL, < 0.75 ABOVE_NORMAL,
            < 1 HIGHEST, >= 1 TIME_CRITICAL. Elsewhere p scales linearly between the current policy's
            sched_get_priority_min and _max, as GNUstep's pthread path does. Returns false if the
            platform call failed.

        Header-only, C++20; compiles with -fno-exceptions.
*/

#ifndef OOFND_THREAD_HPP
#define OOFND_THREAD_HPP

// Objective-C++ callers see OOFoundation.h's `#define true 1` / `#define false 0`; suspend them for the
// standard headers (as oofnd/Data.hpp does, proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include <string>
#include <string_view>
#include <thread>
#include <utility>

#if defined(_WIN32)
// The three kernel32 entry points, declared exactly as <processthreadsapi.h> declares them (HANDLE
// = void *, HRESULT = long, BOOL = int), so this header does not drag <windows.h> (and its BOOL,
// min/max and interface macros) into Objective-C++ game code. A TU that also includes <windows.h>
// sees identical redeclarations.
extern "C" {
__declspec(dllimport) void* __stdcall GetCurrentThread(void);
__declspec(dllimport) long __stdcall SetThreadDescription(void* hThread, const wchar_t* lpThreadDescription);
__declspec(dllimport) int __stdcall SetThreadPriority(void* hThread, int nPriority);
__declspec(dllimport) int __stdcall MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags, const char* lpMultiByteStr, int cbMultiByte, wchar_t* lpWideCharStr, int cchWideChar);
}
#else
#include <pthread.h>
#include <sched.h>
#endif

namespace oo::thread {

// The id of the thread that ran static initialisation (the main thread); see the banner.
inline const std::thread::id kMainThreadId = std::this_thread::get_id();

inline bool isMainThread()
{
    return std::this_thread::get_id() == kMainThreadId;
}

// Runs `body` on a new detached thread. See the banner for the Objective-C retain/pool contract.
template <typename F>
void detach(F&& body)
{
    std::thread(std::forward<F>(body)).detach();
}

inline bool setCurrentName(std::string_view utf8Name)
{
#if defined(_WIN32)
    const std::string name(utf8Name);
    const unsigned int kCP_UTF8 = 65001;
    int units = MultiByteToWideChar(kCP_UTF8, 0, name.c_str(), -1, nullptr, 0);
    if (units <= 0)
        return false;
    std::wstring wide(static_cast<size_t>(units), L'\0');
    if (MultiByteToWideChar(kCP_UTF8, 0, name.c_str(), -1, wide.data(), units) != units)
        return false;
    return SetThreadDescription(GetCurrentThread(), wide.c_str()) >= 0;
#elif defined(__APPLE__)
    const std::string name(utf8Name);
    return pthread_setname_np(name.c_str()) == 0;
#else
    std::string name(utf8Name);
    if (name.size() > 15)
        name.resize(15); // Linux's limit; longer names fail with ERANGE
    return pthread_setname_np(pthread_self(), name.c_str()) == 0;
#endif
}

#if defined(_WIN32)
// GNUstep's NSThread priority -> Windows thread priority (measured; see the banner).
constexpr int windowsPriorityFor(double p)
{
    if (p <= 0.0)
        return -15; // THREAD_PRIORITY_IDLE
    if (p <= 0.25)
        return -2; // THREAD_PRIORITY_LOWEST
    if (p < 0.5)
        return -1; // THREAD_PRIORITY_BELOW_NORMAL
    if (p >= 1.0)
        return 15; // THREAD_PRIORITY_TIME_CRITICAL
    if (p >= 0.75)
        return 2; // THREAD_PRIORITY_HIGHEST
    if (p > 0.5)
        return 1; // THREAD_PRIORITY_ABOVE_NORMAL
    return 0; // THREAD_PRIORITY_NORMAL
}
#endif

inline bool setCurrentPriority(double p)
{
#if defined(_WIN32)
    return SetThreadPriority(GetCurrentThread(), windowsPriorityFor(p)) != 0;
#else
    int policy = 0;
    sched_param param { };
    if (pthread_getschedparam(pthread_self(), &policy, &param) != 0)
        return false;
    const int lo = sched_get_priority_min(policy);
    const int hi = sched_get_priority_max(policy);
    if (p < 0.0)
        p = 0.0;
    if (p > 1.0)
        p = 1.0;
    param.sched_priority = lo + static_cast<int>(p * (hi - lo));
    return pthread_setschedparam(pthread_self(), policy, &param) == 0;
#endif
}

} // namespace oo::thread

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_THREAD_HPP
