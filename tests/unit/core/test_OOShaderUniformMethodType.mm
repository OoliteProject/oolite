/*	test_OOShaderUniformMethodType.mm
	Unit tests for src/Core/Materials/OOShaderUniformMethodType.h: bead oo-41vj.

	OOShaderUniformTypeFromMethod() tells a shader uniform binding the return type of the method it
	is bound to, by comparing the runtime's return-type encoding with a table of known ones. Its
	file held an Objective-C template class whose only use was to give that table. This pins,
	against a class of the test's own with one method per return type, the type each method is
	given (the ones the table has, and those it has not), NULL, and the two call helpers.
	Run: bash tools/check-core-tests.sh
*/

#import "OOShaderUniformMethodType.h"
#import "oofnd/objc/OOObject.h"
#import "OOOpenGLExtensionManager.h"
#include "oofnd/PList.hpp"

#include "oo_test.hpp"

#include <string>
#include <vector>


/*	OOMatrix.mm (the test's matrices) links the extension manager, whose collaborators are stubbed
	as in test_OOOpenGLExtensionManager; none of them runs here.
*/
@interface ResourceManager: OOObject
+ (std::vector<std::string>) cxx_paths;
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles;
@end

@implementation ResourceManager
+ (std::vector<std::string>) cxx_paths  { return {}; }
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles  { return oo::PList(oo::PList::Dict{}); }
@end


@interface OORegExpMatcher: OOObject
+ (instancetype) regExpMatcher;
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp;
@end

@implementation OORegExpMatcher
+ (instancetype) regExpMatcher  { return [[[self alloc] init] autorelease]; }
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp  { return NO; }
@end


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	return string == "SHADERS_FULL" ? SHADERS_FULL : SHADERS_NOT_SUPPORTED;
}


@interface TestReturns: OOObject
- (float)f;
- (double)d;
- (signed char)sc;
- (unsigned char)uc;
- (BOOL)b;
- (signed short)ss;
- (unsigned short)us;
- (signed int)si;
- (unsigned int)ui;
- (signed long)sl;
- (unsigned long)ul;
- (long long)sll;
- (unsigned long long)ull;
- (Vector)v;
- (HPVector)hpv;
- (Quaternion)q;
- (OOMatrix)m;
- (NSPoint)p;
- (id)o;
- (void)nothing;
- (NSRect)rect;
- (float)withArgument:(int)argument;
@end

@implementation TestReturns
- (float)f						{ return 1.5f; }
- (double)d						{ return 2.25; }
- (signed char)sc				{ return -3; }
- (unsigned char)uc				{ return 250; }
- (BOOL)b						{ return YES; }
- (signed short)ss				{ return -300; }
- (unsigned short)us			{ return 60000; }
- (signed int)si				{ return -70000; }
- (unsigned int)ui				{ return 4000000000U; }
- (signed long)sl				{ return -5; }
- (unsigned long)ul				{ return 6; }
- (long long)sll				{ return -8000000000LL; }
- (unsigned long long)ull		{ return 9000000000ULL; }
- (Vector)v						{ return make_vector(1, 2, 3); }
- (HPVector)hpv					{ return make_HPvector(1, 2, 3); }
- (Quaternion)q					{ return kIdentityQuaternion; }
- (OOMatrix)m					{ return kIdentityMatrix; }
- (NSPoint)p					{ return NSMakePoint(1, 2); }
- (id)o							{ return self; }
- (void)nothing					{}
- (NSRect)rect					{ NSRect r = {}; return r; }
- (float)withArgument:(int)argument	{ return (float)argument; }
@end


namespace {

OOShaderUniformType TypeOf(const char *selector)
{
	return OOShaderUniformTypeFromMethod(class_getInstanceMethod([TestReturns class], sel_registerName(selector)));
}


IMP ImpOf(const char *selector)
{
	return class_getMethodImplementation([TestReturns class], sel_registerName(selector));
}

}	// namespace


OO_TEST(typesFromMethods)
{
	OO_CHECK(TypeOf("f") == kOOShaderUniformTypeFloat);
	OO_CHECK(TypeOf("d") == kOOShaderUniformTypeDouble);
	OO_CHECK(TypeOf("sc") == kOOShaderUniformTypeChar);
	OO_CHECK(TypeOf("uc") == kOOShaderUniformTypeUnsignedChar);
	OO_CHECK(TypeOf("ss") == kOOShaderUniformTypeShort);
	OO_CHECK(TypeOf("us") == kOOShaderUniformTypeUnsignedShort);
	OO_CHECK(TypeOf("si") == kOOShaderUniformTypeInt);
	OO_CHECK(TypeOf("ui") == kOOShaderUniformTypeUnsignedInt);
	OO_CHECK(TypeOf("sl") == kOOShaderUniformTypeLong);
	OO_CHECK(TypeOf("ul") == kOOShaderUniformTypeUnsignedLong);
	OO_CHECK(TypeOf("v") == kOOShaderUniformTypeVector);
	OO_CHECK(TypeOf("hpv") == kOOShaderUniformTypeHPVector);
	OO_CHECK(TypeOf("q") == kOOShaderUniformTypeQuaternion);
	OO_CHECK(TypeOf("m") == kOOShaderUniformTypeMatrix);
	OO_CHECK(TypeOf("p") == kOOShaderUniformTypePoint);
	OO_CHECK(TypeOf("o") == kOOShaderUniformTypeObject);
	OO_CHECK(TypeOf("withArgument:") == kOOShaderUniformTypeFloat);	// arguments are not considered
}


OO_TEST(typesTheTableHasNot)
{
	// BOOL is encoded as a signed char here.
	OO_CHECK(TypeOf("b") == kOOShaderUniformTypeChar);
	// The table has no long long entries: on this platform (LLP64) a long is 32 bits, so a long
	// long matches nothing.
	OO_CHECK(TypeOf("sll") == kOOShaderUniformTypeInvalid);
	OO_CHECK(TypeOf("ull") == kOOShaderUniformTypeInvalid);
	OO_CHECK(TypeOf("nothing") == kOOShaderUniformTypeInvalid);
	OO_CHECK(TypeOf("rect") == kOOShaderUniformTypeInvalid);
	OO_CHECK(OOShaderUniformTypeFromMethod(NULL) == kOOShaderUniformTypeInvalid);
	OO_CHECK(TypeOf("noSuchMethod") == kOOShaderUniformTypeInvalid);
}


OO_TEST(callHelpers)
{
	@autoreleasepool
	{
		TestReturns *object = [[[TestReturns alloc] init] autorelease];
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("sc"), ImpOf("sc"), kOOShaderUniformTypeChar) == -3);
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("uc"), ImpOf("uc"), kOOShaderUniformTypeUnsignedChar) == 250);
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("ss"), ImpOf("ss"), kOOShaderUniformTypeShort) == -300);
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("us"), ImpOf("us"), kOOShaderUniformTypeUnsignedShort) == 60000);
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("si"), ImpOf("si"), kOOShaderUniformTypeInt) == -70000);
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("ui"), ImpOf("ui"), kOOShaderUniformTypeUnsignedInt) == 4000000000LL);
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("sl"), ImpOf("sl"), kOOShaderUniformTypeLong) == -5);
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("ul"), ImpOf("ul"), kOOShaderUniformTypeUnsignedLong) == 6);
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("sll"), ImpOf("sll"), kOOShaderUniformTypeLongLong) == -8000000000LL);
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("ull"), ImpOf("ull"), kOOShaderUniformTypeUnsignedLongLong) == 9000000000LL);
		OO_CHECK(OOCallIntegerMethod(object, sel_registerName("f"), ImpOf("f"), kOOShaderUniformTypeFloat) == 0);	// not an integer type
		OO_CHECK(OOCallFloatMethod(object, sel_registerName("f"), ImpOf("f"), kOOShaderUniformTypeFloat) == 1.5);
		OO_CHECK(OOCallFloatMethod(object, sel_registerName("d"), ImpOf("d"), kOOShaderUniformTypeDouble) == 2.25);
		OO_CHECK(OOCallFloatMethod(object, sel_registerName("si"), ImpOf("si"), kOOShaderUniformTypeInt) == 0);	// not a float type
	}
}

OO_TEST_MAIN()
