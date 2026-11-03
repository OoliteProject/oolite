/*

OOStringExpander+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-3il6, made by its chunk
oo-3rb.145; chunks oo-3rb.146..147 move nothing in). The Foundation-typed API OOStringExpander.h
declared before its sweep -- OOExpandDescriptionString, OOGenerateSystemDescription and the
OOExpand* macros with their argument-dictionary / boxing machinery -- verbatim, forwarding to
cxx_OOExpandDescriptionString / cxx_OOGenerateSystemDescription. It exists so that the callers
compile unchanged; each caller moves to the cxx_ forms in its own sweep bead. When `git grep`
finds no caller of anything declared here, the bridge bead deletes this file,
OOStringExpander+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
OOStringExpander.h. Never add to it; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (OOStringExpander.h)

*/

// Imported only from the end of OOStringExpander.h (which declares everything used here, and the
// OOEXPAND_ARGUMENT_COUNT / OOEXPAND_MAP machinery these macros use); never import it directly.
#ifndef OOSTRINGEXPANDER_FOUNDATIONBRIDGE_H
#define OOSTRINGEXPANDER_FOUNDATIONBRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

NSString* OOExpandDescriptionString(Random_Seed seed, NSString* string, NSDictionary* overrides, NSDictionary* legacyLocals, NSString* systemName, OOExpandOptions options);

#ifdef __cplusplus
}
#endif

NSString* OOGenerateSystemDescription(Random_Seed seed, NSString* name);

/**
        Expand a string with default options.
*/
#define OOExpand(string, ...) OOExpandWithSeed(OOStringExpanderDefaultRandomSeed(), string, __VA_ARGS__)

/**
        Expand a string as though it were surrounded by brackets;
        OOExpandKey(@"foo", ...) is equivalent to OOExpand(@"[foo]", ...).
*/
#define OOExpandKey(key, ...) OOExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), key, __VA_ARGS__)

/**
        Like OOExpandKey(), but uses a random-er random seed to avoid repeatability.
 */
#define OOExpandKeyRandomized(key, ...) OOExpandWithOptions(OOStringExpanderDefaultRandomSeed(), kOOExpandKey | kOOExpandGoodRNG | kOOExpandReseedRNG, key, __VA_ARGS__)

#define OOExpandWithSeed(seed, string, ...) OOExpandWithOptions(seed, kOOExpandNoOptions, string, __VA_ARGS__)

#define OOExpandKeyWithSeed(seed, key, ...) OOExpandWithOptions(seed, kOOExpandKey, key, __VA_ARGS__)

#define OOExpandWithOptions(seed, options, string, ...) \
    OOExpandDescriptionString(seed, string, OOEXPAND_ARG_DICTIONARY(__VA_ARGS__), nil, nil, options)

// MARK: Danger zone! Everything beyond this point is scary.

/*	Given an argument list, return a dictionary whose keys are the literal
        arguments and whose values are objects representing the arguments' values
        (as per OO_CAST_PARAMETER() below).

        Note that the argument list will be preprocessor-expanded at this point.
 */
#define OOEXPAND_ARG_DICTIONARY(...) (                                                                                              \
    (OOEXPAND_ARGUMENT_COUNT(__VA_ARGS__) == 0) ? nil : [NSDictionary dictionaryWithObjects:OOEXPAND_OBJECTS_FROM_ARGS(__VA_ARGS__) \
                                                                                    forKeys:OOEXPAND_NAMES_FROM_ARGS(__VA_ARGS__)   \
                                                                                      count:OOEXPAND_ARGUMENT_COUNT(__VA_ARGS__)])

#define OOEXPAND_NAME_FROM_ARG(ITEM) @ #ITEM
#define OOEXPAND_NAMES_FROM_ARGS(...) \
    (NSString*[]) { OOEXPAND_MAP(OOEXPAND_NAME_FROM_ARG, __VA_ARGS__) }

#define OOEXPAND_OBJECTS_FROM_ARGS(...) \
    (id[]) { OOEXPAND_MAP(OO_CAST_PARAMETER, __VA_ARGS__) }

/*	Limited boxing mechanism. ITEM may be an NSString *, NSNumber *, any
        integer type or any floating point type; the result is an NSNumber *,
        except if the parameter is an NSString * in which case it is returned
        unmodified.
 */
#ifdef __cplusplus
/*	Objective-C++ has neither __builtin_choose_expr nor __builtin_types_compatible_p,
        so the same classification is done by overload resolution: one overload per
        type the C branch below recognises, each forwarding to the helper that branch would pick.
        A type the C branch does not recognise has no overload here either.
*/
#define OO_CAST_PARAMETER(ITEM) OOCastParam(ITEM)
#else
#define OO_CAST_PARAMETER(ITEM)                             \
    __builtin_choose_expr(                                  \
        OOEXPAND_IS_OBJECT(ITEM),                           \
        OOCastParamObject,                                  \
        __builtin_choose_expr(                              \
            OOEXPAND_IS_SIGNED_INTEGER(ITEM),               \
            OOCastParamSignedInteger,                       \
            __builtin_choose_expr(                          \
                OOEXPAND_IS_UNSIGNED_INTEGER(ITEM),         \
                OOCastParamUnsignedInteger,                 \
                __builtin_choose_expr(                      \
                    OOEXPAND_IS_FLOAT(ITEM),                \
                    OOCastParamFloat,                       \
                    __builtin_choose_expr(                  \
                        OOEXPAND_IS_UNSIGNED_INTEGER(ITEM), \
                        OOCastParamUnsignedInteger,         \
                        __builtin_choose_expr(              \
                            OOEXPAND_IS_DOUBLE(ITEM),       \
                            OOCastParamDouble,              \
                            (void)0))))))(ITEM)

// Test whether ITEM is a known object type.
// NOTE: id works here in clang, but not gcc.
#define OOEXPAND_IS_OBJECT(ITEM) ( \
    __builtin_types_compatible_p(typeof(ITEM), NSString*) || __builtin_types_compatible_p(typeof(ITEM), NSNumber*))

// Test whether ITEM is a signed integer type.
// Some redundancy to avoid silliness across platforms; probably not necessary.
#define OOEXPAND_IS_SIGNED_INTEGER(ITEM) ( \
    __builtin_types_compatible_p(typeof(ITEM), char) || __builtin_types_compatible_p(typeof(ITEM), short) || __builtin_types_compatible_p(typeof(ITEM), int) || __builtin_types_compatible_p(typeof(ITEM), long) || __builtin_types_compatible_p(typeof(ITEM), long long) || __builtin_types_compatible_p(typeof(ITEM), NSInteger) || __builtin_types_compatible_p(typeof(ITEM), intptr_t) || __builtin_types_compatible_p(typeof(ITEM), ssize_t) || __builtin_types_compatible_p(typeof(ITEM), off_t))

// Test whether ITEM is an unsigned integer type.
// Some redundancy to avoid silliness across platforms; probably not necessary.
#define OOEXPAND_IS_UNSIGNED_INTEGER(ITEM) ( \
    __builtin_types_compatible_p(typeof(ITEM), unsigned char) || __builtin_types_compatible_p(typeof(ITEM), unsigned short) || __builtin_types_compatible_p(typeof(ITEM), unsigned int) || __builtin_types_compatible_p(typeof(ITEM), unsigned long) || __builtin_types_compatible_p(typeof(ITEM), unsigned long long) || __builtin_types_compatible_p(typeof(ITEM), NSUInteger) || __builtin_types_compatible_p(typeof(ITEM), uintptr_t) || __builtin_types_compatible_p(typeof(ITEM), size_t))

// Test whether ITEM is a float.
// This is distinguished from double to expose optimization opportunities.
#define OOEXPAND_IS_FLOAT(ITEM) ( \
    __builtin_types_compatible_p(typeof(ITEM), float))

// Test whether ITEM is any other floating-point type.
#define OOEXPAND_IS_DOUBLE(ITEM) ( \
    __builtin_types_compatible_p(typeof(ITEM), double) || __builtin_types_compatible_p(typeof(ITEM), long double))
#endif

// OO_CAST_PARAMETER() boils down to one of these.
static inline id OOCastParamObject(id object) { return object; }
static inline id OOCastParamSignedInteger(long long value) { return [NSNumber numberWithLongLong:value]; }
static inline id OOCastParamUnsignedInteger(unsigned long long value) { return [NSNumber numberWithUnsignedLongLong:value]; }
static inline id OOCastParamFloat(float value) { return [NSNumber numberWithFloat:value]; }
static inline id OOCastParamDouble(double value) { return [NSNumber numberWithDouble:value]; }

#ifdef __cplusplus
static inline id OOCastParam(NSString* value) { return OOCastParamObject(value); }
static inline id OOCastParam(NSNumber* value) { return OOCastParamObject(value); }
static inline id OOCastParam(char value) { return OOCastParamSignedInteger(value); }
static inline id OOCastParam(short value) { return OOCastParamSignedInteger(value); }
static inline id OOCastParam(int value) { return OOCastParamSignedInteger(value); }
static inline id OOCastParam(long value) { return OOCastParamSignedInteger(value); }
static inline id OOCastParam(long long value) { return OOCastParamSignedInteger(value); }
static inline id OOCastParam(unsigned char value) { return OOCastParamUnsignedInteger(value); }
static inline id OOCastParam(unsigned short value) { return OOCastParamUnsignedInteger(value); }
static inline id OOCastParam(unsigned int value) { return OOCastParamUnsignedInteger(value); }
static inline id OOCastParam(unsigned long value) { return OOCastParamUnsignedInteger(value); }
static inline id OOCastParam(unsigned long long value) { return OOCastParamUnsignedInteger(value); }
static inline id OOCastParam(float value) { return OOCastParamFloat(value); }
static inline id OOCastParam(double value) { return OOCastParamDouble(value); }
static inline id OOCastParam(long double value) { return OOCastParamDouble(value); }
#endif

#endif // OOSTRINGEXPANDER_FOUNDATIONBRIDGE_H
