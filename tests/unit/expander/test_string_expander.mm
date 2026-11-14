/*	test_string_expander.mm
	Differential regression test for src/Core/OOStringExpander.mm (bead oo-3rb.61).

	The engine of OOExpandDescriptionString() moved from NSString onto UTF-16 units and oo::str.
	Before that, this program was built against the ORIGINAL OOStringExpander.mm (gnustep-base
	1.31.1) with the stubs in this directory standing in for Universe, PlayerEntity,
	ResourceManager, the JavaScript engine and the credit formatter, and it recorded one line per
	expansion: the result's UTF-16 units, the two random generators' next values (so the engine
	must consume them identically) and everything the expander logged. The digests below are
	FNV-1a over those lines; the converted engine reproduces them exactly.

	Corpora:
	  - every key of the shipped Resources/Config/descriptions.plist, 16 planet seeds, 5 option
	    sets (plain; good RNG; good RNG with \n conversion; JavaScript warnings; %I disallowed),
	    with overrides and legacy locals, plus the system description of each seed;
	  - 20,000 generated strings (ExpressionCorpus) mixing [keys], [digits], operator chains
	    with and without parameters, every %-escape, \n, \x7F, byte-order marks, combining marks
	    and lone surrogates, under the same 5 option sets.
	Two things are normalised because they are not the engine's: the character of GNUstep's
	"%lc" in the unknown-escape warning (it prints the argument's garbage high byte, which varies
	from run to run) keeps only its low byte, and an exception is recorded by name only (its
	reason quotes a source line number and a C++ signature).

	Built and run by tools/check-string-expander.sh (it copies OOStringExpander.mm next to these
	stubs so that its quote-includes find them). Run with --print to see the lines.
*/

#import "Universe.h"
#import "PlayerEntity.h"
#import "ResourceManager.h"
#import "OOJavaScriptEngine.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOStringExpander.h"
#import "OOFoundationBridge.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"
#include <objc/objc-arc.h>
#include <objc/runtime.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static NSMutableArray *sLog;
static NSDictionary *sDescriptions;
static NSDictionary *sWhitelist;

// --- logging and JavaScript warnings ------------------------------------------------------

static NSString *MaskPercentLc(NSString *message)
{
	NSRange r = [message rangeOfString:@"Unknown escape code in string: %"];
	if (r.location == NSNotFound || NSMaxRange(r) >= [message length])  return message;
	unichar c = [message characterAtIndex:NSMaxRange(r)] & 0xFF;
	return [message stringByReplacingCharactersInRange:NSMakeRange(NSMaxRange(r), 1)
											withString:[NSString stringWithCharacters:&c length:1]];
}

BOOL OOLogWillDisplayMessagesInClass(NSString *cls) { return YES; }
void OOLogWithFunctionFileAndLineAndArguments(NSString *cls, const char *fn, const char *file, unsigned long line, NSString *fmt, va_list args)
{
	NSString *msg = [[[NSString alloc] initWithFormat:fmt arguments:args] autorelease];
	[sLog addObject:[NSString stringWithFormat:@"[%@] %s: %@", cls, fn ? fn : "(null)", MaskPercentLc(msg)]];
}
void OOLogWithFunctionFileAndLine(NSString *cls, const char *fn, const char *file, unsigned long line, NSString *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	OOLogWithFunctionFileAndLineAndArguments(cls, fn, file, line, fmt, args);
	va_end(args);
}
void OOLogWithPrefix(NSString *cls, const char *fn, const char *file, unsigned long line, NSString *prefix, NSString *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	OOLogWithFunctionFileAndLineAndArguments(cls, fn, file, line, [prefix stringByAppendingString:fmt], args);
	va_end(args);
}
void OOLogGenericParameterErrorForFunction(const char *fn) { [sLog addObject:[NSString stringWithFormat:@"parameter error %s", fn]]; }
void OOLogGenericSubclassResponsibilityForFunction(const char *fn) { [sLog addObject:@"subclass responsibility"]; }
// The expander logs through oo::log since bead oo-3rb.315: its finished lines ("[class] function:
// message", the format OOLogWithFunctionFileAndLineAndArguments above records) reach this sink
// (bead oo-qqz6: harness plumbing; installed in main()). A failed assertion (OOCAssert) now logs
// here too, in class "gnustep"; NSCAssert's NSLog went to stderr and was never recorded (and the
// line quotes the temporary copy's path), so it is left out, as it was.
static void HarnessLogSink(std::string_view line)
{
	if (line.starts_with("[gnustep] "))
	{
		fprintf(stderr, "%.*s\n", (int)line.size(), line.data());
		return;
	}
	[sLog addObject:MaskPercentLc(oo::NSStringFrom(std::string(line)))];
}
void OOLogIndent(void) {}
void OOLogOutdent(void) {}
void OOLogPushIndent(void) {}
void OOLogPopIndent(void) {}

JSContext *OOJSAcquireContext(void) { return nullptr; }
void OOJSRelinquishContext(JSContext *context) {}
void OOJSReportWarningWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString *msg = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
	[sLog addObject:[@"JS warning: " stringByAppendingString:MaskPercentLc(msg)]];
}
// The C++ form (printf format) the expander calls since bead oo-vp0y.10; the same record.
void cxx_OOJSReportWarningWithArguments(JSContext *context, const char *format, va_list args)
{
	NSString *msg = oo::NSStringFrom(oo::str::vformat(format, args));
	[sLog addObject:[@"JS warning: " stringByAppendingString:MaskPercentLc(msg)]];
}

NSString *OOHarnessCredits(OOCreditsQuantity tenths, BOOL decimal)
{
	return decimal ? [NSString stringWithFormat:@"%llu.%llu Cr", (unsigned long long)(tenths / 10), (unsigned long long)(tenths % 10)]
				   : [NSString stringWithFormat:@"%llu Cr", (unsigned long long)(tenths / 10)];
}

@implementation NSObject (OOHarnessDescription)
- (NSString *) shortDescription { return [NSString stringWithFormat:@"<%@>", [self class]]; }
@end

// --- lookups -------------------------------------------------------------------------------

@implementation NSArray (OOHarnessExtractors)
- (id) oo_objectAtIndex:(NSUInteger)i { return i < [self count] ? [self objectAtIndex:i] : nil; }
- (NSArray *) oo_arrayAtIndex:(NSUInteger)i { id o = [self oo_objectAtIndex:i]; return [o isKindOfClass:[NSArray class]] ? o : nil; }
- (NSString *) oo_stringAtIndex:(NSUInteger)i { id o = [self oo_objectAtIndex:i]; return [o isKindOfClass:[NSString class]] ? o : nil; }
@end

@implementation NSDictionary (OOHarnessExtractors)
- (NSArray *) oo_arrayForKey:(id)key { id o = [self objectForKey:key]; return [o isKindOfClass:[NSArray class]] ? o : nil; }
- (NSDictionary *) oo_dictionaryForKey:(id)key { id o = [self objectForKey:key]; return [o isKindOfClass:[NSDictionary class]] ? o : nil; }
- (NSString *) oo_stringForKey:(id)key { id o = [self objectForKey:key]; return [o isKindOfClass:[NSString class]] ? o : nil; }
@end

Random_Seed OOHarnessSystemManager::getRandomSeedForCurrentSystem() { Random_Seed s = {1, 2, 3, 4, 5, 6}; return s; }

// The C++ universe's members: the same data, converted once / per call, as the
// Objective-C stub's C++ forms answered.
const oo::PList *Universe::descriptions()
{
	static const oo::PList *descriptions = new oo::PList(oo::PListFrom(sDescriptions));
	return descriptions;
}
std::optional<std::string> Universe::getSystemName(OOSystemID sys)  { return oo::OptionalString([NSString stringWithFormat:@"Sys%d", (int)sys]); }
std::optional<std::string> Universe::getSystemName(OOSystemID sys, OOGalaxyID gal)  { return oo::OptionalString([NSString stringWithFormat:@"G%dSys%d", (int)gal, (int)sys]); }
OOHarnessSystemManager *Universe::getSystemManager()  { static OOHarnessSystemManager manager; return &manager; }
static Universe *sUniverse;
Universe *OOGetUniverse(void) { return sUniverse; }

// Every whitelisted legacy query method answers with its own name (and is logged, so a call
// the engine makes or skips shows). Queries are called by name (OOCallByName, ADR-0055 item 5),
// which reads an oo::PList result: the answer is the same text as a string PList, and the method
// is added with -harnessQueryTemplate's type encoding (bead oo-qqz6: stub-API tracking).
static oo::PList QueryIMP(id self, SEL _cmd)
{
	[sLog addObject:[NSString stringWithFormat:@"query %s", sel_getName(_cmd)]];
	return oo::PList(oo::StdString([NSString stringWithFormat:@"q(%s)", sel_getName(_cmd)]));
}

@implementation PlayerEntity
+ (BOOL) resolveInstanceMethod:(SEL)sel
{
	const char *name = sel_getName(sel);
	size_t n = strlen(name);
	if (n > 0 && name[n - 1] != ':')
	{
		Method templateMethod = class_getInstanceMethod(self, @selector(harnessQueryTemplate));
		class_addMethod(self, sel, reinterpret_cast<IMP>(reinterpret_cast<void (*)(void)>(&QueryIMP)), method_getTypeEncoding(templateMethod));
		return YES;
	}
	return [super resolveInstanceMethod:sel];
}
- (OOSystemID) systemID { return 7; }
- (NSString *) missionVariableForKey:(NSString *)key
{
	if ([key hasSuffix:@"_nil"])  return nil;
	return [@"mv:" stringByAppendingString:key];
}
- (NSString *) keyBindingDescription2:(NSString *)binding { return [@"kb:" stringByAppendingString:binding]; }
- (oo::PList) harnessQueryTemplate { return oo::PList(); }
- (oo::PList) commanderName_string { return oo::PList(oo::StdString(@"Jameson")); }
- (oo::PList) commanderShip_string { return oo::PList(oo::StdString(@"Cobra Mark III")); }
- (oo::PList) commanderShipDisplayName_string { return oo::PList(oo::StdString(@"Cobra \u00C9")); }
- (oo::PList) commanderRank_string { return oo::PList(oo::StdString(@"Harmless")); }
- (oo::PList) commanderKillsAsString { return oo::PList(oo::StdString(@"12")); }
- (oo::PList) commanderLegalStatus_string { return oo::PList(oo::StdString(@"Clean")); }
- (oo::PList) commanderBountyAsString { return oo::PList(oo::StdString(@"0")); }
- (oo::PList) creditsFormattedForSubstitution { return oo::PList(oo::StdString(@"1,234.5")); }
- (oo::PList) creditsFormattedForLegacySubstitution { return oo::PList(oo::StdString(@"1234.5")); }
// The C++ forms (bead oo-qqz6): the same answers; a nil mission variable is a null PList.
- (oo::PList) cxx_missionVariableForKey:(const std::string &)key
{
	NSString *value = [self missionVariableForKey:oo::NSStringFrom(key)];
	return value != nil ? oo::PList(oo::StdString(value)) : oo::PList();
}
- (std::optional<std::string>) cxx_keyBindingDescription2:(const std::string &)binding { return oo::OptionalString([self keyBindingDescription2:oo::NSStringFrom(binding)]); }
@end
static PlayerEntity *sPlayer;
PlayerEntity *OOGetPlayer(void) { return sPlayer; }

oo::PList ResourceManager::whitelistDictionary() { return oo::PListFrom(sWhitelist); }	// C++

// --- recording -----------------------------------------------------------------------------

static uint64_t sHash;
static BOOL sPrint;
static unsigned sLines;

static void HashLine(NSString *line)
{
	NSUInteger n = [line length];
	for (NSUInteger i = 0; i < n; i++)
	{
		unichar c = [line characterAtIndex:i];
		sHash = (sHash ^ (c & 0xFF)) * 1099511628211ULL;
		sHash = (sHash ^ (c >> 8)) * 1099511628211ULL;
	}
	sHash = (sHash ^ '\n') * 1099511628211ULL;
	sLines++;
	if (sPrint)  printf("%s\n", [line UTF8String]);
}

static NSString *Units(NSString *s)
{
	if (s == nil)  return @"nil";
	NSMutableString *out = [NSMutableString stringWithString:@"\""];
	for (NSUInteger i = 0; i < [s length]; i++)
	{
		unichar c = [s characterAtIndex:i];
		if (c >= 0x20 && c < 0x7F && c != '\\' && c != '"')  [out appendFormat:@"%c", (char)c];
		else  [out appendFormat:@"\\u%04X", (unsigned)c];
	}
	[out appendString:@"\""];
	return out;
}

static void Record(NSString *label, NSString *result)
{
	unsigned r1 = Ranrot();
	int r2 = gen_rnd_number();
	HashLine([NSString stringWithFormat:@"%@ => %@ | rng %u %d", label, Units(result), r1, r2]);
	for (NSString *line in sLog)  HashLine([@"    log " stringByAppendingString:Units(line)]);
	[sLog removeAllObjects];
}

static NSString *Expand(Random_Seed seed, NSString *string, NSString *systemName, OOExpandOptions options)
{
	NSDictionary *overrides = @{ @"self:name": @"Bob", @"num": @12.5, @"big": @"123456789012.25", @"pr": @"%R", @"arr": @[@"x"], @"neg": @"-3.75" };
	NSDictionary *locals = @{ @"local_x": @3, @"local_s": @"loc%H" };
	@try
	{
		return OOExpandDescriptionString(seed, string, overrides, locals, systemName, options);
	}
	@catch (OOException *e)
	{
		// The expander raises OOException since bead oo-3rb.5 (the same name text; bead oo-qqz6).
		[sLog addObject:[@"EXCEPTION " stringByAppendingString:[NSString stringWithUTF8String:[e name]]]];
	}
	@catch (NSException *e)
	{
		[sLog addObject:[@"EXCEPTION " stringByAppendingString:[e name]]];
	}
	return nil;
}

static const OOExpandOptions kOptionSets[] =
{
	kOOExpandNoOptions, kOOExpandGoodRNG, kOOExpandBackslashN | kOOExpandGoodRNG, kOOExpandForJavaScript, kOOExpandDisallowPercentI
};
enum { kOptionCount = sizeof kOptionSets / sizeof *kOptionSets };

// --- the generated expressions -------------------------------------------------------------

struct ExpressionCorpus
{
	uint64_t s;
	NSArray *keys;
	uint32_t next()
	{
		s ^= s << 13;
		s ^= s >> 7;
		s ^= s << 17;
		return (uint32_t)(s >> 32);
	}
	NSString *pick(NSArray *a) { return [a objectAtIndex:next() % [a count]]; }
	NSString *key()
	{
		static NSArray *special = [@[@"commander_name", @"commander_shipdisplayname", @"credits_number", @"_oo_legacy_credits_number",
			@"self:name", @"num", @"big", @"pr", @"neg", @"arr", @"local_x", @"local_s", @"mission_foo", @"mission_x_nil",
			@"oolite_key_x", @"oolite_key_", @"dockedStationName_string", @"foo_string", @"bar_number", @"baz_bool",
			@"unknownkey", @"system_description"] retain];
		NSString *k;
		switch (next() % 5)
		{
			case 0: case 1: k = pick(keys); break;
			case 2: case 3: k = pick(special); break;
			default: k = [NSString stringWithFormat:@"%u", next() % 41];
		}
		if (next() % 10 == 0)  k = [pick(@[@"\uFEFF", @"\uFFFE", @"\uFEFF\uFEFF"]) stringByAppendingString:k];
		return k;
	}
	NSString *expression()
	{
		static NSArray *ops = [@[@"cr", @"dcr", @"icr", @"idcr", @"precision", @"multiply", @"add", @"bogus", @"", @"c\u0301r"] retain];
		static NSArray *params = [@[@"1", @"-3", @"0", @"2.5", @"abc", @"12", @"1e3", @"", @" 7", @"3\u0301", @"-1", @"20", @"1e400"] retain];
		NSMutableString *s = [NSMutableString stringWithFormat:@"[%@", key()];
		static const unsigned kOpCounts[] = {0, 0, 1, 1, 2, 3};
		for (unsigned n = kOpCounts[next() % 6]; n > 0; n--)
		{
			[s appendFormat:@"|%@", pick(ops)];
			if (next() % 5 < 3)  [s appendFormat:@":%@", pick(params)];
			if (next() % 20 == 0)  [s appendString:@"\u0301"];
		}
		if (next() % 20 == 0)  [s appendString:@"|\u0301|cr"];
		[s appendString:@"]"];
		return s;
	}
	NSString *string()
	{
		static NSArray *literals = nil;
		if (literals == nil)
		{
			unichar lone = 0xD800;
			literals = [@[@"a", @"Hello ", @"x", @"  ", @"\n", @"\\n", @"\\", @"\x7F", @"\uFEFF", @"\uFFFE", @"\u0301",
				@"\u00E9", @"e\u0301", @"|", @":", @"%", @"%%", @"%[", @"%]", @"%H", @"%I", @"%N", @"%R", @"%R\u0301",
				@"%J007", @"%J256", @"%J07", @"%G123001", @"%G123009", @"%G12300", @"%@", @"%d", @"%.", @"%q", @"[",
				@"]", @"[]", @"[5]", @"[0]", @"[999]", @"[22]", @"9", @"0", @"\u0100", [NSString stringWithCharacters:&lone length:1],
				@"\uFEFF\uFEFFz"] retain];
		}
		NSMutableString *s = [NSMutableString string];
		for (unsigned n = 1 + next() % 8; n > 0; n--)
		{
			[s appendString:(next() % 20 < 9) ? expression() : pick(literals)];
		}
		return s;
	}
};

int main(int argc, char **argv)
{
	void *pool = objc_autoreleasePoolPush();
	if (argc < 3)
	{
		fprintf(stderr, "usage: %s descriptions.plist whitelist.plist [--print]\n", argv[0]);
		return 2;
	}
	sPrint = argc > 3 && strcmp(argv[3], "--print") == 0;
	sLog = [NSMutableArray new];
	// oo::log as the old stubs above behaved: every class shows, "[class] function: message".
	oo::log::logger().setSink(&HarnessLogSink);
	oo::log::logger().setInitialized(true);
	oo::log::logger().setOptions(oo::log::Options{ .showFunction = true, .showFileAndLine = false, .showClass = true, .showTime = false });
	sUniverse = new Universe();
	sPlayer = [PlayerEntity new];
	sDescriptions = [[NSDictionary dictionaryWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]] retain];
	sWhitelist = [[NSDictionary dictionaryWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]] retain];
	if (sDescriptions == nil || sWhitelist == nil)
	{
		fprintf(stderr, "test_string_expander: cannot read %s or %s\n", argv[1], argv[2]);
		return 2;
	}
	NSArray *keys = [[sDescriptions allKeys] sortedArrayUsingSelector:@selector(compare:)];

	// Every descriptions.plist key.
	sHash = 14695981039346656037ULL;
	for (unsigned s = 0; s < 16; s++)
	{
		Random_Seed seed = { (uint8_t)(0x4A + 17 * s), (uint8_t)(0x5A + 3 * s), (uint8_t)(0x48 ^ s), (uint8_t)(0x02 + s), (uint8_t)(0x53 + 29 * s), (uint8_t)(0xB7 - 11 * s) };
		for (NSString *key in keys)
		{
			for (unsigned o = 0; o < kOptionCount; o++)
			{
				void *inner = objc_autoreleasePoolPush();
				ranrot_srand(1000 + s * 7 + o);
				seed_for_planet_description(seed);
				NSString *r = Expand(seed, key, (o & 1) ? @"Zaonce" : nil, kOptionSets[o] | kOOExpandKey);
				Record([NSString stringWithFormat:@"seed %u key %@ opt %u", s, key, o], r);
				objc_autoreleasePoolPop(inner);
			}
		}
		void *inner = objc_autoreleasePoolPush();
		ranrot_srand(77 + s);
		Record(@"system description", OOGenerateSystemDescription(seed, @"Riedquat"));
		objc_autoreleasePoolPop(inner);
	}
	const uint64_t keysHash = sHash;
	const unsigned keysLines = sLines;

	// Generated expressions.
	sHash = 14695981039346656037ULL;
	sLines = 0;
	ExpressionCorpus corpus = { 0x61, keys };
	for (unsigned n = 0; n < 20000; n++)
	{
		void *inner = objc_autoreleasePoolPush();
		NSString *input = corpus.string();
		Random_Seed seed = { (uint8_t)n, (uint8_t)(n >> 8), 3, 4, 5, (uint8_t)(n * 7) };
		for (unsigned o = 0; o < kOptionCount; o++)
		{
			ranrot_srand(n * 5 + o);
			seed_for_planet_description(seed);
			NSString *r = Expand(seed, input, (o & 1) ? @"Zaonce" : nil, kOptionSets[o]);
			Record([NSString stringWithFormat:@"string %u opt %u", n, o], r);
		}
		objc_autoreleasePoolPop(inner);
	}
	const uint64_t stringsHash = sHash;

	// Regression (bead oo-3rb.69): a replacement of "\x7F" eats the character after it. At the end
	// of the (sub-)string there is none; the upstream engine then asserted in AppendCharacters
	// (start > end) and raised out of OOExpandDescriptionString. It now eats nothing there.
	int regressionFailures = 0;
	{
		void *inner = objc_autoreleasePoolPush();
		Random_Seed seed = { 1, 2, 3, 4, 5, 6 };
		NSDictionary *del = @{ @"del": @"\x7F" };
		NSString *const cases[][2] =
		{
			{ @"a[del]", @"a" },		// at the end: eats nothing (asserted before)
			{ @"ab[del]", @"ab" },		// at the end: eats nothing (asserted before)
			{ @"a[del]bc", @"ac" },		// in the middle: eats "b", as always
			{ @"[del]x", @"" },			// the whole string, as always
		};
		for (const auto &c : cases)
		{
			NSString *r = nil;
			@try
			{
				r = OOExpandDescriptionString(seed, c[0], del, nil, nil, kOOExpandNoOptions);
			}
			@catch (OOException *e)
			{
				fprintf(stderr, "test_string_expander: %s raised %s\n", [Units(c[0]) UTF8String], [e name]);
				regressionFailures++;
				continue;
			}
			@catch (NSException *e)
			{
				fprintf(stderr, "test_string_expander: %s raised %s\n", [Units(c[0]) UTF8String], [[e name] UTF8String]);
				regressionFailures++;
				continue;
			}
			if (![r isEqualToString:c[1]])
			{
				fprintf(stderr, "test_string_expander: %s gave %s, expected %s\n", [Units(c[0]) UTF8String], [Units(r) UTF8String], [Units(c[1]) UTF8String]);
				regressionFailures++;
			}
		}
		[sLog removeAllObjects];
		objc_autoreleasePoolPop(inner);
	}

	// Captured from the original OOStringExpander.mm (see the banner). Re-captured with Jon's
	// approval, 2026-09-29 (bead oo-qqz6; were 0xdaec14b5265fca36 / 0x07a1e83ff98956eb): every
	// expansion result and RNG draw is unchanged; only log text differs - 7845 lines name a
	// non-string value by its contents instead of its class (oo-qps.50), and 22 JS warnings end at
	// an embedded NUL, as the C string the JS engine receives always did (oo-kpxgo).
	// kStringsDigest re-captured with Jon's approval, 2026-09-29 (bead oo-3rb.69; was
	// 0xdc8ef7032bfb6797): the \x7F fix changes exactly the 12 records that raised before.
	// Both re-captured with Jon's approval, 2026-10-25 (were 0x6349f869900cf779 /
	// 0xef7448c0016ba2ed): upstream #747 changed descriptions.plist (key_oxzmanager_copyurl, the
	// OXZ-manager help strings, "Info URL:"); against the pre-sync plist the old digests still match.
	const uint64_t kKeysDigest = 0xea38daecff933503ULL, kStringsDigest = 0x338f336558c7db67ULL;
	int failures = regressionFailures;
	if (keysHash != kKeysDigest)
	{
		fprintf(stderr, "test_string_expander: descriptions.plist keys digest 0x%016llx, expected 0x%016llx (%u lines)\n", (unsigned long long)keysHash, (unsigned long long)kKeysDigest, keysLines);
		failures++;
	}
	if (stringsHash != kStringsDigest)
	{
		fprintf(stderr, "test_string_expander: generated strings digest 0x%016llx, expected 0x%016llx (%u lines)\n", (unsigned long long)stringsHash, (unsigned long long)kStringsDigest, sLines);
		failures++;
	}
	if (failures == 0)  fprintf(stderr, "test_string_expander: OK (%u + %u lines)\n", keysLines, sLines);
	objc_autoreleasePoolPop(pool);
	return failures == 0 ? 0 : 1;
}
