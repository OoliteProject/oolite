/*

ooscript/JSEngine.hpp

The JavaScript engine façade (Phase 1 seam 1.1, bead oo-e7c; ADR-0002, architecture §4 R1).

Oolite talks to its script engine through this header and nothing else. It is sized to what the
tree actually calls (the 2026-09-18 histogram over src/: 139 distinct JS_* functions, 3,828
sites; the top twenty are mapped in README.md beside this file), not to what any engine
offers. Behind it sits one backend: JSEngine_quickjs.cpp, the vendored QuickJS-ng (the patched
SpiderMonkey 1.8.5 backend it replaced was deleted by bead oo-7wx at Phase 1 item 5).
Retargeting a call site onto this façade must not change behaviour; that is what the goldens
verify, and it is why every function here keeps the calling convention of the JS_* function it
replaces (out-parameters, bool success, same argument order) rather than restyling it.

Rules of the header:
  * No engine type appears here. Handles are pointers to incomplete types the backend defines;
    Value and PropertyId are 8-byte PODs whose layout is the backend's (asserted there). That
    is what lets a file include this header without any engine header.
  * Hooks (property getters, class hooks, natives) are declared with façade types. The backend
    adapts them; a call site never writes an engine signature.
  * Nothing is inline that would need the engine's value layout. The build is thin-LTO, so the
    cost of an out-of-line predicate is an LTO decision, not a design one.
  * Consumers that are still Objective-C are compiled as Objective-C++ when they are retargeted
    (ADR-0001: the whole tree compiles as Objective-C++ during the bridge).

Engine function names in this file's comments are written without their JS_* prefix: the
deny-list (tools/deny-list.txt) forbids the prefixed spelling in any code file, comments
included, and this header is code. The full map from engine function to façade call, the
top-20 histogram and the list of what is deliberately not in the façade are in README.md
beside this file.

Copyright (C) 2026 the Oolite migration project. GPL-2.0-or-later, as the rest of Oolite.

*/

#pragma once

#include <cstddef>
#include <cstdint>

namespace ooscript {

// MARK: Handles ---------------------------------------------------------------------------------

// Opaque engine objects. Only the backend knows what they point at. A handle is a plain pointer,
// so it is copied, compared and null-tested like the engine pointer it replaces.
struct RuntimeRep;
struct ContextRep;
struct ObjectRep;
struct StringRep;
struct FunctionRep;

using Runtime  = RuntimeRep*;
using Context  = ContextRep*;
using Object   = ObjectRep*;
using String   = StringRep*;
using Function = FunctionRep*;

// A JS value: 64 bits, trivially copyable, passed by value exactly like the engine's own value
// type. Its bit layout belongs to the backend; read it only through the functions below.
struct Value
{
	std::uint64_t bits;
};

// A property key (an interned string, an integer index, or void). Same rules as Value.
struct PropertyId
{
	std::uint64_t bits;
};

// The engine's "16-bit code unit" string element. char16_t everywhere; the backend converts.
using Char16 = char16_t;

// MARK: Value construction and inspection ------------------------------------------------------

Value undefinedValue();
Value nullValue();
Value booleanValue(bool b);
Value trueValue();
Value falseValue();
Value int32Value(std::int32_t i);
Value numberValue(double d);            // engine: NewNumberValue without the always-true success flag
Value objectValue(Object obj);           // obj may be null: OBJECT_TO_JSVAL(NULL) is the null value
Value stringValue(String str);
Value privateValue(void* p);             // PRIVATE_TO_JSVAL

bool isUndefined(Value v);
bool isNull(Value v);
bool isNullOrUndefined(Value v);
bool isObjectOrNull(Value v);            // JSVAL_IS_OBJECT: true for null too; keep the old name's meaning
bool isObject(Value v);                  // a non-null object
bool isString(Value v);
bool isInt32(Value v);
bool isDouble(Value v);
bool isNumber(Value v);
bool isBoolean(Value v);
bool isPrimitive(Value v);

Object       toObject(Value v);          // JSVAL_TO_OBJECT; v must be an object or null
String       toString(Value v);          // JSVAL_TO_STRING; v must be a string
std::int32_t toInt32(Value v);           // JSVAL_TO_INT; v must be an int
double       toDouble(Value v);          // JSVAL_TO_DOUBLE; v must be a double
bool         toBoolean(Value v);         // JSVAL_TO_BOOLEAN; v must be a boolean
void*        toPrivate(Value v);         // JSVAL_TO_PRIVATE

// Conversions that follow the language's rules and may run script (getters, valueOf). They
// return false with an exception pending, exactly as the ValueTo* family does.
bool newNumberValue(Context cx, double d, Value* rval);          // engine: NewNumberValue
bool valueToNumber(Context cx, Value v, double* out);            // engine: ValueToNumber
bool valueToBoolean(Context cx, Value v, bool* out);             // engine: ValueToBoolean
bool valueToObject(Context cx, Value v, Object* out);            // engine: ValueToObject
bool valueToInt32(Context cx, Value v, std::int32_t* out);       // engine: ValueToInt32
bool valueToECMAInt32(Context cx, Value v, std::int32_t* out);   // engine: ValueToECMAInt32
bool valueToECMAUint32(Context cx, Value v, std::uint32_t* out); // engine: ValueToECMAUint32
String valueToString(Context cx, Value v);                       // engine: ValueToString; null on failure
Function valueToFunction(Context cx, Value v);                   // engine: ValueToFunction; null on failure
bool valueToId(Context cx, Value v, PropertyId* out);            // engine: ValueToId
bool idToValue(Context cx, PropertyId id, Value* out);           // engine: IdToValue

enum class Type : unsigned
{
	Void, Object, Function, String, Number, Boolean, Null, XML
};
Type typeOfValue(Context cx, Value v);   // engine: TypeOfValue
const char* typeName(Type t);            // engine: GetTypeName

// MARK: Property ids ----------------------------------------------------------------------------

PropertyId   int32Id(std::int32_t i);    // INT_TO_JSID
PropertyId   voidId();                   // JSID_VOID
bool         isInt32Id(PropertyId id);   // JSID_IS_INT
bool         isStringId(PropertyId id);  // JSID_IS_STRING
bool         isVoidId(PropertyId id);    // JSID_IS_VOID
std::int32_t idToInt32(PropertyId id);   // JSID_TO_INT; id must be an int
String       idToString(PropertyId id);  // JSID_TO_STRING; id must be a string
bool         idsEqual(PropertyId a, PropertyId b);

// MARK: Native functions ------------------------------------------------------------------------

// The argument block of a native call, as the engine passes it: callee, this, then argc
// arguments; the return value is written back into slot 0. Wraps the engine's ARGV / THIS /
// RVAL / SET_RVAL / CALLEE macros without copying anything.
class CallArgs
{
public:
	CallArgs(Context cx, unsigned argc, Value* vp) : cx_(cx), argc_(argc), vp_(vp) {}

	Context   context() const   { return cx_; }
	unsigned  count() const     { return argc_; }
	Value*    argv() const      { return vp_ + 2; }                 // engine: ARGV
	Value&    operator[](unsigned i) const { return vp_[2 + i]; }   // argv[i]; i < count()
	Value     callee() const    { return vp_[0]; }                  // engine: CALLEE
	Value     thisValue() const { return vp_[1]; }                  // engine: THIS
	Object    thisObject() const;                                   // engine: THIS_OBJECT (may run script)
	Value     rval() const      { return vp_[0]; }                  // engine: RVAL
	void      setRval(Value v) const { vp_[0] = v; }                // engine: SET_RVAL
	Value*    rawVp() const     { return vp_; }                     // for the few sites that keep vp
	bool      isConstructing() const;                               // engine: IsConstructing

private:
	Context   cx_;
	unsigned  argc_;
	Value*    vp_;
};

// A native function: return true with the result in args.setRval(), or false with an exception
// pending. The backend resolves which façade native a call reaches from the callee, so a native
// needs no engine-side identity.
using NativeFn = bool (*)(Context cx, CallArgs& args);

// MARK: Classes ---------------------------------------------------------------------------------

enum class PropertyFlag : std::uint8_t
{
	None       = 0,
	Enumerate  = 0x01,   // JSPROP_ENUMERATE
	ReadOnly   = 0x02,   // JSPROP_READONLY
	Permanent  = 0x04,   // JSPROP_PERMANENT
	Shared     = 0x40,   // JSPROP_SHARED: no value slot, the getter is the truth
};
constexpr PropertyFlag operator|(PropertyFlag a, PropertyFlag b) noexcept
{
	return static_cast<PropertyFlag>(static_cast<std::uint8_t>(a) | static_cast<std::uint8_t>(b));
}

// Property hooks. The id is the spec's tinyid as an int id when the property came from a
// PropertySpec table, and the property's name otherwise, exactly as the engine passes it.
using PropertyGetter = bool (*)(Context cx, Object obj, PropertyId id, Value* vp);
using PropertySetter = bool (*)(Context cx, Object obj, PropertyId id, bool strict, Value* vp);
using EnumerateHook  = bool (*)(Context cx, Object obj);
using ResolveHook    = bool (*)(Context cx, Object obj, PropertyId id);
using ConvertHook    = bool (*)(Context cx, Object obj, Type hint, Value* vp);
using FinalizeHook   = void (*)(Context cx, Object obj);

struct PropertySpec
{
	const char*     name;      // nullptr terminates a table
	std::int8_t     tinyid = 0;    // passed to getter/setter as int32Id(tinyid)
	PropertyFlag    flags = PropertyFlag{};
	PropertyGetter  getter = nullptr;    // nullptr = engine default
	PropertySetter  setter = nullptr;    // nullptr = engine default
};

struct FunctionSpec
{
	const char*     name;      // nullptr terminates a table
	NativeFn        call = nullptr;
	std::uint16_t   nargs = 0;
	std::uint16_t   flags = 0;     // PropertyFlag bits for the defined property
};

// The "new" enumerate protocol (JSCLASS_NEW_ENUMERATE): the engine drives an iterator through
// the hook instead of asking the hook to define every property up front.
enum class EnumerateOp : unsigned
{
	Init,      // JSENUMERATE_INIT: set *statep, optionally *idp = the count
	InitAll,   // JSENUMERATE_INIT_ALL: as Init, including non-enumerable properties
	Next,      // JSENUMERATE_NEXT: set *idp to the next id, or *statep to null when done
	Destroy,   // JSENUMERATE_DESTROY: free whatever *statep holds
};
using NewEnumerateHook = bool (*)(Context cx, Object obj, EnumerateOp op, Value* statep, PropertyId* idp);

enum class ClassFlag : std::uint32_t
{
	None         = 0,
	HasPrivate   = 1u << 0,   // JSCLASS_HAS_PRIVATE
	NewEnumerate = 1u << 1,   // JSCLASS_NEW_ENUMERATE: `newEnumerate` is used, `enumerate` ignored
	Global       = 1u << 2,   // JSCLASS_GLOBAL_FLAGS: the class of the global object
};
constexpr ClassFlag operator|(ClassFlag a, ClassFlag b) noexcept
{
	return static_cast<ClassFlag>(static_cast<std::uint32_t>(a) | static_cast<std::uint32_t>(b));
}

// A class definition. Every hook is optional: nullptr means the engine's stub, which is what
// engine: PropertyStub / EnumerateStub / ResolveStub / ConvertStub spelled out before.
// Define one per class as a static object with static storage duration; the backend attaches its
// engine-side class to it on first use through the `backend` slot and never copies it.
struct ClassDef
{
	const char*     name;
	ClassFlag       flags = ClassFlag{};
	PropertyGetter  addProperty = nullptr;
	PropertyGetter  delProperty = nullptr;
	PropertyGetter  getProperty = nullptr;
	PropertySetter  setProperty = nullptr;
	EnumerateHook   enumerate = nullptr;
	NewEnumerateHook newEnumerate = nullptr;   // used only with ClassFlag::NewEnumerate
	ResolveHook     resolve = nullptr;
	ConvertHook     convert = nullptr;
	FinalizeHook    finalize = nullptr;
	NativeFn        call = nullptr;        // the object is callable
	NativeFn        construct = nullptr;   // the object is a constructor
	void*           backend = nullptr;     // owned by the backend; initialise to nullptr
};

// MARK: Objects ---------------------------------------------------------------------------------

Object newObject(Context cx, ClassDef* def, Object proto, Object parent);              // engine: NewObject
Object newGlobalObject(Context cx, ClassDef* def);                                     // engine: NewCompartmentAndGlobalObject
void   setGlobalObject(Context cx, Object global);                                     // engine: SetGlobalObject
bool   initStandardClasses(Context cx, Object global);                                 // engine: InitStandardClasses
void   clearScope(Context cx, Object obj);                                             // engine: ClearScope
Object initClass(Context cx, Object obj, Object parentProto, ClassDef* def,            // engine: InitClass
                 NativeFn constructor, unsigned nargs,
                 const PropertySpec* ps, const FunctionSpec* fs,
                 const PropertySpec* staticPs, const FunctionSpec* staticFs);
Object defineObject(Context cx, Object obj, const char* name, ClassDef* def,           // engine: DefineObject
                    Object proto, PropertyFlag flags);
Object getConstructor(Context cx, Object proto);                                       // engine: GetConstructor
Object getPrototype(Context cx, Object obj);                                           // engine: GetPrototype
Object getParent(Context cx, Object obj);                                              // engine: GetParent
Object getGlobalObject(Context cx);                                                    // engine: GetGlobalObject
Object getGlobalForObject(Context cx, Object obj);                                     // engine: GetGlobalForObject

const ClassDef* getClass(Context cx, Object obj);        // engine: GetClass; nullptr if the class is not ours
const ClassDef* getObjectClass(Context cx, Object obj);  // engine: GetClass for any object: our classes as getClass,
                                                         // the engine's own (Object, Array, ...) a stable hook-less
                                                         // descriptor carrying their name (bead oo-1gc.3)
bool   instanceOf(Context cx, Object obj, ClassDef* def, Value* argv);                 // engine: InstanceOf
bool   setPrivate(Context cx, Object obj, void* data);                                 // engine: SetPrivate
void*  getPrivate(Context cx, Object obj);                                             // engine: GetPrivate
void*  getInstancePrivate(Context cx, Object obj, ClassDef* def, Value* argv);         // engine: GetInstancePrivate
bool   objectIsFunction(Context cx, Object obj);                                       // engine: ObjectIsFunction

// Properties by name (UTF-8/ASCII) and by id.
bool getProperty(Context cx, Object obj, const char* name, Value* vp);                 // engine: GetProperty
bool setProperty(Context cx, Object obj, const char* name, Value* vp);                 // engine: SetProperty
bool getPropertyById(Context cx, Object obj, PropertyId id, Value* vp);                // engine: GetPropertyById
bool setPropertyById(Context cx, Object obj, PropertyId id, Value* vp);                // engine: SetPropertyById
bool definePropertyById(Context cx, Object obj, PropertyId id, Value value,            // engine: DefinePropertyById
                        PropertyGetter getter, PropertySetter setter, PropertyFlag flags);
bool lookupProperty(Context cx, Object obj, const char* name, Value* vp);              // engine: LookupProperty
bool lookupPropertyById(Context cx, Object obj, PropertyId id, Value* vp);             // engine: LookupPropertyById
bool hasProperty(Context cx, Object obj, const char* name, bool* found);               // engine: HasProperty
bool deleteProperty(Context cx, Object obj, const char* name);                         // engine: DeleteProperty
bool getMethodById(Context cx, Object obj, PropertyId id, Object* objp, Value* vp);    // engine: GetMethodById
bool defineProperty(Context cx, Object obj, const char* name, Value value,             // engine: DefineProperty
                    PropertyGetter getter, PropertySetter setter, PropertyFlag flags);
bool defineProperties(Context cx, Object obj, const PropertySpec* ps);                 // engine: DefineProperties
Function defineFunction(Context cx, Object obj, const char* name, NativeFn call,       // engine: DefineFunction
                        unsigned nargs, PropertyFlag flags);
bool defineFunctions(Context cx, Object obj, const FunctionSpec* fs);                  // engine: DefineFunctions

// Elements and arrays.
bool   setElement(Context cx, Object obj, std::int32_t index, Value* vp);              // engine: SetElement
bool   getElement(Context cx, Object obj, std::int32_t index, Value* vp);              // engine: GetElement
bool   lookupElement(Context cx, Object obj, std::int32_t index, Value* vp);           // engine: LookupElement
Object newArrayObject(Context cx, std::int32_t length, Value* vector);                 // engine: NewArrayObject
bool   isArrayObject(Context cx, Object obj);                                          // engine: IsArrayObject
bool   getArrayLength(Context cx, Object obj, std::uint32_t* length);                  // engine: GetArrayLength
bool   setArrayLength(Context cx, Object obj, std::uint32_t length);                   // engine: SetArrayLength

// Enumeration: the ids of an object's own enumerable properties. Free it with destroyIdArray.
struct IdArray
{
	std::size_t length;
	PropertyId* ids;
	void*       backend;
};
IdArray* enumerate(Context cx, Object obj);                                            // engine: Enumerate
void     destroyIdArray(Context cx, IdArray* ida);                                     // engine: DestroyIdArray

// Functions.
String   getFunctionId(Function fn);                                                   // engine: GetFunctionId; null if anonymous
Object   getFunctionObject(Function fn);                                               // engine: GetFunctionObject
NativeFn getFunctionNative(Context cx, Function fn);                                   // engine: GetFunctionNative; nullptr unless ours
bool     callFunctionValue(Context cx, Object thisObj, Value fn,                       // engine: CallFunctionValue
                           unsigned argc, Value* argv, Value* rval);
bool     callFunctionName(Context cx, Object thisObj, const char* name,                // engine: CallFunctionName
                          unsigned argc, Value* argv, Value* rval);

// Script evaluation. `length` is in bytes for the narrow form and in code units for the wide one.
bool evaluateScript(Context cx, Object scope, const char* src, unsigned length,        // engine: EvaluateScript
                    const char* filename, unsigned lineno, Value* rval);
bool evaluateUCScript(Context cx, Object scope, const Char16* src, unsigned length,    // engine: EvaluateUCScript
                      const char* filename, unsigned lineno, Value* rval);

// MARK: Scripts -----------------------------------------------------------------------------

// A precompiled script (OOJSScript.m's compiled-script cache: LoadScriptWithName /
// CompiledScriptData / ScriptWithCompiledData). compileUCScript compiles source into one of
// these; newScriptObject wraps it in a garbage-collected JS object so it can be rooted the
// same way any other Object is; executeScript runs it once; destroyScript frees the compiled
// form after the run (OOJSScript.m destroys it right after executeScript -- the wrapper
// object, not the compiled script, is what keeps the event handlers it defined alive).
struct ScriptRep;
using Script = ScriptRep*;

Script compileUCScript(Context cx, Object scope, const Char16* src, unsigned length,   // engine: CompileUCScript
                       const char* filename, unsigned lineno);
Object newScriptObject(Context cx, Script script);                                     // engine: NewScriptObject
bool   executeScript(Context cx, Object obj, Script script, Value* rval);              // engine: ExecuteScript
void   destroyScript(Context cx, Script script);                                       // engine: DestroyScript

// The compiled-script cache's on-disk form (OOCacheManager's "compiled JavaScript scripts"
// cache, CompiledScriptData/ScriptWithCompiledData). serializeScript/deserializeScript move
// the engine's XDR call sites onto the façade; the byte layout stays the backend's own (see
// README.md's "Not in the façade" note) -- callers only ever move the bytes, never read them.
struct ByteBuffer
{
	std::uint8_t* data;
	std::size_t   length;
};
bool   serializeScript(Context cx, Script script, ByteBuffer* out);                     // engine: XDRNewMem(ENCODE)+XDRScript+XDRMemGetData+XDRDestroy
Script deserializeScript(Context cx, const std::uint8_t* data, std::size_t length);     // engine: XDRNewMem(DECODE)+XDRMemSetData+XDRScript+XDRDestroy
void   destroyByteBuffer(ByteBuffer* buf);                                              // frees serializeScript's output; safe on a zeroed buffer

// MARK: Strings ---------------------------------------------------------------------------------

String        internString(Context cx, const char* s);                                 // engine: InternString
String        internUCStringN(Context cx, const Char16* s, std::size_t n);             // engine: InternUCStringN
String        newStringCopyZ(Context cx, const char* s);                               // engine: NewStringCopyZ
String        newStringCopyN(Context cx, const char* s, std::size_t n);                // engine: NewStringCopyN
String        newUCStringCopyN(Context cx, const Char16* s, std::size_t n);            // engine: NewUCStringCopyN
Value         emptyStringValue(Context cx);                                            // engine: GetEmptyStringValue
std::size_t   getStringLength(String str);                                             // engine: GetStringLength
const Char16* getStringCharsAndLength(Context cx, String str, std::size_t* length);    // engine: GetStringCharsAndLength
const Char16* getInternedStringChars(String str);                                      // engine: GetInternedStringChars
bool          stringEqualsAscii(Context cx, String str, const char* ascii, bool* match); // engine: StringEqualsAscii
bool          stringHasBeenInterned(Context cx, String str);                           // engine: StringHasBeenInterned
void          setCStringsAreUTF8();                                                    // engine: SetCStringsAreUTF8

// MARK: Regular expressions -----------------------------------------------------------------

// engine: NewUCRegExpObjectNoStatics. Compiles a RegExp object from UTF-16 source without
// binding the engine's static RegExp.$1.. properties; OORegExpMatcher's cached-pattern path is
// the only caller. `flags` carries the engine's regexp flag bits (e.g. ignore-case, global)
// unchanged, exactly as the function it replaces.
Object newUCRegExpObjectNoStatics(Context cx, const Char16* chars, std::size_t length,
                                  std::uint32_t flags);

// MARK: Exceptions and error reporting --------------------------------------------------------

bool isExceptionPending(Context cx);                                                   // engine: IsExceptionPending
bool getPendingException(Context cx, Value* vp);                                       // engine: GetPendingException
void setPendingException(Context cx, Value v);                                         // engine: SetPendingException
void clearPendingException(Context cx);                                                // engine: ClearPendingException
bool reportPendingException(Context cx);                                               // engine: ReportPendingException

// Report an already-formatted message. (Oolite formats the text and passes "%s"; the
// printf-style variants are therefore not part of the façade.)
void reportError(Context cx, const char* message);                                     // engine: ReportError(cx, "%s", message)
bool reportWarning(Context cx, const char* message);                                   // engine: ReportWarning(cx, "%s", message)
void reportOutOfMemory(Context cx);                                                    // engine: ReportOutOfMemory

enum class ReportFlag : unsigned
{
	Error     = 0x0,
	Warning   = 0x1,   // JSREPORT_WARNING
	Exception = 0x2,   // JSREPORT_EXCEPTION
	Strict    = 0x4,   // JSREPORT_STRICT
};
struct ErrorReport
{
	const char*    filename;      // may be null
	unsigned       lineno;
	unsigned       flags;         // ReportFlag bits
	unsigned       errorNumber;   // engine's numeric error code; 0 if not applicable
	const Char16*  ucmessage;     // may be null
	const Char16*  linebuf;       // may be null
};
using ErrorReporter = void (*)(Context cx, const char* message, const ErrorReport* report);
ErrorReporter setErrorReporter(Context cx, ErrorReporter reporter);                    // engine: SetErrorReporter; returns the old one

// A save/restore of the pending exception around a call that must not disturb it.
struct ExceptionState;
ExceptionState* saveExceptionState(Context cx);                                        // engine: SaveExceptionState
void restoreExceptionState(Context cx, ExceptionState* state);                         // engine: RestoreExceptionState
void dropExceptionState(Context cx, ExceptionState* state);                            // engine: DropExceptionState

// MARK: GC roots --------------------------------------------------------------------------------

bool addNamedObjectRoot(Context cx, Object* rp, const char* name);                     // engine: AddNamedObjectRoot
bool addNamedValueRoot(Context cx, Value* vp, const char* name);                       // engine: AddNamedValueRoot
bool addNamedStringRoot(Context cx, String* sp, const char* name);                     // engine: AddNamedStringRoot
bool removeObjectRoot(Context cx, Object* rp);                                         // engine: RemoveObjectRoot
bool removeValueRoot(Context cx, Value* vp);                                           // engine: RemoveValueRoot
bool removeStringRoot(Context cx, String* sp);                                         // engine: RemoveStringRoot

// RAII forms for the common "root for the scope of this function" case.
class RootedObject
{
public:
	RootedObject(Context cx, Object obj, const char* name) : cx_(cx), obj_(obj) { addNamedObjectRoot(cx_, &obj_, name); }
	~RootedObject() { removeObjectRoot(cx_, &obj_); }
	RootedObject(const RootedObject&) = delete;
	RootedObject& operator=(const RootedObject&) = delete;
	Object  get() const { return obj_; }
	Object* address()   { return &obj_; }
	void    set(Object o) { obj_ = o; }
private:
	Context cx_;
	Object  obj_;
};

class RootedValue
{
public:
	RootedValue(Context cx, Value v, const char* name) : cx_(cx), v_(v) { addNamedValueRoot(cx_, &v_, name); }
	~RootedValue() { removeValueRoot(cx_, &v_); }
	RootedValue(const RootedValue&) = delete;
	RootedValue& operator=(const RootedValue&) = delete;
	Value  get() const { return v_; }
	Value* address()   { return &v_; }
	void   set(Value v) { v_ = v; }
private:
	Context cx_;
	Value   v_;
};

// MARK: Runtime, contexts, requests, GC ---------------------------------------------------------

Runtime newRuntime(std::uint32_t maxBytes);                                            // engine: NewRuntime
void    destroyRuntime(Runtime rt);                                                    // engine: DestroyRuntime
void    shutDown();                                                                    // engine: ShutDown
Context newContext(Runtime rt, std::size_t stackChunkSize);                            // engine: NewContext
void    destroyContext(Context cx);                                                    // engine: DestroyContext
Runtime getRuntime(Context cx);                                                        // engine: GetRuntime
void*   getContextPrivate(Context cx);                                                 // engine: GetContextPrivate
void    setContextPrivate(Context cx, void* data);                                     // engine: SetContextPrivate

// Requests bracket every use of a context from the outside world (the engine is built
// thread-safe). isInRequest is what the OOJS_NATIVE_ENTER assertions check.
void beginRequest(Context cx);                                                         // engine: BeginRequest
void endRequest(Context cx);                                                           // engine: EndRequest
bool isInRequest(Context cx);                                                          // engine: IsInRequest
bool isThreadsafeBuild();                                                              // engine build config: THREADSAFE
class Request
{
public:
	explicit Request(Context cx) : cx_(cx) { beginRequest(cx_); }
	~Request() { endRequest(cx_); }
	Request(const Request&) = delete;
	Request& operator=(const Request&) = delete;
private:
	Context cx_;
};

enum class ContextOption : std::uint32_t
{
	None        = 0,
	Strict      = 1u << 0,   // JSOPTION_STRICT
	VarObjFix   = 1u << 1,   // JSOPTION_VAROBJFIX
	RegExpLimit = 1u << 2,   // JSOPTION_RELIMIT
	AnonFunFix  = 1u << 3,   // JSOPTION_ANONFUNFIX
	Jit         = 1u << 4,   // JSOPTION_JIT (trace JIT)
	MethodJit   = 1u << 5,   // JSOPTION_METHODJIT
	Profiling   = 1u << 6,   // JSOPTION_PROFILING
};
constexpr ContextOption operator|(ContextOption a, ContextOption b)
{
	return static_cast<ContextOption>(static_cast<std::uint32_t>(a) | static_cast<std::uint32_t>(b));  // NOLINT(clang-analyzer-optin.core.EnumCastOutOfRange): this operator builds bitmask combinations of ContextOption flags; the analyzer treats the enum as a closed set of named values and flags any OR'd combination as "not a declared enumerator", which is a false positive for every legitimate multi-flag combination (see OOJavaScriptEngine.mm's OOJSENGINE_CONTEXT_OPTIONS).
}
ContextOption setOptions(Context cx, ContextOption options);                           // engine: SetOptions; returns the old set
ContextOption getOptions(Context cx);                                                  // engine: GetOptions

enum class Version : int
{
	Unknown = -1,
	Default = 0,
	ECMA5   = 185,   // JSVERSION_ECMA_5, the version Oolite runs
	Latest  = 1000,
};
Version     setVersion(Context cx, Version v);                                         // engine: SetVersion; returns the old one
Version     getVersion(Context cx);                                                    // engine: GetVersion
const char* versionToString(Version v);                                                // engine: VersionToString

// Garbage collection.
enum class GCParam : unsigned
{
	MaxBytes,        // JSGC_MAX_BYTES
	MaxMallocBytes,  // JSGC_MAX_MALLOC_BYTES
	Bytes,           // JSGC_BYTES
	NumberOfGCs,     // JSGC_NUMBER
};
std::uint32_t getGCParameter(Runtime rt, GCParam key);                                 // engine: GetGCParameter
void          setGCParameter(Runtime rt, GCParam key, std::uint32_t value);            // engine: SetGCParameter
void          gc(Context cx);                                                          // engine: GC
void          setGCZeal(Context cx, std::uint8_t zeal);                                // engine: SetGCZeal; debug builds only
bool          gcZealSupported();                                                       // engine build config: GC_ZEAL (whether setGCZeal is a real hook)
void          maybeGC(Context cx);                                                     // engine: MaybeGC

// The operation callback runs periodically during script execution (Oolite's time limiter).
// Return false to abort the running script.
using OperationCallback = bool (*)(Context cx);
OperationCallback setOperationCallback(Context cx, OperationCallback cb);              // engine: SetOperationCallback; returns the old one
void triggerOperationCallback(Context cx);                                             // engine: TriggerOperationCallback
void triggerAllOperationCallbacks(Runtime rt);                                         // engine: TriggerAllOperationCallbacks

// MARK: Completing the retarget (bead oo-1gc.3) -------------------------------------------------
//
// What the last game files needed that the histogram-sized first cut left out. Same rule as the
// rest of the header: each replaces one engine call and keeps its calling convention.

// Value and id identity is the engine's own: values and ids compared bitwise, and both backends keep
// one canonical bit pattern per value (int32 stays int32, one pointer per object).
inline bool operator==(Value a, Value b)           { return a.bits == b.bits; }
inline bool operator!=(Value a, Value b)           { return a.bits != b.bits; }
inline bool operator==(PropertyId a, PropertyId b) { return a.bits == b.bits; }
inline bool operator!=(PropertyId a, PropertyId b) { return a.bits != b.bits; }

// A request suspended around long native work (OOJS_BEGIN_FULL_NATIVE); the token restores it.
unsigned suspendRequest(Context cx);                                                   // engine: SuspendRequest
void     resumeRequest(Context cx, unsigned token);                                    // engine: ResumeRequest

bool compareStrings(Context cx, String a, String b, std::int32_t* result);             // engine: CompareStrings
bool freezeObject(Context cx, Object obj);                                             // engine: FreezeObject
Function compileUCFunction(Context cx, Object scope, const char* name,                 // engine: CompileUCFunction
                           unsigned nargs, const char** argnames,
                           const Char16* chars, std::size_t length,
                           const char* filename, unsigned lineno);
bool callFunction(Context cx, Object thisObj, Function fn,                             // engine: CallFunction
                  unsigned argc, Value* argv, Value* rval);
bool bufferIsCompilableUnit(Context cx, Object obj, const char* bytes, std::size_t length); // engine: BufferIsCompilableUnit

// newUCRegExpObjectNoStatics `flags`: the engine's regexp flag bits, spelled here.
constexpr std::uint32_t RegExpFoldCase  = 0x01;   // JSREG_FOLD: /i
constexpr std::uint32_t RegExpGlobal    = 0x02;   // JSREG_GLOB: /g
constexpr std::uint32_t RegExpMultiline = 0x04;   // JSREG_MULTILINE: /m
constexpr std::uint32_t RegExpSticky    = 0x08;   // JSREG_STICKY: /y

// MARK: Debugging and profiling (debug console, stack dumps, the JS profiler) -------------------
//
// Engine-specific by nature (README.md, "Not in the façade"): a backend may answer these with
// less than SpiderMonkey does (no frames, no variables, no hook) and the game degrades to the
// diagnostics it can get. Nothing here may be used for anything a golden can observe.

struct StackFrameRep;
using StackFrame = StackFrameRep*;

// Walk the running script's frames, innermost first: start with *iter == nullptr; returns the next
// frame (also stored in *iter) or nullptr when there are no more.
StackFrame frameIterator(Context cx, StackFrame* iter);                                // engine: FrameIterator
bool        frameIsScript(Context cx, StackFrame fp);                                  // engine: IsScriptFrame
bool        frameIsConstructor(Context cx, StackFrame fp);                             // engine: IsConstructorFrame
bool        frameIsDebugger(Context cx, StackFrame fp);                                // engine: IsDebuggerFrame
Script      frameScript(Context cx, StackFrame fp);                                    // engine: GetFrameScript; null for native frames
const char* scriptFilename(Context cx, Script script);                                 // engine: GetScriptFilename
unsigned    frameLineNumber(Context cx, StackFrame fp);                                // engine: PCToLineNumber(GetFrameScript, GetFramePC)
Function    frameFunction(Context cx, StackFrame fp);                                  // engine: GetFrameFunction
bool        frameThis(Context cx, StackFrame fp, Value* thisv);                        // engine: GetFrameThis
Object      frameScopeChain(Context cx, StackFrame fp);                                // engine: GetFrameScopeChain

// The variables visible in a scope object (engine: GetPropertyDescArray / PutPropertyDescArray).
enum class VariableFlag : unsigned
{
	None = 0, Enumerate = 0x01, ReadOnly = 0x02, Permanent = 0x04, Alias = 0x08,
	Argument = 0x10, Variable = 0x20, Exception = 0x40, Error = 0x80,
};
struct Variable
{
	PropertyId id;
	Value      value;
	unsigned   flags;      // VariableFlag bits
	Value      alias;      // meaningful with VariableFlag::Alias
};
struct VariableList
{
	std::size_t length;
	Variable*   vars;
	void*       backend;
};
bool getScopeVariables(Context cx, Object scope, VariableList* out);                  // false if unsupported
void destroyScopeVariables(Context cx, VariableList* list);

// The `debugger` statement (engine: SetDebuggerHandler). Execution always continues.
using DebuggerHandler = void (*)(Context cx, void* closure);
void setDebuggerHandler(Runtime rt, DebuggerHandler handler, void* closure);

// Function entry/exit, for the JS profiler (engine: SetFunctionCallback, MOZ_TRACE_JSCALLS builds).
using FunctionCallback = void (*)(Function fn, Script script, Context cx, int entering);
bool setFunctionCallback(Context cx, FunctionCallback cb);                             // false if unsupported

// Context creation/destruction (engine: SetContextCallback).
enum class ContextOp : unsigned { New = 0, Destroy = 1 };
using ContextCallback = bool (*)(Context cx, ContextOp op);
ContextCallback setContextCallback(Runtime rt, ContextCallback cb);                   // returns the old one

// Debug-console dumps (engine: DumpNamedRoots, DumpHeap; DEBUG engine builds only). `file` is a
// FILE*. Both return false when the backend cannot produce the dump.
enum class RootKind : unsigned { Value, GCThing };
using RootDumper = void (*)(const char* name, void* rp, RootKind kind, void* data);
bool dumpNamedRoots(Runtime rt, RootDumper dump, void* data);
bool dumpHeap(Context cx, void* file);

// MARK: Backend identity ------------------------------------------------------------------------

// Which engine is behind the façade in this build. Differential testing (Phase 1 item 4) keys on it.
const char* backendName();

} // namespace ooscript
