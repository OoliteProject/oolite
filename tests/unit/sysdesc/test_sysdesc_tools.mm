/*	test_sysdesc_tools.mm
	Regression test for the localisation tools in src/Core/OOConvertSystemDescriptions.mm (bead
	oo-vjwp): --export-sysdesc, --compile-sysdesc and the line converter they share.

	oo-xh1g ported the tools from Foundation to oo::PList / std::string. The port visits
	dictionaries in key order (byte order) where the Foundation code visited them in hash order,
	which decides the slot an unknown key is given, the order of the "Assigning key" log lines and
	the order of the written dictionaries' keys. The digests below were CAPTURED FROM THE PORTED
	TOOL (tree at bead/oo-xh1g), not from the Foundation original: they pin the new behaviour so
	that a later change to it shows, and say nothing about what the hash-ordered original wrote.

	Built and run by tools/check-sysdesc-tools.sh, which compiles the tree's
	OOConvertSystemDescriptions.mm against the stubs in this directory (ResourceManager: the
	sysdesc inputs and the diagnostic files it writes; Universe: the descriptions) and runs it over
	the shipped Resources/Config/descriptions.plist.

	Scenarios, each recorded as lines (every file written: its name, length and FNV-1a; every
	message logged) and digested:
	  A  export, old-style, no key table
	  B  export, XML, no key table
	  C  export, old-style, the key table below
	  D  compile, old-style, sysdesc.plist = A's output, no key table (every key is unknown, so
	     each is assigned a slot and logged)
	  E  compile, XML, sysdesc.plist = C's output, the key table below
	Then the line converter directly, over hand-written lines with the expected results spelled
	out (UTF-16 units, a missing "]", digits only).

	Run with --print to see the recorded lines and the digests.
*/

#import "Universe.h"
#import "ResourceManager.h"
#import "OOConvertSystemDescriptions.h"
#import "OOFoundationBridge.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/String.hpp"
#include <stdint.h>
#include <stdio.h>
#include <string.h>


namespace {

std::vector<std::string>				sLines;
oo::PList								sDescriptions;
oo::PList								sSysdesc;
oo::PList								sKeyTable;
std::map<std::string, oo::Data>			sWritten;


uint64_t FNV1a(const void *bytes, size_t length, uint64_t hash = 14695981039346656037ULL)
{
	const unsigned char *p = static_cast<const unsigned char *>(bytes);
	for (size_t i = 0; i < length; i++)
	{
		hash ^= p[i];
		hash *= 1099511628211ULL;
	}
	return hash;
}


// The shipped key table has no copy in Resources/Config: a small one with names for a few
// blocks (and one index no block has).
oo::PList KeyTable()
{
	oo::PList::Dict table;
	table.emplace("0", oo::PList("planet_is"));
	table.emplace("3", oo::PList("is_famous"));
	table.emplace("14", oo::PList("system_description_root"));
	table.emplace("999", oo::PList("no_such_block"));
	return oo::PList(std::move(table));
}

}	// namespace


// --- stubs -------------------------------------------------------------------------------------

BOOL OOLogWillDisplayMessagesInClass(NSString *cls) { return YES; }
void OOLogWithFunctionFileAndLineAndArguments(NSString *cls, const char *fn, const char *file, unsigned long line, NSString *fmt, va_list args)
{
	NSString *msg = [[[NSString alloc] initWithFormat:fmt arguments:args] autorelease];
	sLines.push_back(oo::str::format("log [%s] %s", oo::StdString(cls).c_str(), oo::StdString(msg).c_str()));
}
void OOLogWithFunctionFileAndLine(NSString *cls, const char *fn, const char *file, unsigned long line, NSString *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	OOLogWithFunctionFileAndLineAndArguments(cls, fn, file, line, fmt, args);
	va_end(args);
}


@implementation ResourceManager
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName
								  inFolder:(const std::optional<std::string> &)folderName
								  andMerge:(BOOL)mergeFiles
{
	if (fileName == "sysdesc.plist")  return sSysdesc;
	if (fileName == "sysdesc_key_table.plist")  return sKeyTable;
	return oo::PList();
}

+ (BOOL) cxx_writeDiagnosticData:(const oo::Data &)data toFileNamed:(const std::string &)name
{
	sWritten[name] = data;
	sLines.push_back(oo::str::format("file %s %zu %016llx", name.c_str(), data.length(), (unsigned long long)FNV1a(data.bytes(), data.length())));
	return YES;
}
@end


@implementation Universe
- (NSDictionary *) descriptions { return oo::ObjectFromPList(sDescriptions); }
// The C++ form the tools call since oo-3rb.310, over the same data (bead oo-3rb.335: stub-API tracking).
- (const oo::PList *) cxx_descriptions { return &sDescriptions; }
@end
static Universe *sUniverse;
Universe *OOGetUniverse(void) { return sUniverse; }


// --- the scenarios -----------------------------------------------------------------------------

namespace {

struct Scenario
{
	const char	*name;
	uint64_t	expected;
};

// Captured from the ported tool (see the banner).
const Scenario kScenarios[] =
{
	{ "A export old-style",				0x81612e0e9ecf253fULL },
	{ "B export XML",					0x3ad86808b5dba106ULL },
	{ "C export old-style keyed",		0x243092ab184eb628ULL },
	{ "D compile old-style",			0x9d31777f9d26629bULL },
	{ "E compile XML keyed",			0x42d5cd4b07367714ULL },
};


oo::PList Parse(const oo::Data &data)
{
	auto parsed = oo::parsePropertyList(std::string_view(reinterpret_cast<const char *>(data.bytes()), data.length()));
	return parsed ? *parsed : oo::PList();
}


uint64_t Digest(const std::vector<std::string> &lines)
{
	uint64_t hash = 14695981039346656037ULL;
	for (const std::string &line : lines)
	{
		hash = FNV1a(line.data(), line.size(), hash);
		hash = FNV1a("\n", 1, hash);
	}
	return hash;
}


int sFailures = 0;


void CheckLine(const char *line, const oo::PList &keys, BOOL useFallback, const char *expected, bool print)
{
	const std::string result = OOStringifySystemDescriptionLine(line, keys, useFallback);
	if (print)  printf("line \"%s\" (%s) -> \"%s\"\n", line, useFallback ? "fallback" : "no fallback", result.c_str());
	if (result != expected)
	{
		printf("FAIL: line \"%s\" (%s): got \"%s\", expected \"%s\"\n", line, useFallback ? "fallback" : "no fallback", result.c_str(), expected);
		sFailures++;
	}
}

}	// namespace


int main(int argc, const char *argv[])
{
	@autoreleasepool
	{
		if (argc < 2)
		{
			fprintf(stderr, "usage: %s descriptions.plist [--print]\n", argv[0]);
			return 2;
		}
		const bool print = (argc > 2 && strcmp(argv[2], "--print") == 0);

		auto file = oo::fs::readFile(oo::fs::pathFromUTF8(argv[1]));
		if (!file)
		{
			fprintf(stderr, "cannot read %s\n", argv[1]);
			return 2;
		}
		sDescriptions = Parse(*file);
		if (!sDescriptions.isDict())
		{
			fprintf(stderr, "cannot parse %s\n", argv[1]);
			return 2;
		}
		sUniverse = [[Universe alloc] init];

		std::vector<std::vector<std::string>> recorded;
		auto run = [&](void (^body)(void))
		{
			sLines.clear();
			body();
			recorded.push_back(sLines);
		};

		sKeyTable = oo::PList();
		run(^{ ExportSystemDescriptions(NO); });
		const oo::Data exportedPlain = sWritten["sysdesc.plist"];
		run(^{ ExportSystemDescriptions(YES); });
		sKeyTable = KeyTable();
		run(^{ ExportSystemDescriptions(NO); });
		const oo::Data exportedKeyed = sWritten["sysdesc.plist"];

		sKeyTable = oo::PList();
		sSysdesc = Parse(exportedPlain);
		run(^{ CompileSystemDescriptions(NO); });
		sKeyTable = KeyTable();
		sSysdesc = Parse(exportedKeyed);
		run(^{ CompileSystemDescriptions(YES); });

		for (size_t i = 0; i < recorded.size(); i++)
		{
			const uint64_t digest = Digest(recorded[i]);
			if (print)
			{
				for (const std::string &line : recorded[i])  printf("%s: %s\n", kScenarios[i].name, line.c_str());
			}
			printf("%-28s %016llx%s\n", kScenarios[i].name, (unsigned long long)digest, (digest == kScenarios[i].expected) ? "" : "  MISMATCH");
			if (digest != kScenarios[i].expected)  sFailures++;
		}

		// The line converter. "[#key]" for a known index (or block_N with the fallback), other
		// brackets as they stand, UTF-16 units kept, a "[" with no "]" after it left alone.
		const oo::PList keys = KeyTable();
		CheckLine("[0] and [3]", keys, NO, "[#planet_is] and [#is_famous]", print);
		CheckLine("[0] and [7]", keys, NO, "[#planet_is] and [7]", print);
		CheckLine("[0] and [7]", keys, YES, "[#planet_is] and [#block_7]", print);
		CheckLine("[x0] [] [0x] [#3]", keys, YES, "[x0] [] [0x] [#3]", print);
		CheckLine("\xC3\xA9[3]\xF0\x9F\x98\x80[14]", keys, NO, "\xC3\xA9[#is_famous]\xF0\x9F\x98\x80[#system_description_root]", print);
		CheckLine("[3] then [0", keys, NO, "[#is_famous] then [0", print);
		CheckLine("]x[3]", keys, NO, "]x[3]", print);
		CheckLine("[007]", keys, NO, "[007]", print);
		CheckLine("[007]", keys, YES, "[#block_7]", print);
		CheckLine("", keys, YES, "", print);

		if (sFailures != 0)
		{
			printf("test_sysdesc_tools: %d failure(s)\n", sFailures);
			return 1;
		}
		printf("test_sysdesc_tools: OK\n");
	}
	return 0;
}
