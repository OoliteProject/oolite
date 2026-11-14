/*	test_defaults.cpp
	Unit tests for oofnd/Defaults.hpp (bead oo-32f): oo::Defaults against NSUserDefaults as the
	game runs it today (gnustep-base 1.31 with NSUserDefaults+Override and NSBundle+Override).
	Every expected value and byte string below was captured from a probe program linked against
	that gnustep-base on this toolchain (proposed ADR-0032).

	OOCocoa.h's true/false macros are defined first, exactly as the game has them, so this file
	also proves Defaults.hpp (and all it includes) survives them and hands them back.
*/

#define true						1
#define false						0

#include "oofnd/Defaults.hpp"

#include <type_traits>

static_assert(std::is_same_v<decltype(true), int>, "Defaults.hpp must restore OOCocoa.h's true macro");
static constexpr int kTrueAfter = true;

#undef true
#undef false

#include "oo_test.hpp"

#include <cmath>
#include <filesystem>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace {

namespace fs = oo::fs;
using oo::PList;

std::string written(const PList& p, const oo::defaults_detail::SinglePrecision& single = {})
{
	return oo::writeOpenStepPList(p, single).toString();
}

// A fresh, empty directory per test.
fs::Path scratch(const char* name)
{
	std::error_code ec;
	fs::Path dir = std::filesystem::temp_directory_path(ec) / "oofnd-test-defaults" / name;
	std::filesystem::remove_all(dir, ec);
	return dir;
}

void put(const fs::Path& file, const std::string& text)
{
	OO_CHECK(fs::createDirectories(file.parent_path()));
	OO_CHECK(fs::writeFile(file, oo::Data::fromString(text)));
}

std::optional<std::string> contents(const fs::Path& file)
{
	fs::Result<oo::Data> d = fs::readFile(file);
	if (!d)  return std::nullopt;
	return d->toString();
}

// The persistent domain GNUstep read back in the probe; its values use GNUstep's <*..> forms.
const char* const kProbeInput =
	"{ setInteger = 123456789012; t1 = YES; t2 = yes; t3 = \" 12\"; t4 = \"0x10\"; t5 = \"12abc\"; t6 = true;"
	" t7 = \"+5\"; t8 = \"-0\"; t9 = \"  -3.5e1x\"; t10 = NO; t11 = <*BY>; t12 = <*I7>; t13 = <*R2.5>;"
	" t14 = \"00001\"; t15 = \"Tq\"; t16 = \"0 0 9\"; }";

} // namespace

OO_TEST(cocoaMacrosAreRestored)
{
	OO_CHECK_EQ(kTrueAfter, 1);
}

// --- NSString coercions (NSUserDefaults -boolForKey: / -integerForKey: / -doubleForKey:) ------

OO_TEST(stringBoolValueMatchesGNUstep)
{
	using oo::defaults_detail::stringBoolValue;
	const std::map<std::string, bool> probed = {
		{"YES", true}, {"yes", true}, {"true", true}, {"Tq", true}, {" 12", true}, {"12abc", true},
		{"+5", true}, {"00001", true}, {"0 0 9", true}, {"  -3.5e1x", true}, {"1e3", true},
		{"+-3", true}, {"-7", true}, {"NO", false}, {"0x10", false}, {"-0", false}, {"hello", false},
		{"0.1", false}, {".5", false}, {"", false}, {"inf", false}, {"\xC2\xA0" "12", false},
	};
	for (const auto& [s, b] : probed)  OO_CHECK_EQ(stringBoolValue(s), b);
}

OO_TEST(stringIntegerValueMatchesGNUstep)
{
	using oo::defaults_detail::stringIntegerValue;
	const std::map<std::string, std::int64_t> probed = {
		{" 12", 12}, {"0x10", 0}, {"12abc", 12}, {"+5", 5}, {"  -3.5e1x", -3}, {"YES", 0}, {"1e3", 1},
		{" \t+7", 7}, {"\n12", 12}, {"\v5", 5}, {"\f5", 5}, {"\r5", 5}, {".5", 0}, {"5.", 5},
		{"+-3", 0}, {"-3.9", -3}, {"1,5", 1}, {"4294967296", 4294967296LL}, {"123456789012", 123456789012LL},
		{"\xC2\xA0" "12", 0}, {"99999999999999999999", -1}, {"-99999999999999999999", INT64_MIN},
		{"", 0}, {"  -", 0},
	};
	for (const auto& [s, i] : probed)  OO_CHECK_EQ(stringIntegerValue(s), i);
}

OO_TEST(stringDoubleValueMatchesGNUstep)
{
	using oo::defaults_detail::stringDoubleValue;
	const std::map<std::string, double> probed = {
		{"0.1", 0.1}, {"  -3.5e1x", -35.0}, {"0x10", 0.0}, {"1e3", 1000.0}, {"inf", 0.0}, {"nan", 0.0},
		{"0x1p3", 0.0}, {".5", 0.5}, {"5.", 5.0}, {"1e", 1.0}, {"1e+", 1.0}, {"-.5e-1", -0.05},
		{"\xC2\xA0" "12", 12.0}, {"1e-400", 0.0}, {"  -", 0.0}, {"+-3", 0.0}, {"3.9", 3.9}, {"12\xC3\xA9", 12.0},
		{"1,5", 1.0}, {"YES", 0.0},
	};
	for (const auto& [s, d] : probed)  OO_CHECK_EQ(stringDoubleValue(s), d);
	OO_CHECK(std::isinf(stringDoubleValue("1e400")));
	OO_CHECK(std::signbit(stringDoubleValue("-0")));
	OO_CHECK_EQ(static_cast<float>(stringDoubleValue("0.1")), 0.1f);
}

// --- the OpenStep writer (NSUserDefaults+Override's format) ---------------------------------

OO_TEST(openStepStringsAreBareOnlyWhenAlphanumeric)
{
	for (int c = 32; c < 127; ++c)
	{
		const std::string s = std::string("a") + static_cast<char>(c) + "b";
		const bool alnum = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
		std::string expected = alnum ? s : "\"" + s + "\"";
		if (c == '"')  expected = "\"a\\\"b\"";
		if (c == '\\')  expected = "\"a\\\\b\"";
		OO_CHECK_EQ(written(PList(s)), expected);
	}
	OO_CHECK_EQ(written(PList("")), std::string("\"\""));
	OO_CHECK_EQ(written(PList("1")), std::string("1"));
	OO_CHECK_EQ(written(PList("-")), std::string("\"-\""));
}

OO_TEST(openStepEscapesControlsAndNonASCII)
{
	const char* const probed[32] = {
		nullptr, "\"\\001\"", "\"\\002\"", "\"\\003\"", "\"\\004\"", "\"\\005\"", "\"\\006\"", "\"\\a\"", "\"\\b\"",
		"\"\t\"", "\"\n\"", "\"\\v\"", "\"\\f\"", "\"\r\"", "\"\\016\"", "\"\\017\"", "\"\\020\"", "\"\\021\"",
		"\"\\022\"", "\"\\023\"", "\"\\024\"", "\"\\025\"", "\"\\026\"", "\"\\027\"", "\"\\030\"", "\"\\031\"",
		"\"\\032\"", "\"\\033\"", "\"\\034\"", "\"\\035\"", "\"\\036\"", "\"\\037\"",
	};
	for (int c = 1; c < 32; ++c)  OO_CHECK_EQ(written(PList(std::string(1, static_cast<char>(c)))), std::string(probed[c]));
	OO_CHECK_EQ(written(PList("\x7f")), std::string("\"\\177\""));
	OO_CHECK_EQ(written(PList("\xC2\x80")), std::string("\"\\U0080\""));
	OO_CHECK_EQ(written(PList("caf\xC3\xA9 \xE2\x98\x83")), std::string("\"caf\\U00E9 \\U2603\""));
	OO_CHECK_EQ(written(PList("\xEF\xBF\xBD")), std::string("\"\\UFFFD\""));
	OO_CHECK_EQ(written(PList("\xF0\x9F\x98\x80")), std::string("\"\\UD83D\\UDE00\""));
}

OO_TEST(openStepContainersNumbersAndData)
{
	OO_CHECK_EQ(written(PList(PList::Array{})), std::string("(\n)"));
	OO_CHECK_EQ(written(PList(PList::Dict{})), std::string("{\n}"));
	OO_CHECK_EQ(written(PList(oo::Data())), std::string("<>"));
	OO_CHECK_EQ(written(PList(oo::Data("\x01\x02\x03\x04\x05\x06\x07\x08\x09", 9))), std::string("<01020304 05060708 09>"));
	OO_CHECK_EQ(written(PList(PList::Array{PList("x"), PList(PList::Dict{{"k", PList(PList::Array{})}})})),
		std::string("(\n    x,\n    {\n\tk = (\n\t);\n    }\n)"));
	// Keys in UTF-16 order: upper case before lower case, "~" before U+2603.
	OO_CHECK_EQ(written(PList(PList::Dict{{"b", "x"}, {"B", "y"}, {"a", "z"}, {"A", "w"}, {"~", "u"}, {"\xE2\x98\x83", "t"}})),
		std::string("{\n    A = w;\n    B = y;\n    a = z;\n    b = x;\n    \"~\" = u;\n    \"\\U2603\" = t;\n}"));
	OO_CHECK_EQ(written(PList(1e21)), std::string("\"1e+21\""));
	OO_CHECK_EQ(written(PList(123456789012345678.0)), std::string("\"1.234567890123457e+17\""));
	OO_CHECK_EQ(written(PList(INFINITY)), std::string("inf"));
	OO_CHECK_EQ(written(PList(-INFINITY)), std::string("\"-inf\""));
	OO_CHECK_EQ(written(PList(std::nan(""))), std::string("nan"));
	OO_CHECK_EQ(written(PList(true)), std::string("1"));
	OO_CHECK_EQ(written(PList(std::int16_t{-3})), std::string("\"-3\""));
	OO_CHECK_EQ(written(PList(4000000000u)), std::string("4000000000"));

	// Seven levels deep: the indentation is GNUstep's, 4 spaces per level with 8 spaces as a tab.
	PList deep("deep");
	for (int i = 0; i < 6; ++i)  deep = PList(PList::Array{deep});
	OO_CHECK_EQ(written(PList(PList::Dict{{"k", deep}})),
		std::string("{\n    k = (\n\t(\n\t    (\n\t\t(\n\t\t    (\n\t\t\t(\n\t\t\t    deep\n\t\t\t)\n\t\t    )\n\t\t)\n\t    )\n\t)\n    );\n}"));
}

OO_TEST(openStepNumberDescriptionsFromTheProbe)
{
	PList::Array nums = {
		0.1 + 0.2, 1.0 / 3, 1e-5, PList(std::uint64_t{100}), 1e16, 123456789.125, 5e-324, 1e300, -0.0, 0.5,
		1.0f / 3, 16777217.0f, 1e-5f,
		PList(UINT64_MAX), PList(INT64_MIN), PList(false), PList(std::int64_t{65}), PList(std::uint64_t{200}),
	};
	nums[3] = PList(100.0);
	PList root(PList::Dict{{"nums", PList(nums)}});
	const PList::Array& a = *root.find("nums")->getIf<PList::Array>();
	auto single = [&](const PList& p) { return &p == &a[10] || &p == &a[11] || &p == &a[12]; };
	OO_CHECK_EQ(written(root, single), std::string(
		"{\n    nums = (\n\t\"0.3\",\n\t\"0.3333333333333333\",\n\t\"1e-05\",\n\t100,\n\t\"1e+16\",\n"
		"\t\"123456789.125\",\n\t\"4.940656458412465e-324\",\n\t\"1e+300\",\n\t\"-0\",\n\t\"0.5\",\n"
		"\t\"0.3333333\",\n\t\"1.677722e+07\",\n\t\"1e-05\",\n\t18446744073709551615,\n"
		"\t\"-9223372036854775808\",\n\t0,\n\t65,\n\t200\n    );\n}"));
}

// --- arguments, domain name, directory ------------------------------------------------------

OO_TEST(argumentDomainMatchesGNUstep)
{
	const PList::Dict args = oo::parseDefaultsArguments({
		"probe.exe", "-a", "1", "-b", "-c", "(x,y)", "-d", "{k=v;}", "-e", "hello world", "-f", "\"q\"", "-",
		"-g", "--", "h", "-i", "<0102>", "-load", "save.oolite-save", "file.txt",
		"-k", "<?xml version=\"1.0\"?><plist><true/></plist>", "-m", "", "-n", "<*I5>", "-o", "a;",
		"-p", "(unterminated", "-j",
	});
	const PList::Dict expected = {
		{"-", "h"}, {"a", "1"}, {"c", PList(PList::Array{"x", "y"})}, {"d", PList(PList::Dict{{"k", "v"}})},
		{"e", "hello world"}, {"f", "q"}, {"i", PList(oo::Data("\x01\x02", 2))}, {"k", true},
		{"load", "save.oolite-save"}, {"m", ""}, {"n", PList::unsignedInteger(5)}, {"o", "a;"}, {"p", "(unterminated"},
	};
	OO_CHECK(args == expected);
	OO_CHECK(args.find("b") == args.end());
	OO_CHECK(args.find("j") == args.end());

	const PList::Dict again = oo::parseDefaultsArguments({"probe", "loose", "-x", "1", "-x", "2", "--NSx", "y"});
	OO_CHECK(again == (PList::Dict{{"x", "2"}, {"-NSx", "y"}}));
}

OO_TEST(applicationDomainIsTheBundleIdentifierElseTheProcessName)
{
	OO_CHECK_EQ(oo::applicationDomainName(PList(PList::Dict{{"CFBundleIdentifier", "oolite"}}), "probe"), std::string("oolite"));
	OO_CHECK_EQ(oo::applicationDomainName(PList(), "probe"), std::string("probe"));
	OO_CHECK_EQ(oo::applicationDomainName(PList(PList::Dict{{"CFBundleIdentifier", ""}}), "oolite"), std::string("oolite"));
}

OO_TEST(defaultsDirectoryIsHomeGNUstepDefaults)
{
	auto make = [](oo::PathEnvironment::Platform platform, std::map<std::string, std::string> vars) {
		oo::PathEnvironment env;
		env.platform = platform;
		env.getenv = [vars](const std::string& n) -> std::optional<std::string> {
			auto it = vars.find(n);
			if (it == vars.end())  return std::nullopt;
			return it->second;
		};
		return oo::ResourcePaths(env);
	};
	using P = oo::PathEnvironment::Platform;
	OO_CHECK_EQ(fs::utf8String(oo::userDefaultsDirectory(make(P::windows, {{"HOMEPATH", "C:\\Games\\Oolite\\oolite.app"}}))),
		std::string("C:/Games/Oolite/oolite.app/GNUstep/Defaults"));
	OO_CHECK_EQ(fs::utf8String(oo::userDefaultsDirectory(make(P::windows, {{"HOMEPATH", "C:\\g"}, {"OO_GNUSTEPDEFAULTSDIR", "C:\\x"}}))),
		std::string("C:/g/GNUstep/Defaults"));
	OO_CHECK_EQ(fs::utf8String(oo::userDefaultsDirectory(make(P::posix, {{"HOME", "/home/u"}}))), std::string("/home/u/GNUstep/Defaults"));
	OO_CHECK_EQ(fs::utf8String(oo::userDefaultsDirectory(make(P::posix, {{"HOME", "/home/u"}, {"OO_GNUSTEPDEFAULTSDIR", "/data"}}))),
		std::string("/data"));
}

// --- the store ------------------------------------------------------------------------------

OO_TEST(gettersCoerceTheProbedFile)
{
	const fs::Path dir = scratch("getters");
	put(dir / "oolite.plist", kProbeInput);
	oo::Defaults d(dir, "oolite");
	struct Row { const char* key; bool b; std::int64_t i; double f; };
	const Row probed[] = {
		{"setInteger", true, 123456789012LL, 123456789012.0}, {"t1", true, 0, 0}, {"t2", true, 0, 0},
		{"t3", true, 12, 12}, {"t4", false, 0, 0}, {"t5", true, 12, 12}, {"t6", true, 0, 0}, {"t7", true, 5, 5},
		{"t8", false, 0, -0.0}, {"t9", true, -3, -35}, {"t10", false, 0, 0}, {"t11", true, 1, 1},
		{"t12", true, 7, 7}, {"t13", true, 2, 2.5}, {"t14", true, 1, 1}, {"t15", true, 0, 0}, {"t16", true, 0, 0},
		{"missing", false, 0, 0},
	};
	for (const Row& r : probed)
	{
		OO_CHECK_EQ(d.boolForKey(r.key), r.b);
		OO_CHECK_EQ(d.integerForKey(r.key), r.i);
		OO_CHECK_EQ(d.doubleForKey(r.key), r.f);
		OO_CHECK_EQ(d.floatForKey(r.key), static_cast<float>(r.f));
	}
	OO_CHECK(d.stringForKey("t1") == std::optional<std::string>("YES"));
	OO_CHECK(!d.stringForKey("t11"));
	OO_CHECK(!d.stringForKey("missing"));

	d.setObject("arr", PList(PList::Array{"1"}));
	d.setObject("dict", PList(PList::Dict{{"k", "1"}}));
	d.setObject("data", PList(oo::Data("1", 1)));
	for (const char* k : {"arr", "dict", "data"})
	{
		OO_CHECK(!d.boolForKey(k));
		OO_CHECK_EQ(d.integerForKey(k), 0);
		OO_CHECK_EQ(d.doubleForKey(k), 0.0);
		OO_CHECK(!d.stringForKey(k));
	}
	OO_CHECK(d.arrayForKey("arr").isArray() && d.arrayForKey("dict").isNull());
	OO_CHECK(d.dictionaryForKey("dict").isDict() && d.dictionaryForKey("arr").isNull());
	d.setDouble("nan", std::nan(""));
	d.setDouble("big", 1e30);
	d.setDouble("neg0", -0.0);
	OO_CHECK(d.boolForKey("nan") && d.boolForKey("big") && !d.boolForKey("neg0"));
	OO_CHECK_EQ(d.integerForKey("nan"), INT64_MIN);
	OO_CHECK_EQ(d.integerForKey("big"), INT64_MIN);
}

OO_TEST(searchListOrder)
{
	const fs::Path dir = scratch("search");
	put(dir / "oolite.plist", "{ app = fromApp; both = fromApp; }");
	put(dir / "NSGlobalDomain.plist", "{ global = fromGlobal; both = fromGlobal; app = fromGlobal; }");
	oo::Defaults d(dir, "oolite", {{"both", "fromArgs"}});
	d.registerDefaults({{"reg", "fromRegistration"}, {"global", "fromRegistration"}});
	OO_CHECK(d.stringForKey("both") == std::optional<std::string>("fromArgs"));
	OO_CHECK(d.stringForKey("app") == std::optional<std::string>("fromApp"));
	OO_CHECK(d.stringForKey("global") == std::optional<std::string>("fromGlobal"));
	OO_CHECK(d.stringForKey("reg") == std::optional<std::string>("fromRegistration"));
	d.setObject("both", "set");          // the application domain: arguments still win
	OO_CHECK(d.stringForKey("both") == std::optional<std::string>("fromArgs"));
	d.removeObject("app");
	OO_CHECK(d.stringForKey("app") == std::optional<std::string>("fromGlobal"));
}

OO_TEST(synchronizeWritesTheProbedBytes)
{
	const fs::Path dir = scratch("write");
	put(dir / "oolite.plist", kProbeInput);
	oo::Defaults d(dir, "oolite");
	OO_CHECK(d.synchronize());   // nothing changed: the file is left as it is
	OO_CHECK(contents(dir / "oolite.plist") == std::optional<std::string>(kProbeInput));
	d.setObject("t1", "YES");    // the same value: still nothing to write
	OO_CHECK(d.synchronize());
	OO_CHECK(contents(dir / "oolite.plist") == std::optional<std::string>(kProbeInput));

	d.setObject("only", "v");
	OO_CHECK(d.synchronize());
	OO_CHECK(contents(dir / "oolite.plist") == std::optional<std::string>(
		"{\n    only = v;\n    setInteger = 123456789012;\n    t1 = YES;\n    t10 = NO;\n    t11 = 1;\n"
		"    t12 = 7;\n    t13 = \"2.5\";\n    t14 = 00001;\n    t15 = Tq;\n    t16 = \"0 0 9\";\n    t2 = yes;\n"
		"    t3 = \" 12\";\n    t4 = 0x10;\n    t5 = 12abc;\n    t6 = true;\n    t7 = \"+5\";\n    t8 = \"-0\";\n"
		"    t9 = \"  -3.5e1x\";\n}"));
}

OO_TEST(synchronizeCreatesTheDirectoryAndKeepsFloatsSinglePrecision)
{
	const fs::Path dir = scratch("fresh") / "GNUstep" / "Defaults";
	oo::Defaults d(dir, "oolite");
	d.setObject("CustomEquipActivation", PList(PList::Array{}));
	d.setInteger("Jameson-humbletrash", -29624);
	d.setObject("debug-settings-override", PList(PList::Dict{}));
	d.setObject("save-directory", "Resources/Scenarios");
	d.setFloat("volume_control", 0.55f);
	d.setDouble("gamma", 0.55f);
	d.setBool("yes", true);
	OO_CHECK(d.synchronize());
	OO_CHECK(contents(dir / "oolite.plist") == std::optional<std::string>(
		"{\n    CustomEquipActivation = (\n    );\n    \"Jameson-humbletrash\" = \"-29624\";\n"
		"    \"debug-settings-override\" = {\n    };\n    gamma = \"0.550000011920929\";\n"
		"    \"save-directory\" = \"Resources/Scenarios\";\n    \"volume_control\" = \"0.55\";\n    yes = 1;\n}"));
	// Until the next run the values keep their types, as NSNumbers did.
	OO_CHECK_EQ(d.floatForKey("volume_control"), 0.55f);
	OO_CHECK(d.object("yes") == PList(true));
	// ...and the next run reads strings.
	oo::Defaults next(dir, "oolite");
	OO_CHECK(next.object("volume_control") == PList("0.55"));
	OO_CHECK_EQ(next.floatForKey("volume_control"), 0.55f);
	OO_CHECK_EQ(next.integerForKey("Jameson-humbletrash"), -29624);
}

OO_TEST(synchronizeMergesOntoAnotherWritersFile)
{
	const fs::Path dir = scratch("merge");
	put(dir / "oolite.plist", "{ nums = (1); only = v; }");
	oo::Defaults d(dir, "oolite");
	d.setObject("local", "mine");
	put(dir / "oolite.plist", "{ext = fromdisk; nums = 1;}");   // someone else synchronized meanwhile
	OO_CHECK(!d.stringForKey("ext"));                              // not seen before synchronize
	OO_CHECK(d.synchronize());
	OO_CHECK(d.stringForKey("ext") == std::optional<std::string>("fromdisk"));
	OO_CHECK(!d.stringForKey("only"));
	OO_CHECK(contents(dir / "oolite.plist") == std::optional<std::string>("{\n    ext = fromdisk;\n    local = mine;\n    nums = 1;\n}"));
}

OO_TEST(synchronizeOfAnEmptyDomainDeletesTheFile)
{
	const fs::Path dir = scratch("empty");
	put(dir / "oolite.plist", "{ a = 1; b = 2; }");
	oo::Defaults d(dir, "oolite");
	d.removeObject("a");
	d.removeObject("b");
	OO_CHECK(d.synchronize());
	OO_CHECK(!fs::fileExists(dir / "oolite.plist"));
}

OO_TEST(otherFormatsAndGarbageOnDisk)
{
	const fs::Path dir = scratch("formats");
	put(dir / "oolite.plist", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict><key>b</key><true/><key>r</key><real>2.5</real></dict></plist>");
	oo::Defaults x(dir, "oolite");
	OO_CHECK(x.boolForKey("b"));
	x.setObject("only", "v");
	OO_CHECK(x.synchronize());
	OO_CHECK(contents(dir / "oolite.plist") == std::optional<std::string>("{\n    b = 1;\n    only = v;\n    r = \"2.5\";\n}"));

	put(dir / "oolite.plist", "{a = ;");
	oo::Defaults g(dir, "oolite");
	OO_CHECK(!g.object("a"));
	g.setObject("only", "v");
	OO_CHECK(g.synchronize());
	OO_CHECK(contents(dir / "oolite.plist") == std::optional<std::string>("{\n    only = v;\n}"));
}

OO_TEST_MAIN()
