/*	test_process.cpp
	Unit tests for oofnd/Process.hpp (bead oo-3rb.18): the NSProcessInfo replacements.
	On Windows this TU includes <windows.h> AFTER the header, which also proves the header's
	kernel32 declarations are identical redeclarations.
*/

#include "oofnd/Process.hpp"

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/utsname.h>
#endif

#include "oo_test.hpp"

#include <cstdlib>
#include <string>
#include <thread>

namespace {

void SetEnv(const char *name, const char *value)
{
#if defined(_WIN32)
	_putenv_s(name, value != nullptr ? value : "");
#else
	if (value != nullptr)  setenv(name, value, 1);
	else  unsetenv(name);
#endif
}

} // namespace

OO_TEST(argumentsAreEmptyUntilSet)
{
	OO_CHECK(oo::process::arguments().empty());
	OO_CHECK(oo::process::processName().empty());
	OO_CHECK(!oo::process::hasArgument("-nodust"));
}

OO_TEST(argumentsAreMainsArgvIncludingArgv0)
{
	const char *argv[] = { "C:\\Games\\Oolite\\oolite.exe", "-nodust", "-message", "h\xC3\xA9llo world" };
	oo::process::setArguments(4, argv);
	const std::vector<std::string>& args = oo::process::arguments();
	OO_CHECK_EQ(args.size(), 4u);
	OO_CHECK_EQ(args[0], std::string("C:\\Games\\Oolite\\oolite.exe"));
	OO_CHECK_EQ(args[3], std::string("h\xC3\xA9llo world"));
	OO_CHECK(oo::process::hasArgument("-nodust"));
	OO_CHECK(oo::process::hasArgument("-message"));
	OO_CHECK(!oo::process::hasArgument("-nosound"));
	OO_CHECK(!oo::process::hasArgument("nodust"));   // exact match, as -containsObject:
}

OO_TEST(setArgumentsReplacesAndToleratesNull)
{
	const char *argv[] = { "oolite", nullptr };
	oo::process::setArguments(2, argv);
	OO_CHECK_EQ(oo::process::arguments().size(), 2u);
	OO_CHECK_EQ(oo::process::arguments()[1], std::string(""));
	OO_CHECK(!oo::process::hasArgument("-nodust"));
}

OO_TEST(processNameIsLastComponentWithoutExtension)
{
	const char *a[] = { "C:\\Games\\Oolite\\oolite.exe" };
	oo::process::setArguments(1, a);
#if defined(_WIN32)
	OO_CHECK_EQ(oo::process::processName(), std::string("oolite"));
#endif
	const char *b[] = { "/usr/games/oolite.app/oolite" };
	oo::process::setArguments(1, b);
	OO_CHECK_EQ(oo::process::processName(), std::string("oolite"));
	const char *c[] = { "relname" };   // GNUstep, measured: argv[0] as typed
	oo::process::setArguments(1, c);
	OO_CHECK_EQ(oo::process::processName(), std::string("relname"));
	const char *d[] = { "./pi.exe" };
	oo::process::setArguments(1, d);
	OO_CHECK_EQ(oo::process::processName(), std::string("pi"));
}

OO_TEST(processorCountIsHardwareConcurrency)
{
	const unsigned hc = std::thread::hardware_concurrency();
	OO_CHECK(oo::process::processorCount() >= 1u);
	if (hc != 0)  OO_CHECK_EQ(oo::process::processorCount(), hc);
}

OO_TEST(operatingSystemVersionStringIsGNUsteps)
{
	const std::string v = oo::process::operatingSystemVersionString();
#if defined(_WIN32)
	const DWORD version = GetVersion();
	OO_CHECK_EQ(v, std::to_string(LOBYTE(LOWORD(version))) + "." + std::to_string(HIBYTE(LOWORD(version))));
#else
	struct utsname uts;
	OO_CHECK_EQ(uname(&uts), 0);
	OO_CHECK_EQ(v, std::string(uts.release));
#endif
	OO_CHECK(v.find('.') != std::string::npos);
}

OO_TEST(envReadsTheLiveEnvironment)
{
	SetEnv("OOFND_TEST_PROCESS_VAR", "plain value");
	std::optional<std::string> v = oo::env("OOFND_TEST_PROCESS_VAR");
	OO_CHECK(v.has_value());
	OO_CHECK_EQ(v.value_or(""), std::string("plain value"));
	OO_CHECK(!oo::env("OOFND_TEST_PROCESS_VAR_THAT_IS_NOT_SET").has_value());
	OO_CHECK(!oo::env(nullptr).has_value());
}

#if defined(_WIN32)
OO_TEST(envValuesArriveAsUTF8)
{
	OO_CHECK(SetEnvironmentVariableW(L"OOFND_TEST_PROCESS_WIDE", L"h\u00E9llo") != 0);
	_wputenv_s(L"OOFND_TEST_PROCESS_WIDE", L"h\u00E9llo");
	OO_CHECK_EQ(oo::env("OOFND_TEST_PROCESS_WIDE").value_or(""), std::string("h\xC3\xA9llo"));
}
#endif

OO_TEST_MAIN()
