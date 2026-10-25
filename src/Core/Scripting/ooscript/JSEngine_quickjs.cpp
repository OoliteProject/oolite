/*

ooscript/JSEngine_quickjs.cpp

The QuickJS-ng backend of the façade in JSEngine.hpp (Phase 1 seams 1.4b/1.4c, beads oo-0kq and
oo-s0y; full surface: bead oo-1gc.2). Every function JSEngine.hpp declares is defined here, so the
game can link against this backend instead of JSEngine_spidermonkey.cpp. The SpiderMonkey backend
plus SpiderMonkey 1.8.5's own semantics are the behavioural spec; where QuickJS-ng cannot match
them the divergence is written down next to the code (grep "DIVERGENCE") and in the bead notes, so
Phase 1's differential triage knows what to expect.

Value representation
	ooscript::Value must stay an 8-byte POD, but QuickJS-ng's JSValue is 16 bytes on a 64-bit build.
	So Value uses its own NaN-boxing: genuine doubles are stored as their literal bit pattern (NaN is
	canonicalised to the positive quiet NaN), anything else uses the negative quiet-NaN space
	(0xFFF8...) with a 3-bit tag in bits 48-50 and a 48-bit payload:
	  0 private pointer (privateValue)    4 true
	  1 undefined                         5 int32
	  2 null                              6 object (JSObject*)
	  3 false                             7 string (JSString*) / symbol (pointer | 1)
	toJS() rebuilds a (borrowed) JSValue at the point of an engine call; fromJS()/take() go the
	other way. Strings handed to the façade are always flat: a rope is linearised first.

Value lifetime: the handle arena
	SpiderMonkey 1.8.5 scans the C stack conservatively, so Oolite holds bare Values/Objects in
	locals without rooting them and roots only heap-held ones (addNamed*Root). QuickJS-ng is
	refcounted. The emulation: every heap thing (object, string, symbol, atom) that crosses into a
	façade handle gets +1 reference recorded in a per-runtime arena. The arena is released only in
	gc()/maybeGC() (and when the runtime's last context is destroyed), and only when no façade code
	is running underneath the engine (no native/hook/finalizer frame active) and no context is more
	than one request deep. At that point the value currently stored at every registered root
	ADDRESS is re-referenced into the fresh arena first (roots are addresses read at flush time, as
	SpiderMonkey's root scanning reads them), then the old arena is freed, then the cycle collector
	runs. Values held inside JS objects are owned by QuickJS as usual.
	DIVERGENCE (deliberate, from the bead's "request depth 0"): the flush is allowed at request
	depth <= 1, because Oolite's only collection site (OOJavaScriptEngine
	-garbageCollectionOpportunity:) acquires the context, i.e. opens a request, around its gc() /
	maybeGC() call; at depth 0 the game would never reclaim anything. The hazard this admits is a
	caller that holds an unrooted Value across gc() inside its own single request.

Strings
	String handles point at the QuickJS JSString. getStringCharsAndLength/getInternedStringChars
	return a UTF-16 buffer cached per string in a side table that lives until the next arena flush
	(entries for rooted and interned strings survive the flush). internString/internUCStringN keep
	their string alive for the runtime's life, as SpiderMonkey keeps ATOM_INTERNED atoms.

Property ids
	int ids as before (bit 63 | int32); string ids are atoms (bit 62 | atom), symbol-keyed ids from
	enumeration are (bit 61 | atom); every atom id handed out is held by the arena.

Classes
	initClass creates a JSClassID per ClassDef (attach-on-first-use, registered per runtime), a
	prototype object of that class, and a native constructor. PropertySpec entries with a getter
	or setter -- or whose class has getProperty/setProperty hooks, Oolite's usual tinyid-dispatch
	pattern -- become accessor properties built from C closures that call the hook with
	int32Id(tinyid) and obj = the actual `this`; the rest are plain data properties. FunctionSpecs
	become native functions. Classes with any of the addProperty/delProperty/getProperty/
	setProperty/resolve/enumerate/newEnumerate hooks are "hooked": their instances get
	JSClassExoticMethods, and their plain data properties live in a per-object slot table (as in
	SpiderMonkey, where such properties carry the class hooks as their getter/setter) so that:
	  * getProperty runs on a get of an own slot property (with the slot value in *vp) and on a
	    get that misses everywhere (with undefined in *vp); a hit on the prototype chain is
	    returned as is.
	  * setProperty runs on a set of an own slot property and when a set adds one (after
	    addProperty), and the (possibly replaced) *vp is what gets stored.
	  * resolve runs on an own-lookup miss, re-entrancy guarded per (object, id), exactly where
	    SpiderMonkey's lookup would call it (including on hooked prototypes further down a chain).
	  * enumerate/newEnumerate feed get_own_property_names; delProperty runs on delete.
	Private data and the slot table share the object's opaque pointer (ObjRec).
	convert is mapped onto a Symbol.toPrimitive method on the class prototype; finalize onto the
	class finalizer; call/construct onto the class call hook.

Natives
	Native functions are objects of this backend's own callable class (the class call hook sees the
	constructor flag, which QuickJS-ng's C functions and closures do not). The trampoline builds
	Value vp[2 + max(argc, nargs)] (callee, this, args, undefined padding), wraps it in CallArgs and
	calls the NativeFn. Constructor calls create the new object (class and prototype from the
	constructor) and pass it as `this`, with isConstructing() true.

Scripts
	evaluate* and executeScript run top-level code with the scope object as `this`
	(JS_EvalThis2 with the filename and first line number). compileUCScript compiles to bytecode;
	executing against the global object runs that bytecode, executing against any other scope
	object re-evaluates the kept source with that `this` (QuickJS-ng can only run precompiled
	global code with the global object as `this`). serializeScript writes a small header (line,
	filename, source) plus the JS_WriteObject bytecode; deserializeScript reads it back.
	DIVERGENCE: SpiderMonkey puts the scope object at the head of the scope chain, so top-level
	`var`/function declarations become properties of the scope object and free identifiers resolve
	against it; QuickJS-ng has no scope-object parameter, so those land on / resolve against the
	global object. `this.foo = ...` (Oolite's script style) behaves identically.

Errors
	reportError while a script frame is active throws an Error(message) as the pending exception
	(SpiderMonkey converts reported errors to exceptions when a frame is running); with no script
	running it calls the ErrorReporter directly. reportPendingException builds an ErrorReport
	(filename/line from the error's own fileName/lineNumber or its stack) and calls the reporter.
	A failed top-level evaluate/execute/call/compile reports and clears the exception when a
	reporter is installed and no script is running, as SpiderMonkey's LAST_FRAME_CHECKS do.
	DIVERGENCE: with no reporter installed the exception stays pending (SpiderMonkey would clear it
	silently); the pre-existing unit test pins that. A native or hook returning false with nothing
	pending is SpiderMonkey's uncatchable abort; here it throws an uncatchable error which every
	façade boundary clears, so callers see "false, nothing pending" exactly as before.

Operation callback
	setOperationCallback/triggerOperationCallback use JS_SetInterruptHandler and an atomic flag per
	context; QuickJS-ng polls the handler every ~10k instructions, and a callback returning false
	aborts the script uncatchably.

Global object
	DIVERGENCE: QuickJS-ng contexts have a fixed global of a fixed class. newGlobalObject returns
	it and records the ClassDef, so getClass/getPrivate/setPrivate/instanceOf and defineProperties'
	default hooks (the tinyid getProperty/setProperty dispatch Oolite uses on the global) work;
	the global's own class hooks are not called for string-id misses or adds.

Copyright (C) 2026 the Oolite migration project. GPL-2.0-or-later, as the rest of Oolite.

*/

#define OO_PLAIN_CPP_UNIT 1	// a plain C++ unit: the shared headers' game-unit parts stay out of it (bead oo-dbz)
#include "JSEngine.hpp"

#include <quickjs.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace ooscript {

namespace {

static_assert(sizeof(Value) == 8, "ooscript::Value must stay 8 bytes");
static_assert(sizeof(Char16) == sizeof(std::uint16_t), "Char16 is a UTF-16 code unit");

// MARK: Handle conversions ----------------------------------------------------------------------

inline JSContext* CX(Context cx)       { return reinterpret_cast<JSContext*>(cx); }
inline Context    wrap(JSContext* cx)  { return reinterpret_cast<Context>(cx); }
inline JSRuntime* RT(Runtime rt)       { return reinterpret_cast<JSRuntime*>(rt); }
inline Runtime    wrap(JSRuntime* rt)  { return reinterpret_cast<Runtime>(rt); }
inline Object     objOf(JSValueConst v) { return static_cast<Object>(JS_VALUE_GET_PTR(v)); }
inline JSValue    OBJVAL(Object o)     { return JS_MKPTR(JS_TAG_OBJECT, o); }
inline JSValue    OBJVAL_OR_NULL(Object o) { return o != nullptr ? OBJVAL(o) : JS_NULL; }
inline JSValue    STRVAL(String s)     { return JS_MKPTR(JS_TAG_STRING, s); }
inline bool       sameObject(JSValueConst a, JSValueConst b)
{
	return JS_IsObject(a) && JS_IsObject(b) && JS_VALUE_GET_PTR(a) == JS_VALUE_GET_PTR(b);
}

// MARK: Value NaN-boxing -------------------------------------------------------------------------

constexpr std::uint64_t kQNanMask = 0xFFF8000000000000ULL;
constexpr std::uint64_t kPtrMask  = 0x0000FFFFFFFFFFFFULL;
constexpr std::uint64_t kCanonicalNaN = 0x7FF8000000000000ULL;
constexpr int kTagPrivate = 0, kTagUndefined = 1, kTagNull = 2, kTagFalse = 3, kTagTrue = 4,
              kTagInt32 = 5, kTagObject = 6, kTagHeapPrim = 7;
constexpr std::uint64_t kSymbolBit = 1;   // in a kTagHeapPrim payload: the pointer is a symbol

inline bool  isBoxed(Value v)  { return (v.bits & kQNanMask) == kQNanMask; }
inline int   tagOf(Value v)    { return static_cast<int>((v.bits >> 48) & 0x7); }
inline Value boxed(int tag, std::uint64_t payload)
{
	Value v;
	v.bits = kQNanMask | (static_cast<std::uint64_t>(tag) << 48) | (payload & kPtrMask);
	return v;
}
inline std::uint64_t payloadOf(Value v) { return v.bits & kPtrMask; }
inline void* ptrOf(std::uint64_t payload) { return reinterpret_cast<void*>(static_cast<std::uintptr_t>(payload)); }

// MARK: Property id encoding ---------------------------------------------------------------------

constexpr std::uint64_t kIdInt    = 1ULL << 63;
constexpr std::uint64_t kIdString = 1ULL << 62;
constexpr std::uint64_t kIdSymbol = 1ULL << 61;
// QuickJS-ng 0.16.2 encodes integer-index atoms (0 .. 2^31-2) inline with this tag bit
// (quickjs.c JS_ATOM_TAG_INT). The vendored version is pinned by the meson wrap.
constexpr JSAtom kAtomTagInt = 1u << 31;

inline JSAtom atomOfId(PropertyId id) { return static_cast<JSAtom>(id.bits & 0xFFFFFFFFu); }

} // namespace

// MARK: Value construction and inspection ------------------------------------------------------

Value undefinedValue()  { return boxed(kTagUndefined, 0); }
Value nullValue()       { return boxed(kTagNull, 0); }
Value trueValue()       { return boxed(kTagTrue, 0); }
Value falseValue()      { return boxed(kTagFalse, 0); }
Value booleanValue(bool b) { return b ? trueValue() : falseValue(); }
Value int32Value(std::int32_t i) { return boxed(kTagInt32, static_cast<std::uint32_t>(i)); }
Value objectValue(Object obj)    { return obj != nullptr ? boxed(kTagObject, reinterpret_cast<std::uintptr_t>(obj)) : nullValue(); }
Value stringValue(String str)    { return boxed(kTagHeapPrim, reinterpret_cast<std::uintptr_t>(str)); }
Value privateValue(void* p)      { return boxed(kTagPrivate, reinterpret_cast<std::uintptr_t>(p)); }

Value numberValue(double d)
{
	// JS_NewNumberValue's canonicalisation (store an int32 where exact, never for -0), plus NaN
	// canonicalisation so no double can ever alias the boxed space.
	if (std::isnan(d))
	{
		Value v;
		v.bits = kCanonicalNaN;
		return v;
	}
	if (d >= -2147483648.0 && d <= 2147483647.0)
	{
		const std::int32_t i = static_cast<std::int32_t>(d);
		if (static_cast<double>(i) == d && !(d == 0.0 && std::signbit(d)))  return int32Value(i);
	}
	Value v;
	std::memcpy(&v.bits, &d, sizeof v.bits);
	return v;
}

bool isUndefined(Value v)  { return isBoxed(v) && tagOf(v) == kTagUndefined; }
bool isNull(Value v)       { return isBoxed(v) && tagOf(v) == kTagNull; }
bool isNullOrUndefined(Value v) { return isNull(v) || isUndefined(v); }
bool isObjectOrNull(Value v) { return isBoxed(v) && (tagOf(v) == kTagObject || tagOf(v) == kTagNull); }
bool isObject(Value v)     { return isBoxed(v) && tagOf(v) == kTagObject && payloadOf(v) != 0; }
bool isBoolean(Value v)    { return isBoxed(v) && (tagOf(v) == kTagTrue || tagOf(v) == kTagFalse); }
bool isInt32(Value v)      { return isBoxed(v) && tagOf(v) == kTagInt32; }
bool isDouble(Value v)     { return !isBoxed(v); }
bool isNumber(Value v)     { return isInt32(v) || isDouble(v); }
bool isString(Value v)     { return isBoxed(v) && tagOf(v) == kTagHeapPrim && (payloadOf(v) & kSymbolBit) == 0; }
bool isPrimitive(Value v)  { return !isObject(v); }   // JSVAL_IS_PRIMITIVE: null is primitive

Object       toObject(Value v)  { return isObject(v) ? static_cast<Object>(ptrOf(payloadOf(v))) : nullptr; }
String       toString(Value v)  { return static_cast<String>(ptrOf(payloadOf(v) & ~kSymbolBit)); }
std::int32_t toInt32(Value v)   { return static_cast<std::int32_t>(v.bits & 0xFFFFFFFFu); }
double       toDouble(Value v)  { double d; std::memcpy(&d, &v.bits, sizeof d); return d; }
bool         toBoolean(Value v) { return tagOf(v) == kTagTrue; }
void*        toPrivate(Value v) { return ptrOf(payloadOf(v)); }

// MARK: Property ids ----------------------------------------------------------------------------

PropertyId   int32Id(std::int32_t i)  { PropertyId id; id.bits = kIdInt | static_cast<std::uint32_t>(i); return id; }
PropertyId   voidId()                 { PropertyId id; id.bits = 0; return id; }
bool         isInt32Id(PropertyId id) { return (id.bits & kIdInt) != 0; }
bool         isStringId(PropertyId id){ return (id.bits & kIdString) != 0; }
bool         isVoidId(PropertyId id)  { return id.bits == 0; }
std::int32_t idToInt32(PropertyId id) { return static_cast<std::int32_t>(id.bits & 0xFFFFFFFFu); }
bool         idsEqual(PropertyId a, PropertyId b) { return a.bits == b.bits; }

// MARK: Backend state ------------------------------------------------------------------------------

struct ExceptionState
{
	bool    hadException = false;
	JSValue value        = JS_UNDEFINED;
};

struct ScriptRep
{
	JSRuntime*  rt = nullptr;
	std::string source;     // UTF-8, NUL-terminated by std::string
	std::string filename;
	int         lineno = 1;
	JSValue     bytecode = JS_UNDEFINED;   // JS_TAG_FUNCTION_BYTECODE, owned
	int         refs = 1;                  // compile/deserialize + one per script object
};

namespace {

enum class RootSlot { Object, Value, String };

struct ContextState;

struct RuntimeState
{
	JSRuntime* rt = nullptr;
	std::vector<JSValue> arena;                 // one reference per value handed to the façade
	std::vector<JSAtom>  arenaAtoms;            // one reference per atom id handed to the façade
	std::unordered_map<void*, RootSlot> roots;  // root ADDRESSES, read at flush time
	std::unordered_set<void*> permanentStrings; // interned strings, one reference each, runtime lifetime
	std::unordered_set<void*> internedStrings;  // atom strings handed out this arena generation
	struct Chars { const std::uint16_t* p; std::size_t len; };
	std::unordered_map<void*, Chars> chars;     // JSString* -> UTF-16 view (holds a reference)
	std::vector<ContextState*> contexts;
	std::vector<std::pair<void*, JSAtom>> resolving;   // resolve re-entrancy guard
	int           nativeDepth = 0;              // façade code running under the engine
	int           shapeOnly = 0;                // >0: own lookups see only the engine's shape
	std::uint32_t gcCount = 0;
	std::uint32_t maxBytes = 0;
	std::uint32_t maxMallocBytes = 0;
};

struct ContextState
{
	JSContext*        ctx = nullptr;
	RuntimeState*     rs = nullptr;
	ErrorReporter     reporter = nullptr;
	OperationCallback opcb = nullptr;
	std::atomic<bool> triggered{false};
	int               requestDepth = 0;
	ContextOption     options = ContextOption::None;
	Version           version = Version::Default;
	ClassDef*         globalDef = nullptr;
	void*             globalPrivate = nullptr;
	JSValue           objectProto = JS_UNDEFINED;          // owned
	std::vector<JSValue> held;                              // owned for the context's lifetime
	std::unordered_map<void*, void*> ctorForProto;          // initClass without a constructor
};

// The process registries are immortal: allocated once and never destroyed (bead oo-9ht.173).
// libobjc drains a thread's open autorelease pools at thread detach, which on Windows runs after
// the CRT has destroyed namespace-scope objects; an autoreleased OOJSValue or script freed there
// still reaches them (beginRequest -> csOf, finalizers, roots). The same holds for every
// registry below that a finalizer or a façade call can reach.
std::unordered_map<JSContext*, ContextState*>& gContexts = *new std::unordered_map<JSContext*, ContextState*>;
std::unordered_map<JSRuntime*, JSContext*>&   gCtxForRuntime = *new std::unordered_map<JSRuntime*, JSContext*>;   // finalizers get only a JSRuntime*
JSContext*                                    gDefaultCtx = nullptr;   // for the ctx-less calls
ContextCallback                               gContextCallbackHook = nullptr;   // setContextCallback (bead oo-1gc.3)
std::vector<const Value*>&                    gConstructing = *new std::vector<const Value*>;   // vp blocks of constructor calls

JSClassID gNativeClassId = 0;
JSClassID gScriptClassId = 0;

// QuickJS-ng allocates class ids per runtime, but a ClassDef attaches once for the process and
// Oolite (and the unit test) can create more than one runtime. So this backend hands out its own
// process-wide ids, well above the engine's built-in classes, and registers them in each runtime.
JSClassID allocClassId()
{
	static JSClassID next = 512;
	return next++;
}

inline RuntimeState* rsOf(JSRuntime* rt) { return static_cast<RuntimeState*>(JS_GetRuntimeOpaque(rt)); }
inline RuntimeState* rsOf(JSContext* ctx) { return rsOf(JS_GetRuntime(ctx)); }
ContextState* csOf(JSContext* ctx)
{
	auto it = gContexts.find(ctx);
	return it == gContexts.end() ? nullptr : it->second;
}
inline JSContext* ctxOr(Context cx) { return cx != nullptr ? CX(cx) : gDefaultCtx; }

// Façade code is running underneath the engine (a native, hook or finalizer frame): arena
// flushing is unsafe while this is non-zero, because that frame's locals are unrooted handles.
struct NativeScope
{
	RuntimeState* rs;
	explicit NativeScope(RuntimeState* r) : rs(r) { if (rs != nullptr) ++rs->nativeDepth; }
	~NativeScope() { if (rs != nullptr) --rs->nativeDepth; }
	NativeScope(const NativeScope&) = delete;
	NativeScope& operator=(const NativeScope&) = delete;
};

// MARK: Engine <-> façade value translation --------------------------------------------------

JSValue toJS(Value v)
{
	if (!isBoxed(v))
	{
		double d; std::memcpy(&d, &v.bits, sizeof d);
		return JS_NewFloat64(nullptr, d);
	}
	switch (tagOf(v))
	{
		case kTagPrivate:   return JS_NewFloat64(nullptr, static_cast<double>(payloadOf(v)));
		case kTagUndefined: return JS_UNDEFINED;
		case kTagNull:      return JS_NULL;
		case kTagFalse:     return JS_FALSE;
		case kTagTrue:      return JS_TRUE;
		case kTagInt32:     return JS_MKVAL(JS_TAG_INT, toInt32(v));
		case kTagObject:    return payloadOf(v) != 0 ? JS_MKPTR(JS_TAG_OBJECT, ptrOf(payloadOf(v))) : JS_NULL;
		case kTagHeapPrim:
			if ((payloadOf(v) & kSymbolBit) != 0)  return JS_MKPTR(JS_TAG_SYMBOL, ptrOf(payloadOf(v) & ~kSymbolBit));
			return JS_MKPTR(JS_TAG_STRING, ptrOf(payloadOf(v)));
		default:            return JS_UNDEFINED;
	}
}

inline void holdOwned(JSContext* ctx, JSValue v)
{
	if (JS_VALUE_HAS_REF_COUNT(v))  rsOf(ctx)->arena.push_back(v);
}

// Consumes `v` (an owned reference): its reference moves into the arena.
Value take(JSContext* ctx, JSValue v)
{
	const int tag = JS_VALUE_GET_TAG(v);
	switch (tag)
	{
		case JS_TAG_UNDEFINED:  return undefinedValue();
		case JS_TAG_NULL:       return nullValue();
		case JS_TAG_BOOL:       return booleanValue(JS_VALUE_GET_BOOL(v) != 0);
		case JS_TAG_INT:        return int32Value(JS_VALUE_GET_INT(v));
		case JS_TAG_OBJECT:     holdOwned(ctx, v); return boxed(kTagObject, reinterpret_cast<std::uintptr_t>(JS_VALUE_GET_PTR(v)));
		case JS_TAG_STRING:     holdOwned(ctx, v); return boxed(kTagHeapPrim, reinterpret_cast<std::uintptr_t>(JS_VALUE_GET_PTR(v)));
		case JS_TAG_SYMBOL:     holdOwned(ctx, v); return boxed(kTagHeapPrim, reinterpret_cast<std::uintptr_t>(JS_VALUE_GET_PTR(v)) | kSymbolBit);
		case JS_TAG_STRING_ROPE:
		{
			JSValue flat = JS_ToString(ctx, v);   // linearise: a String handle is always a flat JSString
			JS_FreeValue(ctx, v);
			if (JS_IsException(flat))  return undefinedValue();
			return take(ctx, flat);
		}
		default:
			if (JS_TAG_IS_FLOAT64(tag))  return numberValue(JS_VALUE_GET_FLOAT64(v));
			JS_FreeValue(ctx, v);   // BigInt and engine-internal tags have no façade representation
			return undefinedValue();
	}
}

// Borrows `v`: the arena takes its own reference.
inline Value fromJS(JSContext* ctx, JSValueConst v) { return take(ctx, JS_DupValue(ctx, v)); }

Object takeObject(JSContext* ctx, JSValue v)
{
	if (!JS_IsObject(v))  { JS_FreeValue(ctx, v); return nullptr; }
	return toObject(take(ctx, v));
}

String takeString(JSContext* ctx, JSValue v)
{
	if (!JS_IsString(v))  { JS_FreeValue(ctx, v); return nullptr; }
	Value s = take(ctx, v);
	return isString(s) ? toString(s) : nullptr;
}

bool isSymbolAtom(JSContext* ctx, JSAtom atom)
{
	if ((atom & kAtomTagInt) != 0)  return false;
	JSValue v = JS_AtomToValue(ctx, atom);
	const bool sym = JS_IsSymbol(v);
	JS_FreeValue(ctx, v);
	return sym;
}

// An atom (borrowed) as a façade PropertyId; the arena takes a reference for string/symbol atoms.
PropertyId idFromAtom(JSContext* ctx, JSAtom atom)
{
	if ((atom & kAtomTagInt) != 0)  return int32Id(static_cast<std::int32_t>(atom & ~kAtomTagInt));
	PropertyId id;
	id.bits = (isSymbolAtom(ctx, atom) ? kIdSymbol : kIdString) | atom;
	rsOf(ctx)->arenaAtoms.push_back(JS_DupAtom(ctx, atom));
	return id;
}

// A façade PropertyId as a new atom reference (free it with JS_FreeAtom), JS_ATOM_NULL for void.
JSAtom atomFromId(JSContext* ctx, PropertyId id)
{
	if (isInt32Id(id))
	{
		const std::int32_t i = idToInt32(id);
		if (i >= 0)  return JS_NewAtomUInt32(ctx, static_cast<std::uint32_t>(i));
		const std::string s = std::to_string(i);
		return JS_NewAtomLen(ctx, s.c_str(), s.size());
	}
	if ((id.bits & (kIdString | kIdSymbol)) != 0)  return JS_DupAtom(ctx, atomOfId(id));
	return JS_ATOM_NULL;
}

// RAII for an owned atom.
struct AtomRef
{
	JSContext* ctx;
	JSAtom     atom;
	AtomRef(JSContext* c, JSAtom a) : ctx(c), atom(a) {}
	~AtomRef() { if (atom != JS_ATOM_NULL)  JS_FreeAtom(ctx, atom); }
	AtomRef(const AtomRef&) = delete;
	AtomRef& operator=(const AtomRef&) = delete;
};

// MARK: UTF-16 helpers ----------------------------------------------------------------------------

// UTF-16 -> UTF-8 (WTF-8 for unpaired surrogates, which QuickJS-ng's decoder passes through).
std::string toUtf8(const Char16* s, std::size_t n)
{
	std::string out;
	out.reserve(n);
	for (std::size_t i = 0; i < n; ++i)
	{
		std::uint32_t c = s[i];
		if (c >= 0xD800 && c <= 0xDBFF && i + 1 < n && s[i + 1] >= 0xDC00 && s[i + 1] <= 0xDFFF)
		{
			c = 0x10000 + ((c - 0xD800) << 10) + (static_cast<std::uint32_t>(s[i + 1]) - 0xDC00);
			++i;
		}
		if (c < 0x80)       out.push_back(static_cast<char>(c));
		else if (c < 0x800) { out.push_back(static_cast<char>(0xC0 | (c >> 6))); out.push_back(static_cast<char>(0x80 | (c & 0x3F))); }
		else if (c < 0x10000)
		{
			out.push_back(static_cast<char>(0xE0 | (c >> 12)));
			out.push_back(static_cast<char>(0x80 | ((c >> 6) & 0x3F)));
			out.push_back(static_cast<char>(0x80 | (c & 0x3F)));
		}
		else
		{
			out.push_back(static_cast<char>(0xF0 | (c >> 18)));
			out.push_back(static_cast<char>(0x80 | ((c >> 12) & 0x3F)));
			out.push_back(static_cast<char>(0x80 | ((c >> 6) & 0x3F)));
			out.push_back(static_cast<char>(0x80 | (c & 0x3F)));
		}
	}
	return out;
}

std::u16string toU16(JSContext* ctx, JSValueConst v)
{
	std::size_t len = 0;
	const std::uint16_t* p = JS_ToCStringLenUTF16(ctx, &len, v);
	if (p == nullptr)  { JS_FreeValue(ctx, JS_GetException(ctx)); return std::u16string(); }
	std::u16string out(reinterpret_cast<const char16_t*>(p), len);
	JS_FreeCStringUTF16(ctx, p);
	return out;
}

std::string toStdString(JSContext* ctx, JSValueConst v)
{
	std::size_t len = 0;
	const char* p = JS_ToCStringLen(ctx, &len, v);
	if (p == nullptr)  { JS_FreeValue(ctx, JS_GetException(ctx)); return std::string(); }
	std::string out(p, len);
	JS_FreeCString(ctx, p);
	return out;
}

std::u16string utf8ToU16(const char* s)
{
	std::u16string out;
	const auto* p = reinterpret_cast<const unsigned char*>(s);
	while (*p != 0)
	{
		std::uint32_t c = *p++;
		int extra = 0;
		if (c >= 0xF0)       { c &= 0x07; extra = 3; }
		else if (c >= 0xE0)  { c &= 0x0F; extra = 2; }
		else if (c >= 0xC0)  { c &= 0x1F; extra = 1; }
		for (; extra > 0 && (*p & 0xC0) == 0x80; --extra)  c = (c << 6) | (*p++ & 0x3F);
		if (c >= 0x10000)
		{
			c -= 0x10000;
			out.push_back(static_cast<char16_t>(0xD800 + (c >> 10)));
			out.push_back(static_cast<char16_t>(0xDC00 + (c & 0x3FF)));
		}
		else
		{
			out.push_back(static_cast<char16_t>(c));
		}
	}
	return out;
}

// The cached UTF-16 view of a flat string (see the file banner for its lifetime).
const Char16* stringChars(JSContext* ctx, String str, std::size_t* length)
{
	if (ctx == nullptr || str == nullptr)  { if (length != nullptr) *length = 0; return nullptr; }
	RuntimeState* rs = rsOf(ctx);
	auto it = rs->chars.find(str);
	if (it == rs->chars.end())
	{
		std::size_t len = 0;
		const std::uint16_t* p = JS_ToCStringLenUTF16(ctx, &len, STRVAL(str));
		if (p == nullptr)  { if (length != nullptr) *length = 0; return nullptr; }
		it = rs->chars.emplace(str, RuntimeState::Chars{p, len}).first;
	}
	if (length != nullptr)  *length = it->second.len;
	return reinterpret_cast<const Char16*>(it->second.p);
}

// MARK: The arena flush ---------------------------------------------------------------------------

void flushArena(RuntimeState* rs, bool rescanRoots)
{
	JSRuntime* rt = rs->rt;
	std::vector<JSValue> oldArena;
	std::vector<JSAtom>  oldAtoms;
	oldArena.swap(rs->arena);
	oldAtoms.swap(rs->arenaAtoms);

	// Re-reference whatever each root address holds NOW, into the fresh arena, before anything is
	// released: a value reachable only from a root must not dip to a zero refcount in between.
	std::unordered_set<void*> rootedStrings;
	if (rescanRoots)
	{
		for (const auto& root : rs->roots)
		{
			JSValue v = JS_UNDEFINED;
			switch (root.second)
			{
				case RootSlot::Object: { Object o = *static_cast<Object*>(root.first); if (o != nullptr) v = OBJVAL(o); break; }
				case RootSlot::Value:  v = toJS(*static_cast<Value*>(root.first)); break;
				case RootSlot::String: { String s = *static_cast<String*>(root.first); if (s != nullptr) v = STRVAL(s); break; }
			}
			if (!JS_VALUE_HAS_REF_COUNT(v))  continue;
			rs->arena.push_back(JS_DupValueRT(rt, v));
			if (JS_VALUE_GET_TAG(v) == JS_TAG_STRING)  rootedStrings.insert(JS_VALUE_GET_PTR(v));
		}
	}

	for (auto it = rs->chars.begin(); it != rs->chars.end();)
	{
		if (rs->permanentStrings.count(it->first) != 0 || rootedStrings.count(it->first) != 0)  { ++it; continue; }
		JS_FreeCStringRT_UTF16(rt, it->second.p);
		it = rs->chars.erase(it);
	}
	for (auto it = rs->internedStrings.begin(); it != rs->internedStrings.end();)
	{
		if (rootedStrings.count(*it) != 0)  ++it;
		else                                 it = rs->internedStrings.erase(it);
	}

	for (JSValue v : oldArena)  JS_FreeValueRT(rt, v);
	for (JSAtom a : oldAtoms)   JS_FreeAtomRT(rt, a);
}

bool canFlush(RuntimeState* rs)
{
	if (rs->nativeDepth != 0)  return false;
	for (const ContextState* cs : rs->contexts)
	{
		if (cs->requestDepth > 1)  return false;
	}
	return true;
}

// MARK: Errors, frames and the uncatchable abort ---------------------------------------------------

bool scriptRunning(JSContext* ctx)
{
	// A bytecode frame anywhere near the top of the stack means script is running. Native façade
	// functions push no frame of their own (they are class-call objects); the engine's own C
	// builtins do, which is why a few levels are probed.
	for (int level = 0; level < 16; ++level)
	{
		const JSAtom a = JS_GetScriptOrModuleName(ctx, level);
		if (a != JS_ATOM_NULL)  { JS_FreeAtom(ctx, a); return true; }
	}
	return false;
}

JSValue throwAbort(JSContext* ctx)
{
	JSValue e = JS_NewError(ctx);
	if (JS_IsException(e))  return JS_EXCEPTION;
	JS_DefinePropertyValueStr(ctx, e, "message", JS_NewString(ctx, "ooscript: script aborted"), JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE);
	JS_SetUncatchableError(ctx, e);
	return JS_Throw(ctx, e);
}

// A façade hook or native returned false: propagate its exception, or SpiderMonkey's uncatchable
// abort when it left none pending.
JSValue failValue(JSContext* ctx) { if (!JS_HasException(ctx))  throwAbort(ctx); return JS_EXCEPTION; }
int     failInt(JSContext* ctx)   { if (!JS_HasException(ctx))  throwAbort(ctx); return -1; }

bool parseLocation(const std::string& stack, std::string* file, unsigned* line)
{
	std::size_t pos = 0;
	while (pos < stack.size())
	{
		std::size_t end = stack.find('\n', pos);
		if (end == std::string::npos)  end = stack.size();
		std::string ln = stack.substr(pos, end - pos);
		pos = end + 1;
		const std::size_t at = ln.find("at ");
		if (at == std::string::npos)  continue;
		std::string s = ln.substr(at + 3);
		if (!s.empty() && s.back() == ')')
		{
			const std::size_t open = s.rfind('(');
			if (open == std::string::npos)  continue;
			s = s.substr(open + 1, s.size() - open - 2);
		}
		const std::size_t c2 = s.rfind(':');
		if (c2 == std::string::npos || c2 == 0)  continue;
		const std::size_t c1 = s.rfind(':', c2 - 1);
		if (c1 == std::string::npos)  continue;
		const std::string lineStr = s.substr(c1 + 1, c2 - c1 - 1);
		if (lineStr.empty() || lineStr.find_first_not_of("0123456789") != std::string::npos)  continue;
		*file = s.substr(0, c1);
		*line = static_cast<unsigned>(std::strtoul(lineStr.c_str(), nullptr, 10));
		return true;
	}
	return false;
}

// Filename/line of an error value: its own fileName/lineNumber if it has them (scripts that
// build SpiderMonkey-style errors), else the first located frame of its stack.
bool errorLocation(JSContext* ctx, JSValueConst err, std::string* file, unsigned* line)
{
	if (!JS_IsObject(err))  return false;
	ExceptionState saved;
	if (JS_HasException(ctx))  { saved.hadException = true; saved.value = JS_GetException(ctx); }
	bool found = false;
	JSValue fn = JS_GetPropertyStr(ctx, err, "fileName");
	JSValue ln = JS_GetPropertyStr(ctx, err, "lineNumber");
	if (JS_IsString(fn) && JS_IsNumber(ln))
	{
		*file = toStdString(ctx, fn);
		double d = 0;
		JS_ToFloat64(ctx, &d, ln);
		*line = d > 0 ? static_cast<unsigned>(d) : 0;
		found = true;
	}
	JS_FreeValue(ctx, fn);
	JS_FreeValue(ctx, ln);
	if (!found)
	{
		JSValue st = JS_GetPropertyStr(ctx, err, "stack");
		if (JS_IsString(st))  found = parseLocation(toStdString(ctx, st), file, line);
		JS_FreeValue(ctx, st);
	}
	if (JS_HasException(ctx))  JS_FreeValue(ctx, JS_GetException(ctx));
	if (saved.hadException)  JS_Throw(ctx, saved.value);
	return found;
}

bool currentLocation(JSContext* ctx, std::string* file, unsigned* line)
{
	if (!scriptRunning(ctx))  return false;
	JSValue e = JS_NewError(ctx);
	if (JS_IsException(e))  { JS_FreeValue(ctx, JS_GetException(ctx)); return false; }
	const bool ok = errorLocation(ctx, e, file, line);
	JS_FreeValue(ctx, e);
	return ok;
}

void invokeReporter(JSContext* ctx, const char* message, unsigned flags, const std::string* file,
                    unsigned line, const std::u16string* ucmessage, unsigned errorNumber = 0)
{
	ContextState* cs = csOf(ctx);
	if (cs == nullptr || cs->reporter == nullptr)  return;
	ErrorReport r{};
	r.filename    = (file != nullptr && !file->empty()) ? file->c_str() : nullptr;
	r.lineno      = line;
	r.flags       = flags;
	r.errorNumber = errorNumber;
	r.ucmessage   = ucmessage != nullptr ? ucmessage->c_str() : nullptr;
	r.linebuf     = nullptr;
	NativeScope scope(rsOf(ctx));
	cs->reporter(wrap(ctx), message, &r);
}

void throwErrorMessage(JSContext* ctx, const char* message)
{
	JSValue e = JS_NewError(ctx);
	if (JS_IsException(e))  return;
	JS_DefinePropertyValueStr(ctx, e, "message", JS_NewString(ctx, message), JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE);
	JS_Throw(ctx, e);
}

// SpiderMonkey's ReportError: an exception when a script frame is running, the reporter otherwise.
void reportErrorImpl(JSContext* ctx, const char* message)
{
	if (scriptRunning(ctx))
	{
		throwErrorMessage(ctx, message);
		return;
	}
	const std::u16string uc = utf8ToU16(message);
	invokeReporter(ctx, message, static_cast<unsigned>(ReportFlag::Error), nullptr, 0, &uc);
}

bool reportPendingImpl(JSContext* ctx);

// The end of a façade call that ran the engine: clear an uncatchable abort (SpiderMonkey returns
// false with nothing pending), and apply SpiderMonkey's LAST_FRAME_CHECKS: report and clear an
// uncaught exception when no script is running and a reporter is installed.
bool finish(JSContext* ctx, bool ok)
{
	if (ok)  return true;
	if (!JS_HasException(ctx))  return false;
	JSValue e = JS_GetException(ctx);
	if (JS_IsUncatchableError(e))  { JS_FreeValue(ctx, e); return false; }
	JS_Throw(ctx, e);
	ContextState* cs = csOf(ctx);
	if (cs != nullptr && cs->reporter != nullptr && !scriptRunning(ctx))  reportPendingImpl(ctx);
	return false;
}

bool reportPendingImpl(JSContext* ctx)
{
	if (!JS_HasException(ctx))  return false;
	JSValue exc = JS_GetException(ctx);
	if (JS_IsUncatchableError(exc))  { JS_FreeValue(ctx, exc); return false; }

	std::string message;
	std::u16string ucmessage;
	std::string file;
	unsigned line = 0;
	JSValue str = JS_ToString(ctx, exc);
	std::string text = JS_IsException(str) ? std::string("[exception]") : toStdString(ctx, str);
	if (JS_IsException(str))  JS_FreeValue(ctx, JS_GetException(ctx));
	else                      JS_FreeValue(ctx, str);
	if (JS_IsError(exc))
	{
		message = text;
		JSValue m = JS_GetPropertyStr(ctx, exc, "message");
		ucmessage = JS_IsString(m) ? toU16(ctx, m) : std::u16string();
		JS_FreeValue(ctx, m);
		if (JS_HasException(ctx))  JS_FreeValue(ctx, JS_GetException(ctx));
		errorLocation(ctx, exc, &file, &line);
	}
	else
	{
		message = "uncaught exception: " + text;
		ucmessage = utf8ToU16(message.c_str());
	}
	invokeReporter(ctx, message.c_str(), static_cast<unsigned>(ReportFlag::Exception), &file, line, &ucmessage);
	JS_FreeValue(ctx, exc);
	return true;
}

// MARK: Classes ---------------------------------------------------------------------------------------

struct Slot
{
	JSAtom  atom;
	JSValue value;
	bool    enumerable;
	bool    writable;
	bool    configurable;
};

// Every object of a façade class carries one of these as its opaque pointer.
struct ObjRec
{
	void*             priv = nullptr;
	std::vector<Slot> slots;   // plain data properties of hooked classes (see the banner)
	std::string       scopeFile;   // the script file this object is the scope of (registerScope)

	Slot* find(JSAtom atom)
	{
		for (Slot& s : slots)  if (s.atom == atom) return &s;
		return nullptr;
	}
};

struct BackendClass
{
	JSClassID              id = 0;
	ClassDef*              def = nullptr;
	bool                   hooked = false;
	JSClassExoticMethods   exotic{};
	JSClassDef             cdef{};
	std::vector<std::pair<std::string, std::int32_t>> tinyidProps;   // registerResolvableProperty
	std::vector<std::pair<void*, JSAtom>> enumerated;                // last newEnumerate listing
};

std::unordered_map<JSClassID, BackendClass*>& gClasses = *new std::unordered_map<JSClassID, BackendClass*>;

// Names an old-style enumerate hook defines while ExGetOwnPropertyNames runs it (bead oo-1gc.4):
// QuickJS-ng snapshots the shape's names before calling the exotic hook, so a name the hook adds
// would otherwise be missing from that enumeration.
struct DefineCollector { void* target; std::vector<JSAtom> atoms; };
DefineCollector* gDefineCollector = nullptr;

// SpiderMonkey's "shared permanent" rule (js_HasOwnProperty): a Shared|Permanent property found on
// a prototype of the SAME class as the object is reported as the object's own. That is why
// Object.keys(clock) lists clock's properties and hasOwnProperty("credits") is true for player.
// The PropertySpec accessors each class prototype carries are recorded here (atom, enumerable,
// read-only) so own-property queries and enumeration can report them the same way; property
// reads are unaffected. (bead oo-1gc.6)
struct SharedPermanent { JSAtom atom; bool enumerable; bool readOnly; };
std::unordered_map<void*, std::vector<SharedPermanent>>& gSharedPermanent = *new std::unordered_map<void*, std::vector<SharedPermanent>>;   // prototype -> entries (atoms owned)


BackendClass* classOf(JSValueConst obj)
{
	if (!JS_IsObject(obj))  return nullptr;
	auto it = gClasses.find(JS_GetClassID(obj));
	return it == gClasses.end() ? nullptr : it->second;
}

ObjRec* recOf(JSValueConst obj)
{
	BackendClass* bc = classOf(obj);
	return bc != nullptr ? static_cast<ObjRec*>(JS_GetOpaque(obj, bc->id)) : nullptr;
}

// The ClassDef whose hooks apply to `obj`: its own class, or the global's recorded ClassDef.
ClassDef* classDefOf(JSContext* ctx, JSValueConst obj)
{
	if (BackendClass* bc = classOf(obj))  return bc->def;
	ContextState* cs = csOf(ctx);
	if (cs != nullptr && cs->globalDef != nullptr)
	{
		JSValue g = JS_GetGlobalObject(ctx);
		const bool isGlobal = sameObject(g, obj);
		JS_FreeValue(ctx, g);
		if (isGlobal)  return cs->globalDef;
	}
	return nullptr;
}

bool resolvingNow(RuntimeState* rs, void* obj, JSAtom atom)
{
	return std::find(rs->resolving.begin(), rs->resolving.end(), std::make_pair(obj, atom)) != rs->resolving.end();
}

struct ResolveGuard
{
	RuntimeState* rs;
	ResolveGuard(RuntimeState* r, void* obj, JSAtom atom) : rs(r) { rs->resolving.emplace_back(obj, atom); }
	~ResolveGuard() { rs->resolving.pop_back(); }
	ResolveGuard(const ResolveGuard&) = delete;
	ResolveGuard& operator=(const ResolveGuard&) = delete;
};

bool tinyidForAtom(BackendClass* bc, JSContext* ctx, JSAtom atom, std::int32_t* out)
{
	if (bc->tinyidProps.empty())  return false;
	const char* name = JS_AtomToCString(ctx, atom);
	if (name == nullptr)  { JS_FreeValue(ctx, JS_GetException(ctx)); return false; }
	bool found = false;
	for (const auto& p : bc->tinyidProps)
	{
		if (p.first == name)  { *out = p.second; found = true; break; }
	}
	JS_FreeCString(ctx, name);
	return found;
}

void fillData(JSContext* ctx, JSPropertyDescriptor* desc, JSValueConst value, bool e, bool w, bool c)
{
	if (desc == nullptr)  return;
	desc->flags  = (e ? JS_PROP_ENUMERABLE : 0) | (w ? JS_PROP_WRITABLE : 0) | (c ? JS_PROP_CONFIGURABLE : 0);
	desc->value  = JS_DupValue(ctx, value);
	desc->getter = JS_UNDEFINED;
	desc->setter = JS_UNDEFINED;
}

void freeDesc(JSContext* ctx, JSPropertyDescriptor* d)
{
	JS_FreeValue(ctx, d->value);
	JS_FreeValue(ctx, d->getter);
	JS_FreeValue(ctx, d->setter);
}

// The engine's own lookup on the object's shape, with this backend's exotic part switched off.
int shapeLookup(JSContext* ctx, JSPropertyDescriptor* desc, JSValueConst obj, JSAtom atom)
{
	RuntimeState* rs = rsOf(ctx);
	++rs->shapeOnly;
	const int r = JS_GetOwnProperty(ctx, desc, obj, atom);
	--rs->shapeOnly;
	return r;
}

// The exotic half of an own lookup (the engine has already missed on the shape): the slot table,
// the test-only tinyid registry, then resolve, then the names the last newEnumerate listed.
// *fromShape is set when the answer is a shape property the resolve hook just defined.
int ownLookup(JSContext* ctx, JSPropertyDescriptor* desc, JSValueConst obj, JSAtom atom, bool* fromShape)
{
	*fromShape = false;
	RuntimeState* rs = rsOf(ctx);
	BackendClass* bc = classOf(obj);
	if (bc == nullptr || rs->shapeOnly != 0)  return 0;
	ObjRec* rec = recOf(obj);
	if (rec != nullptr)
	{
		if (Slot* s = rec->find(atom))  { fillData(ctx, desc, s->value, s->enumerable, s->writable, s->configurable); return 1; }
	}
	std::int32_t tinyid = 0;
	if (tinyidForAtom(bc, ctx, atom, &tinyid))
	{
		if (bc->def->resolve != nullptr)
		{
			NativeScope scope(rs);
			if (!bc->def->resolve(wrap(ctx), objOf(obj), int32Id(tinyid)))  return failInt(ctx);
		}
		fillData(ctx, desc, JS_UNDEFINED, true, true, true);
		return 1;
	}
	void* key = JS_VALUE_GET_PTR(obj);
	if (bc->def->resolve != nullptr && !resolvingNow(rs, key, atom) && !isSymbolAtom(ctx, atom))
	{
		{
			ResolveGuard guard(rs, key, atom);
			NativeScope scope(rs);
			if (!bc->def->resolve(wrap(ctx), objOf(obj), idFromAtom(ctx, atom)))  return failInt(ctx);
		}
		rec = recOf(obj);
		if (rec != nullptr)
		{
			if (Slot* s = rec->find(atom))  { fillData(ctx, desc, s->value, s->enumerable, s->writable, s->configurable); return 1; }
		}
		// The hook may have defined an accessor or function on the object's shape instead.
		const int r = shapeLookup(ctx, desc, obj, atom);
		if (r != 0)  { *fromShape = true; return r; }
	}
	for (const auto& e : bc->enumerated)
	{
		if (e.first == key && e.second == atom)  { fillData(ctx, desc, JS_UNDEFINED, true, true, true); return 1; }
	}
	return 0;
}

// The first Shared|Permanent entry for `atom` on a same-class prototype of `obj`, or nullptr.
const SharedPermanent* sharedPermanentFor(JSContext* ctx, JSValueConst obj, JSAtom atom)
{
	if (gSharedPermanent.empty())  return nullptr;
	const JSClassID cls = JS_GetClassID(obj);
	JSValue p = JS_GetPrototype(ctx, obj);
	const SharedPermanent* found = nullptr;
	while (found == nullptr && JS_IsObject(p) && JS_GetClassID(p) == cls)
	{
		auto it = gSharedPermanent.find(JS_VALUE_GET_PTR(p));
		if (it != gSharedPermanent.end())
		{
			for (const SharedPermanent& e : it->second)  if (e.atom == atom) { found = &e; break; }
		}
		JSValue next = JS_GetPrototype(ctx, p);
		JS_FreeValue(ctx, p);
		p = next;
	}
	JS_FreeValue(ctx, p);
	return found;
}

int ExGetOwnProperty(JSContext* ctx, JSPropertyDescriptor* desc, JSValueConst obj, JSAtom atom)
{
	bool fromShape = false;
	const int r = ownLookup(ctx, desc, obj, atom, &fromShape);
	if (r != 0 || rsOf(ctx)->shapeOnly != 0)  return r;   // a shape-only probe sees the shape alone
	const SharedPermanent* sp = sharedPermanentFor(ctx, obj, atom);
	if (sp == nullptr)  return 0;
	if (desc != nullptr)
	{
		JSValue v = JS_GetProperty(ctx, obj, atom);   // the class hook, as SpiderMonkey's lookup ran it
		if (JS_IsException(v))  return -1;
		desc->flags  = (sp->enumerable ? JS_PROP_ENUMERABLE : 0) | (sp->readOnly ? 0 : JS_PROP_WRITABLE);
		desc->value  = v;
		desc->getter = JS_UNDEFINED;
		desc->setter = JS_UNDEFINED;
	}
	return 1;
}

int ExGetOwnPropertyNames(JSContext* ctx, JSPropertyEnum** ptab, std::uint32_t* plen, JSValueConst obj)
{
	*ptab = nullptr;
	*plen = 0;
	BackendClass* bc = classOf(obj);
	if (bc == nullptr)  return 0;
	RuntimeState* rs = rsOf(ctx);
	void* key = JS_VALUE_GET_PTR(obj);
	std::vector<JSAtom> atoms;   // owned references
	std::vector<JSAtom> lateNames;   // owned: defined by an old-style enumerate hook just now
	auto addUnique = [&](JSAtom a) {
		if (std::find(atoms.begin(), atoms.end(), a) != atoms.end())  { JS_FreeAtom(ctx, a); return; }
		atoms.push_back(a);
	};

	const bool newEnum = (static_cast<std::uint32_t>(bc->def->flags) & static_cast<std::uint32_t>(ClassFlag::NewEnumerate)) != 0;
	if (newEnum && bc->def->newEnumerate != nullptr)
	{
		for (auto it = bc->enumerated.begin(); it != bc->enumerated.end();)
		{
			if (it->first == key)  { JS_FreeAtom(ctx, it->second); it = bc->enumerated.erase(it); }
			else                   ++it;
		}
		NativeScope scope(rs);
		Value state = undefinedValue();
		PropertyId id = voidId();
		if (!bc->def->newEnumerate(wrap(ctx), objOf(obj), EnumerateOp::Init, &state, &id))  return failInt(ctx);
		for (int guard = 0; !isNull(state) && guard < 1000000; ++guard)
		{
			id = voidId();
			if (!bc->def->newEnumerate(wrap(ctx), objOf(obj), EnumerateOp::Next, &state, &id))
			{
				for (JSAtom a : atoms)  JS_FreeAtom(ctx, a);
				return failInt(ctx);
			}
			if (isNull(state) || isVoidId(id))  break;
			const JSAtom a = atomFromId(ctx, id);
			if (a == JS_ATOM_NULL)  continue;
			bc->enumerated.emplace_back(key, JS_DupAtom(ctx, a));
			addUnique(a);
		}
	}
	else if (bc->def->enumerate != nullptr)
	{
		NativeScope scope(rs);
		DefineCollector collect{ key, {} };
		DefineCollector* outer = gDefineCollector;
		gDefineCollector = &collect;
		const bool ok = bc->def->enumerate(wrap(ctx), objOf(obj));
		gDefineCollector = outer;
		if (!ok)
		{
			for (JSAtom a : collect.atoms)  JS_FreeAtom(ctx, a);
			return failInt(ctx);
		}
		for (JSAtom a : collect.atoms)  lateNames.push_back(a);
	}
	for (const auto& p : bc->tinyidProps)  addUnique(JS_NewAtom(ctx, p.first.c_str()));
	{
		// Same-class prototypes' Shared|Permanent properties are the object's own (SpiderMonkey).
		const JSClassID cls = JS_GetClassID(obj);
		JSValue p = JS_GetPrototype(ctx, obj);
		while (JS_IsObject(p) && JS_GetClassID(p) == cls)
		{
			auto it = gSharedPermanent.find(JS_VALUE_GET_PTR(p));
			if (it != gSharedPermanent.end())
			{
				for (const SharedPermanent& e : it->second)  addUnique(JS_DupAtom(ctx, e.atom));
			}
			JSValue next = JS_GetPrototype(ctx, p);
			JS_FreeValue(ctx, p);
			p = next;
		}
		JS_FreeValue(ctx, p);
	}
	if (ObjRec* rec = recOf(obj))
	{
		for (const Slot& s : rec->slots)  addUnique(JS_DupAtom(ctx, s.atom));
	}
	// Names the engine already lists from the object's shape must not appear twice.
	for (auto it = atoms.begin(); it != atoms.end();)
	{
		const int r = shapeLookup(ctx, nullptr, obj, *it);
		if (r < 0)  JS_FreeValue(ctx, JS_GetException(ctx));
		if (r > 0)  { JS_FreeAtom(ctx, *it); it = atoms.erase(it); }
		else        ++it;
	}
	// ...except those the enumerate hook added during this call: the engine's own listing was
	// taken before the hook ran, so it does not have them.
	for (JSAtom a : lateNames)  addUnique(a);

	auto* tab = static_cast<JSPropertyEnum*>(js_mallocz(ctx, sizeof(JSPropertyEnum) * (atoms.empty() ? 1 : atoms.size())));
	if (tab == nullptr)  { for (JSAtom a : atoms) JS_FreeAtom(ctx, a); return -1; }
	for (std::size_t i = 0; i < atoms.size(); ++i)
	{
		tab[i].atom = atoms[i];
		const SharedPermanent* sp = sharedPermanentFor(ctx, obj, atoms[i]);
		tab[i].is_enumerable = sp == nullptr || sp->enumerable;
	}
	*ptab = tab;
	*plen = static_cast<std::uint32_t>(atoms.size());
	return 0;
}

int ExHasProperty(JSContext* ctx, JSValueConst obj, JSAtom atom)
{
	int r = JS_GetOwnProperty(ctx, nullptr, obj, atom);
	if (r != 0)  return r;
	JSValue proto = JS_GetPrototype(ctx, obj);
	if (JS_IsException(proto))  return -1;
	r = JS_IsObject(proto) ? JS_HasProperty(ctx, proto, atom) : 0;
	JS_FreeValue(ctx, proto);
	return r;
}

// Read a found descriptor as a value (calling its getter on `receiver`); consumes `d`.
JSValue valueOfDesc(JSContext* ctx, JSPropertyDescriptor* d, JSValueConst receiver)
{
	if (d->flags & JS_PROP_GETSET)
	{
		JSValue r = JS_IsFunction(ctx, d->getter) ? JS_Call(ctx, d->getter, receiver, 0, nullptr) : JS_UNDEFINED;
		freeDesc(ctx, d);
		return r;
	}
	JSValue v = d->value;
	JS_FreeValue(ctx, d->getter);
	JS_FreeValue(ctx, d->setter);
	return v;
}

JSValue ExGetProperty(JSContext* ctx, JSValueConst obj, JSAtom atom, JSValueConst receiver)
{
	BackendClass* bc = classOf(obj);
	const bool own = sameObject(obj, receiver);
	const bool symbol = isSymbolAtom(ctx, atom);
	bool found = false, hookEligible = false;
	JSValue val = JS_UNDEFINED;

	JSPropertyDescriptor d;
	bool fromShape = false;
	int r = ownLookup(ctx, &d, obj, atom, &fromShape);
	if (r < 0)  return JS_EXCEPTION;
	if (r > 0)
	{
		// An own slot (or a placeholder name from the registry/newEnumerate) carries the class
		// hooks; a shape property the resolve hook defined carries its own.
		found = true;
		hookEligible = !fromShape && (d.flags & JS_PROP_GETSET) == 0;
		val = valueOfDesc(ctx, &d, receiver);
		if (JS_IsException(val))  return val;
	}
	else
	{
		JSValue p = JS_GetPrototype(ctx, obj);
		while (JS_IsObject(p))
		{
			r = JS_GetOwnProperty(ctx, &d, p, atom);
			if (r < 0)  { JS_FreeValue(ctx, p); return JS_EXCEPTION; }
			if (r > 0)
			{
				found = true;
				val = valueOfDesc(ctx, &d, receiver);
				break;
			}
			JSValue next = JS_GetPrototype(ctx, p);
			JS_FreeValue(ctx, p);
			p = next;
		}
		JS_FreeValue(ctx, p);
		if (JS_IsException(val))  return val;
		hookEligible = !found;
	}

	if (bc != nullptr && own && hookEligible && !symbol && bc->def->getProperty != nullptr)
	{
		RuntimeState* rs = rsOf(ctx);
		NativeScope scope(rs);
		Value v = take(ctx, val);
		if (!bc->def->getProperty(wrap(ctx), objOf(obj), idFromAtom(ctx, atom), &v))  return failValue(ctx);
		return JS_DupValue(ctx, toJS(v));
	}
	return val;
}

int readOnlyFail(JSContext* ctx, int flags, JSAtom atom)
{
	if ((flags & JS_PROP_THROW) == 0)  return 0;
	const char* name = JS_AtomToCString(ctx, atom);
	JS_ThrowTypeError(ctx, "'%s' is read-only", name != nullptr ? name : "?");
	if (name != nullptr)  JS_FreeCString(ctx, name);
	return -1;
}

int callSetter(JSContext* ctx, JSPropertyDescriptor* d, JSValueConst receiver, JSValueConst val, int flags, JSAtom atom)
{
	int ret = 1;
	if (JS_IsFunction(ctx, d->setter))
	{
		JSValue r = JS_Call(ctx, d->setter, receiver, 1, &val);
		if (JS_IsException(r))  ret = -1;
		else                    JS_FreeValue(ctx, r);
	}
	else
	{
		ret = readOnlyFail(ctx, flags, atom);
	}
	freeDesc(ctx, d);
	return ret;
}

int setSlot(JSContext* ctx, BackendClass* bc, JSValueConst obj, Slot* s, JSAtom atom, JSValueConst val, int flags, bool symbol)
{
	if (!s->writable)  return readOnlyFail(ctx, flags, atom);
	Value v = fromJS(ctx, val);
	if (!symbol && bc->def->setProperty != nullptr)
	{
		NativeScope scope(rsOf(ctx));
		if (!bc->def->setProperty(wrap(ctx), objOf(obj), idFromAtom(ctx, atom), false, &v))  return failInt(ctx);
	}
	ObjRec* rec = recOf(obj);
	Slot* again = rec != nullptr ? rec->find(atom) : nullptr;   // the hook may have deleted it
	if (again == nullptr)  return 1;
	JSValue old = again->value;
	again->value = JS_DupValue(ctx, toJS(v));
	JS_FreeValue(ctx, old);
	return 1;
}

int addSlot(JSContext* ctx, BackendClass* bc, JSValueConst obj, JSAtom atom, Value v, bool e, bool w, bool c, bool symbol)
{
	if (!symbol)
	{
		NativeScope scope(rsOf(ctx));
		if (bc->def->addProperty != nullptr && !bc->def->addProperty(wrap(ctx), objOf(obj), idFromAtom(ctx, atom), &v))  return failInt(ctx);
	}
	ObjRec* rec = recOf(obj);
	if (rec == nullptr)  return 0;
	if (Slot* s = rec->find(atom))
	{
		JSValue old = s->value;
		s->value = JS_DupValue(ctx, toJS(v));
		JS_FreeValue(ctx, old);
		return 1;
	}
	rec->slots.push_back(Slot{JS_DupAtom(ctx, atom), JS_DupValue(ctx, toJS(v)), e, w, c});
	return 1;
}

int ExSetProperty(JSContext* ctx, JSValueConst obj, JSAtom atom, JSValueConst val, JSValueConst receiver, int flags)
{
	BackendClass* bc = classOf(obj);
	if (bc == nullptr)  return 0;
	const bool own = sameObject(obj, receiver);
	const bool symbol = isSymbolAtom(ctx, atom);
	ObjRec* rec = recOf(obj);
	if (own && rec != nullptr)
	{
		if (Slot* s = rec->find(atom))  return setSlot(ctx, bc, obj, s, atom, val, flags, symbol);
	}

	JSPropertyDescriptor d;
	// The object's own properties proper: the shared-permanent emulation in ExGetOwnProperty only
	// changes how prototype properties are REPORTED; an assignment still reaches the prototype's
	// setter, as it did under SpiderMonkey.
	bool fromShape = false;
	int r = ownLookup(ctx, &d, obj, atom, &fromShape);
	if (r < 0)  return -1;
	if (r > 0)
	{
		rec = recOf(obj);
		if (Slot* s = (own && rec != nullptr) ? rec->find(atom) : nullptr)
		{
			freeDesc(ctx, &d);
			return setSlot(ctx, bc, obj, s, atom, val, flags, symbol);
		}
		if (d.flags & JS_PROP_GETSET)  return callSetter(ctx, &d, receiver, val, flags, atom);
		const bool writable = (d.flags & JS_PROP_WRITABLE) != 0;
		freeDesc(ctx, &d);
		if (!writable)  return readOnlyFail(ctx, flags, atom);
		// A data property the resolve hook put on the shape keeps its own attributes. Anything else
		// here is a name the hooks only REPORT (the last newEnumerate listing, the tinyid registry):
		// the object does not have it, so SpiderMonkey's assignment added it -- addProperty, then
		// the class's setProperty, then a slot -- which is the path below. Defining it on the shape
		// instead skipped the setter and left a read-only, permanent shadow (bead oo-f1yi3).
		if (own && fromShape)  return JS_DefineProperty(ctx, obj, atom, val, JS_UNDEFINED, JS_UNDEFINED, JS_PROP_HAS_VALUE | JS_PROP_NO_EXOTIC);
	}
	else
	{
		JSValue p = JS_GetPrototype(ctx, obj);
		while (JS_IsObject(p))
		{
			r = JS_GetOwnProperty(ctx, &d, p, atom);
			if (r < 0)  { JS_FreeValue(ctx, p); return -1; }
			if (r > 0)
			{
				JS_FreeValue(ctx, p);
				if (d.flags & JS_PROP_GETSET)  return callSetter(ctx, &d, receiver, val, flags, atom);
				const bool writable = (d.flags & JS_PROP_WRITABLE) != 0;
				freeDesc(ctx, &d);
				if (!writable)  return readOnlyFail(ctx, flags, atom);
				p = JS_NULL;
				break;
			}
			JSValue next = JS_GetPrototype(ctx, p);
			JS_FreeValue(ctx, p);
			p = next;
		}
		JS_FreeValue(ctx, p);
	}

	// Add a new property to the receiver.
	if (own && recOf(obj) != nullptr)
	{
		Value v = fromJS(ctx, val);
		if (!symbol)
		{
			NativeScope scope(rsOf(ctx));
			if (bc->def->addProperty != nullptr && !bc->def->addProperty(wrap(ctx), objOf(obj), idFromAtom(ctx, atom), &v))  return failInt(ctx);
			if (bc->def->setProperty != nullptr && !bc->def->setProperty(wrap(ctx), objOf(obj), idFromAtom(ctx, atom), false, &v))  return failInt(ctx);
		}
		ObjRec* rec2 = recOf(obj);
		if (Slot* s = rec2->find(atom))
		{
			JSValue old = s->value;
			s->value = JS_DupValue(ctx, toJS(v));
			JS_FreeValue(ctx, old);
			return 1;
		}
		rec2->slots.push_back(Slot{JS_DupAtom(ctx, atom), JS_DupValue(ctx, toJS(v)), true, true, true});
		return 1;
	}
	if (!JS_IsObject(receiver))  return readOnlyFail(ctx, flags, atom);
	return JS_DefinePropertyValue(ctx, receiver, atom, JS_DupValue(ctx, val), JS_PROP_C_W_E);
}

int ExDefineOwnProperty(JSContext* ctx, JSValueConst obj, JSAtom atom, JSValueConst val,
                        JSValueConst getter, JSValueConst setter, int flags)
{
	BackendClass* bc = classOf(obj);
	ObjRec* rec = recOf(obj);
	Slot* s = rec != nullptr ? rec->find(atom) : nullptr;
	if (bc == nullptr || rec == nullptr || (flags & (JS_PROP_HAS_GET | JS_PROP_HAS_SET)) != 0)
	{
		if (s != nullptr)
		{
			if (!s->configurable)  return (flags & JS_PROP_THROW) ? (JS_ThrowTypeError(ctx, "property is not configurable"), -1) : 0;
			JS_FreeAtom(ctx, s->atom);
			JS_FreeValue(ctx, s->value);
			rec->slots.erase(rec->slots.begin() + (s - rec->slots.data()));
		}
		return JS_DefineProperty(ctx, obj, atom, val, getter, setter, flags | JS_PROP_NO_EXOTIC);
	}
	if (s != nullptr)
	{
		if (!s->configurable)
		{
			const bool widen = ((flags & JS_PROP_HAS_CONFIGURABLE) && (flags & JS_PROP_CONFIGURABLE)) ||
			                   ((flags & JS_PROP_HAS_ENUMERABLE) && ((flags & JS_PROP_ENUMERABLE) != 0) != s->enumerable) ||
			                   ((flags & JS_PROP_HAS_VALUE) && !s->writable && !JS_IsStrictEqual(ctx, val, s->value));
			if (widen)  return (flags & JS_PROP_THROW) ? (JS_ThrowTypeError(ctx, "property is not configurable"), -1) : 0;
		}
		if (flags & JS_PROP_HAS_VALUE)
		{
			JSValue old = s->value;
			s->value = JS_DupValue(ctx, val);
			JS_FreeValue(ctx, old);
		}
		if (flags & JS_PROP_HAS_WRITABLE)      s->writable     = (flags & JS_PROP_WRITABLE) != 0;
		if (flags & JS_PROP_HAS_ENUMERABLE)    s->enumerable   = (flags & JS_PROP_ENUMERABLE) != 0;
		if (flags & JS_PROP_HAS_CONFIGURABLE)  s->configurable = (flags & JS_PROP_CONFIGURABLE) != 0;
		return 1;
	}
	const Value v = (flags & JS_PROP_HAS_VALUE) ? fromJS(ctx, val) : undefinedValue();
	return addSlot(ctx, bc, obj, atom, v,
	               (flags & JS_PROP_HAS_ENUMERABLE) && (flags & JS_PROP_ENUMERABLE),
	               (flags & JS_PROP_HAS_WRITABLE) && (flags & JS_PROP_WRITABLE),
	               (flags & JS_PROP_HAS_CONFIGURABLE) && (flags & JS_PROP_CONFIGURABLE),
	               isSymbolAtom(ctx, atom));
}

int ExDeleteProperty(JSContext* ctx, JSValueConst obj, JSAtom atom)
{
	BackendClass* bc = classOf(obj);
	ObjRec* rec = recOf(obj);
	Slot* s = rec != nullptr ? rec->find(atom) : nullptr;
	if (bc == nullptr || s == nullptr)  return 1;
	if (!s->configurable)  return 0;
	if (bc->def->delProperty != nullptr && !isSymbolAtom(ctx, atom))
	{
		Value v = fromJS(ctx, s->value);
		NativeScope scope(rsOf(ctx));
		if (!bc->def->delProperty(wrap(ctx), objOf(obj), idFromAtom(ctx, atom), &v))  return failInt(ctx);
		s = rec->find(atom);
		if (s == nullptr)  return 1;
	}
	JS_FreeAtom(ctx, s->atom);
	JS_FreeValue(ctx, s->value);
	rec->slots.erase(rec->slots.begin() + (s - rec->slots.data()));
	return 1;
}

JSContext* finalizeContext(JSRuntime* rt)
{
	auto it = gCtxForRuntime.find(rt);
	return it != gCtxForRuntime.end() ? it->second : nullptr;
}

void FinalizeTramp(JSRuntime* rt, JSValueConst val)
{
	BackendClass* bc = classOf(val);
	if (bc == nullptr)  return;
	if (bc->def->finalize != nullptr)
	{
		// gCtxForRuntime holds the last live context for this runtime; destroyContext() erases it
		// (bead oo-902s), so a finalizer running after its context went away sees a null Context
		// rather than a dangling one.
		NativeScope scope(rsOf(rt));
		bc->def->finalize(wrap(finalizeContext(rt)), objOf(val));
	}
	auto* rec = static_cast<ObjRec*>(JS_GetOpaque(val, bc->id));
	if (rec != nullptr)
	{
		for (Slot& s : rec->slots)
		{
			JS_FreeValueRT(rt, s.value);
			JS_FreeAtomRT(rt, s.atom);
		}
		delete rec;
		JS_SetOpaque(val, nullptr);
	}
	for (auto it = bc->enumerated.begin(); it != bc->enumerated.end();)
	{
		if (it->first == JS_VALUE_GET_PTR(val))  { JS_FreeAtomRT(rt, it->second); it = bc->enumerated.erase(it); }
		else                                     ++it;
	}
}

void MarkTramp(JSRuntime* rt, JSValueConst val, JS_MarkFunc* markFunc)
{
	BackendClass* bc = classOf(val);
	if (bc == nullptr)  return;
	auto* rec = static_cast<ObjRec*>(JS_GetOpaque(val, bc->id));
	if (rec == nullptr)  return;
	for (const Slot& s : rec->slots)  JS_MarkValue(rt, s.value, markFunc);
}

JSValue runNative(JSContext* ctx, NativeFn fn, JSValueConst func, JSValueConst thisVal, int argc,
                  JSValueConst* argv, bool constructing, ClassDef* ctorClass, unsigned nargs);

JSValue ClassCallTramp(JSContext* ctx, JSValueConst func, JSValueConst thisVal, int argc, JSValueConst* argv, int flags)
{
	BackendClass* bc = classOf(func);
	const bool constructing = (flags & JS_CALL_FLAG_CONSTRUCTOR) != 0;
	NativeFn fn = bc == nullptr ? nullptr : (constructing ? bc->def->construct : bc->def->call);
	if (fn == nullptr)  return JS_ThrowTypeError(ctx, "%s", constructing ? "ooscript: object is not a constructor" : "ooscript: object is not callable");
	return runNative(ctx, fn, func, thisVal, argc, argv, constructing, nullptr, 0);
}

BackendClass* attach(ClassDef* def, JSContext* ctx)
{
	if (def == nullptr || ctx == nullptr)  return nullptr;
	auto* bc = static_cast<BackendClass*>(def->backend);
	if (bc == nullptr)
	{
		bc = new BackendClass();
		bc->def = def;
		bc->id = allocClassId();
		bc->hooked = def->addProperty != nullptr || def->delProperty != nullptr || def->getProperty != nullptr ||
		             def->setProperty != nullptr || def->resolve != nullptr || def->enumerate != nullptr ||
		             def->newEnumerate != nullptr;
		bc->cdef.class_name = def->name;
		bc->cdef.finalizer  = FinalizeTramp;
		bc->cdef.gc_mark    = MarkTramp;
		bc->cdef.call       = (def->call != nullptr || def->construct != nullptr) ? ClassCallTramp : nullptr;
		if (bc->hooked)
		{
			bc->exotic.get_own_property       = ExGetOwnProperty;
			bc->exotic.get_own_property_names = ExGetOwnPropertyNames;
			bc->exotic.delete_property        = ExDeleteProperty;
			bc->exotic.define_own_property    = ExDefineOwnProperty;
			bc->exotic.has_property           = ExHasProperty;
			bc->exotic.get_property           = ExGetProperty;
			bc->exotic.set_property           = ExSetProperty;
			bc->cdef.exotic = &bc->exotic;
		}
		gClasses.emplace(bc->id, bc);
		def->backend = bc;
	}
	JSRuntime* rt = JS_GetRuntime(ctx);
	if (!JS_IsRegisteredClass(rt, bc->id))  JS_NewClass(rt, bc->id, &bc->cdef);
	return bc;
}

// MARK: Natives ----------------------------------------------------------------------------------------

struct NativeRec
{
	NativeFn  fn;
	ClassDef* ctorClass;   // the class a constructor call instantiates (initClass), or null
	unsigned  nargs;
};

JSValue objectProto(JSContext* ctx)
{
	ContextState* cs = csOf(ctx);
	return cs != nullptr ? cs->objectProto : JS_NULL;
}

// A new object of `def` (or a plain object) with `proto`, or the class/Object prototype.
// Object.prototype.toString names a SpiderMonkey host object by its class ("[object Vector3D]",
// "[object Clock]"); scripts test for it. QuickJS-ng says "Object" unless Symbol.toStringTag says
// otherwise, so every class prototype -- and an instance whose prototype is plain Object.prototype
// -- carries the ClassDef's name as a non-enumerable, shape-level tag (bead oo-1gc.6).
void tagWithClassName(JSContext* ctx, JSValueConst obj, const ClassDef* def)
{
	if (def == nullptr || def->name == nullptr)  return;
	JSValue global = JS_GetGlobalObject(ctx);
	JSValue symbolCtor = JS_GetPropertyStr(ctx, global, "Symbol");
	JSValue tagSym = JS_GetPropertyStr(ctx, symbolCtor, "toStringTag");
	const JSAtom atom = JS_ValueToAtom(ctx, tagSym);
	if (atom != JS_ATOM_NULL)
	{
		if (JS_DefineProperty(ctx, obj, atom, JS_NewString(ctx, def->name), JS_UNDEFINED, JS_UNDEFINED,
		                      JS_PROP_HAS_VALUE | JS_PROP_HAS_CONFIGURABLE | JS_PROP_CONFIGURABLE |
		                      JS_PROP_HAS_ENUMERABLE | JS_PROP_HAS_WRITABLE | JS_PROP_NO_EXOTIC) < 0)
		{
			JS_FreeValue(ctx, JS_GetException(ctx));
		}
		JS_FreeAtom(ctx, atom);
	}
	JS_FreeValue(ctx, tagSym);
	JS_FreeValue(ctx, symbolCtor);
	JS_FreeValue(ctx, global);
}

JSValue newObjectRaw(JSContext* ctx, ClassDef* def, JSValueConst proto)
{
	if (def == nullptr)
	{
		return JS_IsObject(proto) ? JS_NewObjectProto(ctx, proto) : JS_NewObject(ctx);
	}
	BackendClass* bc = attach(def, ctx);
	JSValue p = JS_IsObject(proto) ? JS_DupValue(ctx, proto) : JS_GetClassProto(ctx, bc->id);
	if (!JS_IsObject(p))
	{
		JS_FreeValue(ctx, p);
		p = JS_DupValue(ctx, objectProto(ctx));
	}
	const bool plainProto = JS_VALUE_GET_PTR(p) == JS_VALUE_GET_PTR(objectProto(ctx));
	JSValue o = JS_NewObjectProtoClass(ctx, p, bc->id);
	JS_FreeValue(ctx, p);
	if (JS_IsException(o))  return o;
	JS_SetOpaque(o, new ObjRec());
	if (plainProto)  tagWithClassName(ctx, o, def);
	if (def->construct != nullptr)  JS_SetConstructorBit(ctx, o, true);
	return o;
}

struct ConstructMark
{
	bool on;
	ConstructMark(const Value* vp, bool constructing) : on(constructing) { if (on) gConstructing.push_back(vp); }
	~ConstructMark() { if (on) gConstructing.pop_back(); }
	ConstructMark(const ConstructMark&) = delete;
	ConstructMark& operator=(const ConstructMark&) = delete;
};

JSValue runNative(JSContext* ctx, NativeFn fn, JSValueConst func, JSValueConst thisVal, int argc,
                  JSValueConst* argv, bool constructing, ClassDef* ctorClass, unsigned nargs)
{
	RuntimeState* rs = rsOf(ctx);
	NativeScope scope(rs);
	const unsigned count = static_cast<unsigned>(argc < 0 ? 0 : argc);
	const unsigned slots = 2 + std::max(count, nargs);
	Value stackVp[12];
	std::vector<Value> heapVp;
	Value* vp = stackVp;
	if (slots > 12)  { heapVp.resize(slots); vp = heapVp.data(); }

	JSValue created = JS_UNDEFINED;
	if (constructing)
	{
		// thisVal is new.target: the new object gets its `prototype` and the constructor's class.
		JSValue proto = JS_GetPropertyStr(ctx, thisVal, "prototype");
		if (JS_IsException(proto))  return proto;
		created = newObjectRaw(ctx, ctorClass, proto);
		JS_FreeValue(ctx, proto);
		if (JS_IsException(created))  return created;
	}
	vp[0] = fromJS(ctx, func);
	vp[1] = constructing ? fromJS(ctx, created) : fromJS(ctx, thisVal);
	for (unsigned i = 0; i < count; ++i)  vp[2 + i] = fromJS(ctx, argv[i]);
	for (unsigned i = count; i + 2 < slots; ++i)  vp[2 + i] = undefinedValue();

	bool ok;
	{
		ConstructMark mark(vp, constructing);
		CallArgs args(wrap(ctx), count, vp);
		ok = fn(wrap(ctx), args);
	}
	if (!ok)
	{
		JS_FreeValue(ctx, created);
		return failValue(ctx);
	}
	if (constructing)
	{
		// `new` yields the native's object result, or the created object when it returned none.
		if (isObject(vp[0]) && !sameObject(toJS(vp[0]), func))
		{
			JS_FreeValue(ctx, created);
			return JS_DupValue(ctx, toJS(vp[0]));
		}
		return created;
	}
	return JS_DupValue(ctx, toJS(vp[0]));
}

JSValue NativeCallTramp(JSContext* ctx, JSValueConst func, JSValueConst thisVal, int argc, JSValueConst* argv, int flags)
{
	auto* rec = static_cast<NativeRec*>(JS_GetOpaque(func, gNativeClassId));
	if (rec == nullptr || rec->fn == nullptr)
	{
		return JS_ThrowTypeError(ctx, "%s", "ooscript: native function is not registered with the façade");
	}
	return runNative(ctx, rec->fn, func, thisVal, argc, argv, (flags & JS_CALL_FLAG_CONSTRUCTOR) != 0, rec->ctorClass, rec->nargs);
}

void NativeFinalizer(JSRuntime* /*rt*/, JSValueConst val)
{
	delete static_cast<NativeRec*>(JS_GetOpaque(val, gNativeClassId));
}

JSValue newNativeFunction(JSContext* ctx, const char* name, NativeFn fn, unsigned nargs, ClassDef* ctorClass, bool constructor)
{
	JSValue fproto = JS_GetFunctionProto(ctx);
	JSValue f = JS_NewObjectProtoClass(ctx, fproto, gNativeClassId);
	JS_FreeValue(ctx, fproto);
	if (JS_IsException(f))  return f;
	JS_SetOpaque(f, new NativeRec{fn, ctorClass, nargs});
	JS_DefinePropertyValueStr(ctx, f, "length", JS_NewInt32(ctx, static_cast<std::int32_t>(nargs)), JS_PROP_CONFIGURABLE);
	JS_DefinePropertyValueStr(ctx, f, "name", JS_NewString(ctx, name != nullptr ? name : ""), JS_PROP_CONFIGURABLE);
	if (constructor)  JS_SetConstructorBit(ctx, f, true);
	return f;
}

// MARK: Accessors (PropertySpec entries and defineProperty with hooks) --------------------------------

struct AccessorRec
{
	JSRuntime*     rt;
	PropertyGetter get;
	PropertySetter set;
	bool           byTinyid;
	std::int32_t   tinyid;
	JSAtom         atom;      // the property's name when !byTinyid (owned)
	bool           readOnly;
	int            refs;      // getter closure + setter closure
};

void AccessorRelease(void* opaque)
{
	auto* rec = static_cast<AccessorRec*>(opaque);
	if (--rec->refs > 0)  return;
	if (!rec->byTinyid && rec->atom != JS_ATOM_NULL)  JS_FreeAtomRT(rec->rt, rec->atom);
	delete rec;
}

PropertyId accessorId(JSContext* ctx, const AccessorRec* rec)
{
	return rec->byTinyid ? int32Id(rec->tinyid) : idFromAtom(ctx, rec->atom);
}

JSValue AccessorGetTramp(JSContext* ctx, JSValueConst thisVal, int /*argc*/, JSValueConst* /*argv*/, int /*magic*/, void* opaque)
{
	auto* rec = static_cast<AccessorRec*>(opaque);
	if (rec->get == nullptr || !JS_IsObject(thisVal))  return JS_UNDEFINED;
	NativeScope scope(rsOf(ctx));
	Value v = undefinedValue();   // DIVERGENCE: no per-object slot value for non-Shared accessors
	if (!rec->get(wrap(ctx), objOf(thisVal), accessorId(ctx, rec), &v))  return failValue(ctx);
	return JS_DupValue(ctx, toJS(v));
}

JSValue AccessorSetTramp(JSContext* ctx, JSValueConst thisVal, int argc, JSValueConst* argv, int /*magic*/, void* opaque)
{
	auto* rec = static_cast<AccessorRec*>(opaque);
	// Read-only accessors ignore assignment silently, as SpiderMonkey's non-strict set does.
	if (rec->readOnly || rec->set == nullptr || !JS_IsObject(thisVal))  return JS_UNDEFINED;
	NativeScope scope(rsOf(ctx));
	Value v = argc > 0 ? fromJS(ctx, argv[0]) : undefinedValue();
	if (!rec->set(wrap(ctx), objOf(thisVal), accessorId(ctx, rec), false, &v))  return failValue(ctx);
	return JS_UNDEFINED;
}

int jsFlags(PropertyFlag f)
{
	const auto b = static_cast<std::uint8_t>(f);
	int flags = JS_PROP_HAS_CONFIGURABLE | JS_PROP_HAS_ENUMERABLE | JS_PROP_HAS_WRITABLE | JS_PROP_HAS_VALUE;
	if ((b & static_cast<std::uint8_t>(PropertyFlag::Enumerate)) != 0)  flags |= JS_PROP_ENUMERABLE;
	if ((b & static_cast<std::uint8_t>(PropertyFlag::ReadOnly)) == 0)   flags |= JS_PROP_WRITABLE;
	if ((b & static_cast<std::uint8_t>(PropertyFlag::Permanent)) == 0)  flags |= JS_PROP_CONFIGURABLE;
	return flags;
}

void noteDefined(JSContext* ctx, JSValueConst obj, JSAtom atom)
{
	if (gDefineCollector == nullptr || gDefineCollector->target != JS_VALUE_GET_PTR(obj))  return;
	const int has = JS_GetOwnProperty(ctx, nullptr, obj, atom);   // only names that are new
	if (has < 0)  { JS_FreeValue(ctx, JS_GetException(ctx)); return; }
	if (has == 0)  gDefineCollector->atoms.push_back(JS_DupAtom(ctx, atom));
}

// SpiderMonkey's native define overwrote an existing permanent property silently; QuickJS-ng
// refuses to redefine a non-configurable one. A repeat definition keeps the existing property
// (the game's repeats -- an enumerate hook redefining every name each time -- are identical).
int keepsExisting(JSContext* ctx, JSValueConst obj, JSAtom atom)
{
	JSPropertyDescriptor d;
	const int has = JS_GetOwnProperty(ctx, &d, obj, atom);
	if (has <= 0)  return has;
	const bool fixed = (d.flags & JS_PROP_CONFIGURABLE) == 0;
	freeDesc(ctx, &d);
	return fixed ? 1 : 0;
}

bool defineAccessor(JSContext* ctx, JSValueConst obj, JSAtom atom, PropertyGetter get, PropertySetter set,
                    bool byTinyid, std::int32_t tinyid, PropertyFlag flags)
{
	noteDefined(ctx, obj, atom);
	const int keep = keepsExisting(ctx, obj, atom);
	if (keep < 0)  return false;
	if (keep > 0)  return true;
	const auto b = static_cast<std::uint8_t>(flags);
	// A read-only property gets no setter at all, so its descriptor
	// says it is not writable and assignment behaves as SpiderMonkey's did for a read-only
	// property: ignored in sloppy code, a TypeError in strict code (bead oo-1gc.6).
	const bool readOnly = (b & static_cast<std::uint8_t>(PropertyFlag::ReadOnly)) != 0;
	auto* rec = new AccessorRec{JS_GetRuntime(ctx), get, set, byTinyid, tinyid,
	                            byTinyid ? JS_ATOM_NULL : JS_DupAtom(ctx, atom),
	                            readOnly, readOnly ? 1 : 2};
	JSValue g = JS_NewCClosure(ctx, AccessorGetTramp, "", AccessorRelease, 0, 0, rec);
	if (JS_IsException(g))  { rec->refs = 1; AccessorRelease(rec); return false; }
	JSValue s = JS_UNDEFINED;
	if (!readOnly)
	{
		s = JS_NewCClosure(ctx, AccessorSetTramp, "", AccessorRelease, 1, 0, rec);
		if (JS_IsException(s))  { JS_FreeValue(ctx, g); AccessorRelease(rec); return false; }
	}
	int f = JS_PROP_HAS_GET | JS_PROP_HAS_SET | JS_PROP_HAS_CONFIGURABLE | JS_PROP_HAS_ENUMERABLE | JS_PROP_NO_EXOTIC | JS_PROP_THROW;
	if ((b & static_cast<std::uint8_t>(PropertyFlag::Enumerate)) != 0)  f |= JS_PROP_ENUMERABLE;
	if ((b & static_cast<std::uint8_t>(PropertyFlag::Permanent)) == 0)  f |= JS_PROP_CONFIGURABLE;
	// A hooked object may still hold a slot of that name; defining an accessor replaces it.
	if (ObjRec* orec = recOf(obj))
	{
		if (Slot* sl = orec->find(atom))
		{
			JS_FreeAtom(ctx, sl->atom);
			JS_FreeValue(ctx, sl->value);
			orec->slots.erase(orec->slots.begin() + (sl - orec->slots.data()));
		}
	}
	const int r = JS_DefineProperty(ctx, obj, atom, JS_UNDEFINED, g, s, f);
	JS_FreeValue(ctx, g);
	JS_FreeValue(ctx, s);
	return r >= 0;
}

bool defineData(JSContext* ctx, JSValueConst obj, JSAtom atom, JSValueConst value, int flags)
{
	return JS_DefineProperty(ctx, obj, atom, value, JS_UNDEFINED, JS_UNDEFINED, flags | JS_PROP_THROW) >= 0;
}

bool definePropertyImpl(JSContext* ctx, JSValueConst obj, JSAtom atom, JSValueConst value,
                        PropertyGetter getter, PropertySetter setter, PropertyFlag flags)
{
	if (getter != nullptr || setter != nullptr)
	{
		// js_DefineNativeProperty's default: a hook left null falls back to the class's own.
		ClassDef* def = classDefOf(ctx, obj);
		if (getter == nullptr && def != nullptr)  getter = def->getProperty;
		if (setter == nullptr && def != nullptr)  setter = def->setProperty;
		return defineAccessor(ctx, obj, atom, getter, setter, false, 0, flags);
	}
	noteDefined(ctx, obj, atom);
	const int keep = keepsExisting(ctx, obj, atom);
	if (keep < 0)  return false;
	if (keep > 0)  return true;
	return defineData(ctx, obj, atom, value, jsFlags(flags));
}

bool definePropertySpecs(JSContext* ctx, JSValueConst obj, const PropertySpec* ps)
{
	ClassDef* def = classDefOf(ctx, obj);
	for (; ps != nullptr && ps->name != nullptr; ++ps)
	{
		AtomRef atom(ctx, JS_NewAtom(ctx, ps->name));
		if (atom.atom == JS_ATOM_NULL)  return false;
		// A table that lists a name twice (Ship's has "homeSystem" twice, same tinyid) was a
		// silent redefinition under SpiderMonkey's native define; QuickJS-ng refuses to redefine a
		// permanent property, which failed the whole initClass. The first entry stands.
		const int exists = JS_GetOwnProperty(ctx, nullptr, obj, atom.atom);
		if (exists < 0)  return false;
		if (exists > 0)  continue;
		PropertyGetter get = ps->getter != nullptr ? ps->getter : (def != nullptr ? def->getProperty : nullptr);
		PropertySetter set = ps->setter != nullptr ? ps->setter : (def != nullptr ? def->setProperty : nullptr);
		const bool ok = (get != nullptr || set != nullptr)
			? defineAccessor(ctx, obj, atom.atom, get, set, true, ps->tinyid, ps->flags)
			: defineData(ctx, obj, atom.atom, JS_UNDEFINED, jsFlags(ps->flags));
		if (!ok)  return false;
		const auto fb = static_cast<std::uint8_t>(ps->flags);
		const auto sp = static_cast<std::uint8_t>(PropertyFlag::Shared) | static_cast<std::uint8_t>(PropertyFlag::Permanent);
		if ((fb & sp) == sp && (get != nullptr || set != nullptr))
		{
			gSharedPermanent[JS_VALUE_GET_PTR(obj)].push_back(SharedPermanent{ JS_DupAtom(ctx, atom.atom),
				(fb & static_cast<std::uint8_t>(PropertyFlag::Enumerate)) != 0,
				(fb & static_cast<std::uint8_t>(PropertyFlag::ReadOnly)) != 0 });
		}
	}
	return true;
}

// Every native is constructible, as in SpiderMonkey 1.8.5: its InvokeConstructor created `this` from
// the callee's `prototype` (Object.prototype when it has none), called the native, and returned the
// native's object result or else that `this` (jsinterp.cpp, js_CreateThis then Invoke with
// JSINVOKE_CONSTRUCT). Expansions rely on it: `new Vector3D.random(n)` (bead oo-1gc.13) is a
// constructor call of a static method, which QuickJS-ng refuses without the constructor bit.
// runNative already implements exactly that construct path for a native with no ctorClass.
JSValue defineNative(JSContext* ctx, JSValueConst obj, const char* name, NativeFn call, unsigned nargs, std::uint16_t flags)
{
	JSValue f = newNativeFunction(ctx, name, call, nargs, nullptr, true);
	if (JS_IsException(f))  return f;
	AtomRef atom(ctx, JS_NewAtom(ctx, name));
	if (!defineData(ctx, obj, atom.atom, f, jsFlags(static_cast<PropertyFlag>(flags & 0xFF)) | JS_PROP_NO_EXOTIC))
	{
		JS_FreeValue(ctx, f);
		return JS_EXCEPTION;
	}
	return f;
}

bool defineFunctionSpecs(JSContext* ctx, JSValueConst obj, const FunctionSpec* fs)
{
	for (; fs != nullptr && fs->name != nullptr; ++fs)
	{
		JSValue f = defineNative(ctx, obj, fs->name, fs->call, fs->nargs, fs->flags);
		if (JS_IsException(f))  return false;
		JS_FreeValue(ctx, f);
	}
	return true;
}

// SpiderMonkey's convert hook, as a Symbol.toPrimitive method on the class prototype.
JSValue ToPrimitiveTramp(JSContext* ctx, JSValueConst thisVal, int argc, JSValueConst* argv, int /*magic*/, void* opaque)
{
	auto* def = static_cast<ClassDef*>(opaque);
	if (!JS_IsObject(thisVal))  return JS_DupValue(ctx, thisVal);
	Type hint = Type::Void;
	if (argc > 0 && JS_IsString(argv[0]))
	{
		const std::string h = toStdString(ctx, argv[0]);
		if (h == "number")       hint = Type::Number;
		else if (h == "string")  hint = Type::String;
	}
	{
		NativeScope scope(rsOf(ctx));
		Value v = fromJS(ctx, thisVal);
		if (!def->convert(wrap(ctx), objOf(thisVal), hint, &v))  return failValue(ctx);
		if (!isObject(v))  return JS_DupValue(ctx, toJS(v));
	}
	// The hook left an object: OrdinaryToPrimitive.
	const char* order[2] = { "valueOf", "toString" };
	if (hint == Type::String)  std::swap(order[0], order[1]);
	for (const char* m : order)
	{
		JSValue f = JS_GetPropertyStr(ctx, thisVal, m);
		if (JS_IsException(f))  return f;
		if (JS_IsFunction(ctx, f))
		{
			JSValue r = JS_Call(ctx, f, thisVal, 0, nullptr);
			JS_FreeValue(ctx, f);
			if (JS_IsException(r) || !JS_IsObject(r))  return r;
			JS_FreeValue(ctx, r);
		}
		else
		{
			JS_FreeValue(ctx, f);
		}
	}
	return JS_ThrowTypeError(ctx, "%s", "cannot convert object to primitive value");
}

bool installConvert(JSContext* ctx, JSValueConst proto, ClassDef* def)
{
	JSValue global = JS_GetGlobalObject(ctx);
	JSValue symbolCtor = JS_GetPropertyStr(ctx, global, "Symbol");
	JSValue toPrim = JS_GetPropertyStr(ctx, symbolCtor, "toPrimitive");
	JS_FreeValue(ctx, symbolCtor);
	JS_FreeValue(ctx, global);
	if (!JS_IsSymbol(toPrim))  { JS_FreeValue(ctx, toPrim); return false; }
	AtomRef atom(ctx, JS_ValueToAtom(ctx, toPrim));
	JS_FreeValue(ctx, toPrim);
	JSValue f = JS_NewCClosure(ctx, ToPrimitiveTramp, "[Symbol.toPrimitive]", nullptr, 1, 0, def);
	if (JS_IsException(f))  return false;
	return JS_DefinePropertyValue(ctx, proto, atom.atom, f, JS_PROP_CONFIGURABLE | JS_PROP_NO_EXOTIC) >= 0;
}

// MARK: Scripts ----------------------------------------------------------------------------------------

void releaseScript(JSRuntime* rt, ScriptRep* s)
{
	if (s == nullptr || --s->refs > 0)  return;
	JS_FreeValueRT(rt != nullptr ? rt : s->rt, s->bytecode);
	delete s;
}

void ScriptObjectFinalizer(JSRuntime* rt, JSValueConst val)
{
	releaseScript(rt, static_cast<ScriptRep*>(JS_GetOpaque(val, gScriptClassId)));
}

JSEvalOptions evalOptions(const char* filename, unsigned lineno, int flags)
{
	JSEvalOptions o{};
	o.version    = JS_EVAL_OPTIONS_VERSION;
	o.eval_flags = JS_EVAL_TYPE_GLOBAL | flags;
	o.filename   = filename != nullptr ? filename : "";
	o.line_num   = lineno != 0 ? static_cast<int>(lineno) : 1;
	return o;
}

// SpiderMonkey runs a script with its scope object at the head of the scope chain, so a bare name
// that the global lacks resolves through the script object -- at top level and in every closure
// the script creates (oolite-global-prefix.js reads the engine-provided `special` that way,
// oolite-priorityai.js its own `this.PriorityAIController`). QuickJS-ng global code has only the
// global scope. The global's prototype is therefore a "scope fallback" exotic object: a name the
// global does not have is looked up on the scope object of the script whose code is running,
// identified by the running function's filename (every script is registered under its file when
// it runs).
// The same file runs for several objects -- one ship script per ship -- and in SpiderMonkey each
// run's closures resolve through their own run's object. So a façade-class scope object is also
// marked with its file (ObjRec::scopeFile), and the lookup prefers the innermost `this` of a call
// the façade made (a handler call, a timer, the script's own run) that is marked with the running
// file; only when none is does it fall back to the object the file last ran for. Without that a
// ship script whose handler sets `this.list` and then reads `list` failed with a ReferenceError
// whenever another ship had run the same file since (bead oo-1gc.15: BUS_MegaBat_events.js).
// DIVERGENCE: an assignment to such a name defines it on the global rather than the script object;
// console-evaluated code (not from a script file) gets no fallback; a closure of one ship's run
// called directly from another ship's handler (no façade call in between) resolves through the
// caller's object. (beads oo-1gc.4, oo-1gc.15)
JSClassID gScopeFallbackClassId = 0;
std::unordered_map<std::string, JSValue>& gScopeByFile = *new std::unordered_map<std::string, JSValue>;   // owned references
std::vector<JSValue>& gCallThis = *new std::vector<JSValue>;                          // `this` of each façade call in progress (borrowed)

struct CallThisMark
{
	explicit CallThisMark(JSValueConst thisVal) { gCallThis.push_back(thisVal); }
	~CallThisMark() { gCallThis.pop_back(); }
	CallThisMark(const CallThisMark&) = delete;
	CallThisMark& operator=(const CallThisMark&) = delete;
};

void registerScope(JSContext* ctx, const char* filename, JSValueConst scope)
{
	if (filename == nullptr || *filename == 0)  return;
	if (ObjRec* rec = recOf(scope))  rec->scopeFile = filename;
	auto it = gScopeByFile.find(filename);
	if (it != gScopeByFile.end())
	{
		if (JS_VALUE_GET_PTR(it->second) == JS_VALUE_GET_PTR(scope))  return;
		JS_FreeValue(ctx, it->second);
		it->second = JS_DupValue(ctx, scope);
	}
	else
	{
		gScopeByFile.emplace(filename, JS_DupValue(ctx, scope));
	}
}

bool runningScope(JSContext* ctx, JSValue* scope)
{
	if (gScopeByFile.empty())  return false;
	// The innermost frame that belongs to a registered script: code eval()ed inside a script (the
	// debug console's evaluate) has its own pseudo-filename, and SpiderMonkey resolved its names
	// through the calling script's scope chain.
	for (int level = 0; level < 8; ++level)
	{
		const JSAtom a = JS_GetScriptOrModuleName(ctx, level);
		if (a == JS_ATOM_NULL)  continue;
		const char* name = JS_AtomToCString(ctx, a);
		JS_FreeAtom(ctx, a);
		if (name == nullptr)  { JS_FreeValue(ctx, JS_GetException(ctx)); return false; }
		auto it = gScopeByFile.find(name);
		JS_FreeCString(ctx, name);
		if (it == gScopeByFile.end())  continue;
		for (auto t = gCallThis.rbegin(); t != gCallThis.rend(); ++t)
		{
			const ObjRec* rec = recOf(*t);
			if (rec != nullptr && rec->scopeFile == it->first)  { *scope = *t; return true; }
		}
		*scope = it->second;
		return true;
	}
	return false;
}

int ScopeFallbackGetOwnProperty(JSContext* ctx, JSPropertyDescriptor* desc, JSValueConst /*obj*/, JSAtom atom)
{
	JSValue scope;
	if (!runningScope(ctx, &scope))  return 0;
	const int has = JS_HasProperty(ctx, scope, atom);
	if (has <= 0)  return has;
	if (desc != nullptr)
	{
		JSValue v = JS_GetProperty(ctx, scope, atom);
		if (JS_IsException(v))  return -1;
		desc->flags  = JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE;
		desc->value  = v;
		desc->getter = JS_UNDEFINED;
		desc->setter = JS_UNDEFINED;
	}
	return 1;
}

JSClassExoticMethods gScopeFallbackExotic = [] {
	JSClassExoticMethods m{};
	m.get_own_property = ScopeFallbackGetOwnProperty;
	return m;
}();

void installScopeFallback(JSContext* ctx)
{
	JSValue global = JS_GetGlobalObject(ctx);
	JSValue proto = JS_GetPrototype(ctx, global);
	JSValue fallback = JS_NewObjectProtoClass(ctx, proto, gScopeFallbackClassId);
	if (!JS_IsException(fallback))  JS_SetPrototype(ctx, global, fallback);
	else                            JS_FreeValue(ctx, JS_GetException(ctx));
	JS_FreeValue(ctx, fallback);
	JS_FreeValue(ctx, proto);
	JS_FreeValue(ctx, global);
}

void releaseScopes(JSRuntime* rt)
{
	for (auto& e : gScopeByFile)  JS_FreeValueRT(rt, e.second);
	gScopeByFile.clear();
}

bool evalWithThis(JSContext* ctx, Object scope, const std::string& src, const char* filename, unsigned lineno, Value* rval)
{
	JSValue global = JS_GetGlobalObject(ctx);
	JSValue thisObj = scope != nullptr ? OBJVAL(scope) : global;
	JSEvalOptions o = evalOptions(filename, lineno, 0);
	if (scope != nullptr && JS_VALUE_GET_PTR(thisObj) != JS_VALUE_GET_PTR(global))  registerScope(ctx, filename, thisObj);
	JSValue r;
	{
		CallThisMark mark(thisObj);
		r = JS_EvalThis2(ctx, thisObj, src.c_str(), src.size(), &o);
	}
	JS_FreeValue(ctx, global);
	if (JS_IsException(r))
	{
		if (rval != nullptr)  *rval = undefinedValue();
		return finish(ctx, false);
	}
	if (rval != nullptr)  *rval = take(ctx, r);
	else                  JS_FreeValue(ctx, r);
	return true;
}

void writeU32(std::vector<std::uint8_t>& out, std::uint32_t v)
{
	for (int i = 0; i < 4; ++i)  out.push_back(static_cast<std::uint8_t>(v >> (8 * i)));
}

bool readU32(const std::uint8_t*& p, const std::uint8_t* end, std::uint32_t* v)
{
	if (end - p < 4)  return false;
	*v = 0;
	for (int i = 0; i < 4; ++i)  *v |= static_cast<std::uint32_t>(p[i]) << (8 * i);
	p += 4;
	return true;
}

constexpr char kScriptMagic[8] = { 'O', 'O', 'Q', 'J', 'S', 'X', '1', '\0' };

// MARK: Operation callback -----------------------------------------------------------------------------

int InterruptTramp(JSRuntime* /*rt*/, void* opaque)
{
	auto* rs = static_cast<RuntimeState*>(opaque);
	for (ContextState* cs : rs->contexts)
	{
		if (!cs->triggered.exchange(false))  continue;
		if (cs->opcb == nullptr)  continue;
		NativeScope scope(rs);
		if (!cs->opcb(wrap(cs->ctx)))  return 1;   // QuickJS-ng throws its uncatchable "interrupted"
	}
	return 0;
}

} // namespace

// MARK: Value conversions that may run script ----------------------------------------------------

bool newNumberValue(Context /*cx*/, double d, Value* rval) { *rval = numberValue(d); return true; }

bool valueToNumber(Context cx, Value v, double* out)
{
	return JS_ToFloat64(CX(cx), out, toJS(v)) == 0;
}

bool valueToBoolean(Context cx, Value v, bool* out)
{
	const int r = JS_ToBool(CX(cx), toJS(v));
	if (r < 0)  return false;
	*out = r != 0;
	return true;
}

bool valueToObject(Context cx, Value v, Object* out)
{
	// JS_ValueToObject: null and undefined convert to a null object without an error.
	if (isNullOrUndefined(v))  { *out = nullptr; return true; }
	if (isObject(v))           { *out = toObject(v); return true; }
	JSContext* ctx = CX(cx);
	JSValue o = JS_ToObject(ctx, toJS(v));
	if (JS_IsException(o))  { *out = nullptr; return false; }
	*out = takeObject(ctx, o);
	return true;
}

bool valueToInt32(Context cx, Value v, std::int32_t* out)
{
	// JS_ValueToInt32 is the old, non-ECMA conversion: round to nearest, and an error (not a
	// wrap) when the number is not finite or out of int32 range.
	if (isInt32(v))  { *out = toInt32(v); return true; }
	double d = 0;
	if (!valueToNumber(cx, v, &d))  return false;
	if (!std::isfinite(d) || d > 2147483647.0 || d < -2147483648.0)
	{
		JSValue s = JS_ToString(CX(cx), toJS(v));
		const std::string str = JS_IsException(s) ? std::string("value") : toStdString(CX(cx), s);
		if (JS_IsException(s))  JS_FreeValue(CX(cx), JS_GetException(CX(cx)));
		else                    JS_FreeValue(CX(cx), s);
		const std::string msg = "can't convert " + str + " to an integer";
		reportErrorImpl(CX(cx), msg.c_str());
		return false;
	}
	*out = static_cast<std::int32_t>(std::floor(d + 0.5));
	return true;
}

bool valueToECMAInt32(Context cx, Value v, std::int32_t* out)
{
	return JS_ToInt32(CX(cx), out, toJS(v)) == 0;
}

bool valueToECMAUint32(Context cx, Value v, std::uint32_t* out)
{
	std::int32_t i = 0;
	if (JS_ToInt32(CX(cx), &i, toJS(v)) != 0)  return false;
	*out = static_cast<std::uint32_t>(i);
	return true;
}

String valueToString(Context cx, Value v)
{
	if (isString(v))  return toString(v);
	JSContext* ctx = CX(cx);
	JSValue s = JS_ToString(ctx, toJS(v));
	if (JS_IsException(s))  return nullptr;
	return takeString(ctx, s);
}

Function valueToFunction(Context cx, Value v)
{
	JSContext* ctx = CX(cx);
	if (JS_IsFunction(ctx, toJS(v)))  return reinterpret_cast<Function>(toObject(v));
	JSValue s = JS_ToString(ctx, toJS(v));
	std::string str = JS_IsException(s) ? std::string("value") : toStdString(ctx, s);
	if (JS_IsException(s))  JS_FreeValue(ctx, JS_GetException(ctx));
	else                    JS_FreeValue(ctx, s);
	const std::string msg = str + " is not a function";
	reportErrorImpl(ctx, msg.c_str());
	return nullptr;
}

bool valueToId(Context cx, Value v, PropertyId* out)
{
	if (isInt32(v))  { *out = int32Id(toInt32(v)); return true; }
	JSContext* ctx = CX(cx);
	const JSAtom atom = JS_ValueToAtom(ctx, toJS(v));
	if (atom == JS_ATOM_NULL)  return false;
	*out = idFromAtom(ctx, atom);
	JS_FreeAtom(ctx, atom);
	return true;
}

bool idToValue(Context cx, PropertyId id, Value* out)
{
	if (isInt32Id(id))  { *out = int32Value(idToInt32(id)); return true; }
	if (isVoidId(id))   { *out = undefinedValue(); return true; }
	JSContext* ctx = CX(cx);
	*out = take(ctx, JS_AtomToValue(ctx, atomOfId(id)));
	return true;
}

Type typeOfValue(Context cx, Value v)
{
	if (isUndefined(v))             return Type::Void;
	if (isNull(v))                  return Type::Object;   // typeof null
	if (isBoolean(v))               return Type::Boolean;
	if (isNumber(v))                return Type::Number;
	if (isString(v))                return Type::String;
	if (isObject(v))                return JS_IsFunction(ctxOr(cx), toJS(v)) ? Type::Function : Type::Object;
	return Type::Void;   // symbols and private values have no SpiderMonkey 1.8.5 type
}

const char* typeName(Type t)
{
	switch (t)
	{
		case Type::Void:     return "undefined";
		case Type::Object:   return "object";
		case Type::Function: return "function";
		case Type::String:   return "string";
		case Type::Number:   return "number";
		case Type::Boolean:  return "boolean";
		case Type::Null:     return "null";
		case Type::XML:      return "xml";
	}
	return "undefined";
}

String idToString(PropertyId id)
{
	JSContext* ctx = gDefaultCtx;
	if (ctx == nullptr || !isStringId(id))  return nullptr;
	String s = takeString(ctx, JS_AtomToString(ctx, atomOfId(id)));
	if (s != nullptr)  rsOf(ctx)->internedStrings.insert(s);   // an id's string is an atom
	return s;
}

// MARK: Call arguments --------------------------------------------------------------------------

Object CallArgs::thisObject() const
{
	const Value t = vp_[1];
	if (isObject(t))            return toObject(t);
	if (isNullOrUndefined(t))   return getGlobalObject(cx_);
	Object o = nullptr;
	return valueToObject(cx_, t, &o) ? o : nullptr;
}

bool CallArgs::isConstructing() const
{
	return std::find(gConstructing.begin(), gConstructing.end(), vp_) != gConstructing.end();
}

// MARK: Objects -----------------------------------------------------------------------------

Object newObject(Context cx, ClassDef* def, Object proto, Object /*parent*/)
{
	JSContext* ctx = CX(cx);
	JSValue o = newObjectRaw(ctx, def, OBJVAL_OR_NULL(proto));
	if (JS_IsException(o))  return nullptr;
	return takeObject(ctx, o);
}

Object newGlobalObject(Context cx, ClassDef* def)
{
	// DIVERGENCE: see the banner. The context's own global stands in; the ClassDef is recorded.
	JSContext* ctx = CX(cx);
	ContextState* cs = csOf(ctx);
	if (cs != nullptr)  cs->globalDef = def;
	Object global = getGlobalObject(cx);
	if (global != nullptr)  tagWithClassName(ctx, OBJVAL(global), def);
	return global;
}

void setGlobalObject(Context /*cx*/, Object /*global*/)
{
	// A QuickJS-ng context's global object is fixed at creation; newGlobalObject hands that one out.
}

bool initStandardClasses(Context /*cx*/, Object /*global*/) { return true; }   // JS_NewContext added them

void clearScope(Context cx, Object obj)
{
	JSContext* ctx = CX(cx);
	JSValue o = OBJVAL(obj);
	if (ObjRec* rec = recOf(o))
	{
		for (Slot& s : rec->slots)  { JS_FreeAtom(ctx, s.atom); JS_FreeValue(ctx, s.value); }
		rec->slots.clear();
	}
	JSPropertyEnum* tab = nullptr;
	std::uint32_t len = 0;
	if (JS_GetOwnPropertyNames(ctx, &tab, &len, o, JS_GPN_STRING_MASK | JS_GPN_SYMBOL_MASK) < 0)
	{
		JS_FreeValue(ctx, JS_GetException(ctx));
		return;
	}
	// DIVERGENCE: non-configurable (permanent) properties survive; SpiderMonkey's ClearScope
	// empties the scope outright.
	for (std::uint32_t i = 0; i < len; ++i)  JS_DeleteProperty(ctx, o, tab[i].atom, 0);
	JS_FreePropertyEnum(ctx, tab, len);
	if (JS_HasException(ctx))  JS_FreeValue(ctx, JS_GetException(ctx));
}

Object initClass(Context cx, Object obj, Object parentProto, ClassDef* def,
                 NativeFn constructor, unsigned nargs,
                 const PropertySpec* ps, const FunctionSpec* fs,
                 const PropertySpec* staticPs, const FunctionSpec* staticFs)
{
	JSContext* ctx = CX(cx);
	ContextState* cs = csOf(ctx);
	BackendClass* bc = attach(def, ctx);
	if (bc == nullptr || cs == nullptr)  return nullptr;

	JSValue proto = JS_NewObjectProtoClass(ctx, parentProto != nullptr ? OBJVAL(parentProto) : cs->objectProto, bc->id);
	if (JS_IsException(proto))  return nullptr;
	JS_SetOpaque(proto, new ObjRec());
	tagWithClassName(ctx, proto, def);
	Object protoObj = takeObject(ctx, proto);   // the arena holds our reference from here on
	JS_SetClassProto(ctx, bc->id, JS_DupValue(ctx, OBJVAL(protoObj)));

	JSValue ctor;
	if (constructor != nullptr)
	{
		ctor = newNativeFunction(ctx, def->name, constructor, nargs, def, true);
		if (JS_IsException(ctor))  return nullptr;
		AtomRef protoAtom(ctx, JS_NewAtom(ctx, "prototype"));
		AtomRef ctorAtom(ctx, JS_NewAtom(ctx, "constructor"));
		if (!defineData(ctx, ctor, protoAtom.atom, OBJVAL(protoObj), JS_PROP_HAS_VALUE | JS_PROP_HAS_WRITABLE | JS_PROP_HAS_ENUMERABLE | JS_PROP_HAS_CONFIGURABLE) ||
		    !defineData(ctx, OBJVAL(protoObj), ctorAtom.atom, ctor, JS_PROP_HAS_VALUE | JS_PROP_HAS_WRITABLE | JS_PROP_HAS_ENUMERABLE | JS_PROP_HAS_CONFIGURABLE | JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE | JS_PROP_NO_EXOTIC))
		{
			JS_FreeValue(ctx, ctor);
			return nullptr;
		}
	}
	else
	{
		// JS_InitClass without a constructor names the prototype itself, and it is its own "constructor".
		ctor = JS_DupValue(ctx, OBJVAL(protoObj));
		cs->ctorForProto[protoObj] = protoObj;
	}
	Object ctorObj = takeObject(ctx, ctor);

	if (obj != nullptr && def->name != nullptr)
	{
		AtomRef nameAtom(ctx, JS_NewAtom(ctx, def->name));
		if (!defineData(ctx, OBJVAL(obj), nameAtom.atom, OBJVAL(ctorObj), JS_PROP_HAS_VALUE | JS_PROP_HAS_WRITABLE | JS_PROP_HAS_ENUMERABLE | JS_PROP_HAS_CONFIGURABLE | JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE))  return nullptr;
	}
	if (!definePropertySpecs(ctx, OBJVAL(protoObj), ps))  return nullptr;
	if (!defineFunctionSpecs(ctx, OBJVAL(protoObj), fs))  return nullptr;
	if (constructor != nullptr)
	{
		if (!definePropertySpecs(ctx, OBJVAL(ctorObj), staticPs))  return nullptr;
		if (!defineFunctionSpecs(ctx, OBJVAL(ctorObj), staticFs))  return nullptr;
	}
	if (def->convert != nullptr && !installConvert(ctx, OBJVAL(protoObj), def))  return nullptr;
	return protoObj;
}

Object defineObject(Context cx, Object obj, const char* name, ClassDef* def, Object proto, PropertyFlag flags)
{
	JSContext* ctx = CX(cx);
	JSValue o = newObjectRaw(ctx, def, OBJVAL_OR_NULL(proto));
	if (JS_IsException(o))  return nullptr;
	Object result = takeObject(ctx, o);
	AtomRef atom(ctx, JS_NewAtom(ctx, name));
	if (!defineData(ctx, OBJVAL(obj), atom.atom, OBJVAL(result), jsFlags(flags)))  return nullptr;
	return result;
}

Object getConstructor(Context cx, Object proto)
{
	JSContext* ctx = CX(cx);
	if (ContextState* cs = csOf(ctx))
	{
		auto it = cs->ctorForProto.find(proto);
		if (it != cs->ctorForProto.end())  return static_cast<Object>(it->second);
	}
	JSValue c = JS_GetPropertyStr(ctx, OBJVAL(proto), "constructor");
	if (JS_IsException(c))  return nullptr;
	if (!JS_IsFunction(ctx, c))
	{
		JS_FreeValue(ctx, c);
		reportErrorImpl(ctx, "no constructor");
		return nullptr;
	}
	return takeObject(ctx, c);
}

Object getPrototype(Context cx, Object obj)
{
	JSContext* ctx = CX(cx);
	return takeObject(ctx, JS_GetPrototype(ctx, OBJVAL(obj)));
}

Object getParent(Context cx, Object /*obj*/)          { return getGlobalObject(cx); }   // every parent chain ends at the one global
Object getGlobalForObject(Context cx, Object /*obj*/) { return getGlobalObject(cx); }

Object getGlobalObject(Context cx)
{
	// The context keeps the global alive for its whole life, so no arena reference is needed.
	JSContext* ctx = CX(cx);
	JSValue g = JS_GetGlobalObject(ctx);
	Object out = objOf(g);
	JS_FreeValue(ctx, g);
	return out;
}

// The engine's own classes (Object, Array, String, ...) answer a stable, hook-less descriptor per
// engine class id, named as SpiderMonkey names them, so the game can key its object converters
// on them exactly as it keyed on the engine's class pointer (bead oo-1gc.4). The name comes from
// Object.prototype.toString's tag the first time an id is seen.
const ClassDef* foreignClassDef(JSContext* ctx, JSValueConst obj)
{
	static std::unordered_map<JSClassID, ClassDef*>& sForeign = *new std::unordered_map<JSClassID, ClassDef*>;	// immortal, as the registries above (bead oo-9ht.173)
	const JSClassID id = JS_GetClassID(obj);
	auto it = sForeign.find(id);
	if (it != sForeign.end())  return it->second;
	std::string name = "Object";
	JSValue global = JS_GetGlobalObject(ctx);
	JSValue objectCtor = JS_GetPropertyStr(ctx, global, "Object");
	JSValue objectProto = JS_GetPropertyStr(ctx, objectCtor, "prototype");
	JSValue toStr = JS_GetPropertyStr(ctx, objectProto, "toString");
	JSValue tag = JS_Call(ctx, toStr, obj, 0, nullptr);
	if (JS_IsString(tag))
	{
		const std::string t = toStdString(ctx, tag);   // "[object Name]"
		if (t.size() > 9 && t.compare(0, 8, "[object ") == 0)  name = t.substr(8, t.size() - 9);
	}
	else if (JS_IsException(tag))
	{
		JS_FreeValue(ctx, JS_GetException(ctx));
	}
	JS_FreeValue(ctx, tag);
	JS_FreeValue(ctx, toStr);
	JS_FreeValue(ctx, objectProto);
	JS_FreeValue(ctx, objectCtor);
	JS_FreeValue(ctx, global);
	auto* def = new ClassDef { nullptr, ClassFlag::None, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
	                           nullptr, nullptr, nullptr, nullptr, nullptr, nullptr };
	def->name = (new std::string(name))->c_str();
	sForeign.emplace(id, def);
	return def;
}

const ClassDef* getClass(Context cx, Object obj)
{
	if (obj == nullptr)  return nullptr;
	if (BackendClass* bc = classOf(OBJVAL(obj)))  return bc->def;
	JSContext* ctx = ctxOr(cx);
	return ctx != nullptr ? classDefOf(ctx, OBJVAL(obj)) : nullptr;
}

const ClassDef* getObjectClass(Context cx, Object obj)
{
	if (obj == nullptr)  return nullptr;
	if (const ClassDef* def = getClass(cx, obj))  return def;
	JSContext* ctx = ctxOr(cx);
	return ctx != nullptr ? foreignClassDef(ctx, OBJVAL(obj)) : nullptr;
}

namespace {

void reportIncompatible(JSContext* ctx, Object obj, ClassDef* def, Value* argv)
{
	std::string fn = "method";
	if (argv != nullptr && isObject(argv[-2]))
	{
		JSValue n = JS_GetPropertyStr(ctx, toJS(argv[-2]), "name");
		if (JS_IsString(n))  fn = toStdString(ctx, n);
		JS_FreeValue(ctx, n);
		if (JS_HasException(ctx))  JS_FreeValue(ctx, JS_GetException(ctx));
	}
	const ClassDef* actual = getClass(wrap(ctx), obj);
	const std::string msg = std::string(def->name != nullptr ? def->name : "?") + ".prototype." + fn +
	                        " called on incompatible " + (actual != nullptr && actual->name != nullptr ? actual->name : "Object");
	reportErrorImpl(ctx, msg.c_str());
}

} // namespace

bool instanceOf(Context cx, Object obj, ClassDef* def, Value* argv)
{
	JSContext* ctx = CX(cx);
	attach(def, ctx);
	const bool ok = obj != nullptr && getClass(cx, obj) == def;
	if (!ok && argv != nullptr && obj != nullptr)  reportIncompatible(ctx, obj, def, argv);
	return ok;
}

bool setPrivate(Context cx, Object obj, void* data)
{
	if (ObjRec* rec = recOf(OBJVAL(obj)))  { rec->priv = data; return true; }
	JSContext* ctx = ctxOr(cx);
	ContextState* cs = ctx != nullptr ? csOf(ctx) : nullptr;
	if (cs != nullptr && cs->globalDef != nullptr && obj == getGlobalObject(wrap(ctx)))  { cs->globalPrivate = data; return true; }
	return false;
}

void* getPrivate(Context cx, Object obj)
{
	if (obj == nullptr)  return nullptr;
	if (ObjRec* rec = recOf(OBJVAL(obj)))  return rec->priv;
	JSContext* ctx = ctxOr(cx);
	ContextState* cs = ctx != nullptr ? csOf(ctx) : nullptr;
	if (cs != nullptr && cs->globalDef != nullptr && obj == getGlobalObject(wrap(ctx)))  return cs->globalPrivate;
	return nullptr;
}

void* getInstancePrivate(Context cx, Object obj, ClassDef* def, Value* argv)
{
	return instanceOf(cx, obj, def, argv) ? getPrivate(cx, obj) : nullptr;
}

bool objectIsFunction(Context cx, Object obj)
{
	return obj != nullptr && JS_IsFunction(ctxOr(cx), OBJVAL(obj));
}

// MARK: Properties ---------------------------------------------------------------------------------

namespace {

bool getByAtom(JSContext* ctx, Object obj, JSAtom atom, Value* vp)
{
	JSValue v = JS_GetProperty(ctx, OBJVAL(obj), atom);
	if (JS_IsException(v))  { *vp = undefinedValue(); return false; }
	*vp = take(ctx, v);
	return true;
}

bool setByAtom(JSContext* ctx, Object obj, JSAtom atom, Value* vp)
{
	// DIVERGENCE: the engine's set throws on a read-only property where SpiderMonkey's non-strict
	// JS_SetProperty silently succeeds.
	return JS_SetProperty(ctx, OBJVAL(obj), atom, JS_DupValue(ctx, toJS(*vp))) >= 0;
}

// JS_LookupProperty: the value of a data property, true for an accessor, undefined when absent;
// runs resolve hooks but never getters.
bool lookupByAtom(JSContext* ctx, Object obj, JSAtom atom, Value* vp)
{
	JSValue p = JS_DupValue(ctx, OBJVAL(obj));
	*vp = undefinedValue();
	while (JS_IsObject(p))
	{
		JSPropertyDescriptor d;
		const int r = JS_GetOwnProperty(ctx, &d, p, atom);
		if (r < 0)  { JS_FreeValue(ctx, p); return false; }
		if (r > 0)
		{
			if (d.flags & JS_PROP_GETSET)  { *vp = trueValue(); freeDesc(ctx, &d); }
			else                           { *vp = take(ctx, d.value); JS_FreeValue(ctx, d.getter); JS_FreeValue(ctx, d.setter); }
			break;
		}
		JSValue next = JS_GetPrototype(ctx, p);
		JS_FreeValue(ctx, p);
		p = next;
	}
	JS_FreeValue(ctx, p);
	return true;
}

} // namespace

bool getProperty(Context cx, Object obj, const char* name, Value* vp)
{
	JSContext* ctx = CX(cx);
	AtomRef atom(ctx, JS_NewAtom(ctx, name));
	return getByAtom(ctx, obj, atom.atom, vp);
}

bool setProperty(Context cx, Object obj, const char* name, Value* vp)
{
	JSContext* ctx = CX(cx);
	AtomRef atom(ctx, JS_NewAtom(ctx, name));
	return setByAtom(ctx, obj, atom.atom, vp);
}

bool getPropertyById(Context cx, Object obj, PropertyId id, Value* vp)
{
	JSContext* ctx = CX(cx);
	AtomRef atom(ctx, atomFromId(ctx, id));
	return getByAtom(ctx, obj, atom.atom, vp);
}

bool setPropertyById(Context cx, Object obj, PropertyId id, Value* vp)
{
	JSContext* ctx = CX(cx);
	AtomRef atom(ctx, atomFromId(ctx, id));
	return setByAtom(ctx, obj, atom.atom, vp);
}

bool definePropertyById(Context cx, Object obj, PropertyId id, Value value,
                        PropertyGetter getter, PropertySetter setter, PropertyFlag flags)
{
	JSContext* ctx = CX(cx);
	AtomRef atom(ctx, atomFromId(ctx, id));
	return definePropertyImpl(ctx, OBJVAL(obj), atom.atom, toJS(value), getter, setter, flags);
}

bool defineProperty(Context cx, Object obj, const char* name, Value value,
                    PropertyGetter getter, PropertySetter setter, PropertyFlag flags)
{
	JSContext* ctx = CX(cx);
	AtomRef atom(ctx, JS_NewAtom(ctx, name));
	return definePropertyImpl(ctx, OBJVAL(obj), atom.atom, toJS(value), getter, setter, flags);
}

bool lookupProperty(Context cx, Object obj, const char* name, Value* vp)
{
	JSContext* ctx = CX(cx);
	AtomRef atom(ctx, JS_NewAtom(ctx, name));
	return lookupByAtom(ctx, obj, atom.atom, vp);
}

bool lookupPropertyById(Context cx, Object obj, PropertyId id, Value* vp)
{
	JSContext* ctx = CX(cx);
	AtomRef atom(ctx, atomFromId(ctx, id));
	return lookupByAtom(ctx, obj, atom.atom, vp);
}

bool hasProperty(Context cx, Object obj, const char* name, bool* found)
{
	JSContext* ctx = CX(cx);
	AtomRef atom(ctx, JS_NewAtom(ctx, name));
	const int r = JS_HasProperty(ctx, OBJVAL(obj), atom.atom);
	if (r < 0)  return false;
	*found = r != 0;
	return true;
}

bool deleteProperty(Context cx, Object obj, const char* name)
{
	// JS_DeleteProperty succeeds (without deleting) on a permanent property in non-strict code.
	JSContext* ctx = CX(cx);
	AtomRef atom(ctx, JS_NewAtom(ctx, name));
	return JS_DeleteProperty(ctx, OBJVAL(obj), atom.atom, 0) >= 0;
}

bool getMethodById(Context cx, Object obj, PropertyId id, Object* objp, Value* vp)
{
	if (objp != nullptr)  *objp = obj;
	return getPropertyById(cx, obj, id, vp);
}

bool defineProperties(Context cx, Object obj, const PropertySpec* ps)
{
	return definePropertySpecs(CX(cx), OBJVAL(obj), ps);
}

Function defineFunction(Context cx, Object obj, const char* name, NativeFn call, unsigned nargs, PropertyFlag flags)
{
	JSContext* ctx = CX(cx);
	JSValue f = defineNative(ctx, OBJVAL(obj), name, call, nargs, static_cast<std::uint8_t>(flags));
	if (JS_IsException(f))  return nullptr;
	return reinterpret_cast<Function>(takeObject(ctx, f));
}

bool defineFunctions(Context cx, Object obj, const FunctionSpec* fs)
{
	return defineFunctionSpecs(CX(cx), OBJVAL(obj), fs);
}

// MARK: Elements and arrays -------------------------------------------------------------------------

bool setElement(Context cx, Object obj, std::int32_t index, Value* vp)       { return setPropertyById(cx, obj, int32Id(index), vp); }
bool getElement(Context cx, Object obj, std::int32_t index, Value* vp)       { return getPropertyById(cx, obj, int32Id(index), vp); }
bool lookupElement(Context cx, Object obj, std::int32_t index, Value* vp)    { return lookupPropertyById(cx, obj, int32Id(index), vp); }

Object newArrayObject(Context cx, std::int32_t length, Value* vector)
{
	JSContext* ctx = CX(cx);
	JSValue arr;
	if (vector != nullptr && length > 0)
	{
		std::vector<JSValue> values(static_cast<std::size_t>(length));
		for (std::int32_t i = 0; i < length; ++i)  values[static_cast<std::size_t>(i)] = JS_DupValue(ctx, toJS(vector[i]));
		arr = JS_NewArrayFrom(ctx, length, values.data());   // takes the references
	}
	else
	{
		arr = JS_NewArray(ctx);
		if (!JS_IsException(arr) && length > 0 && JS_SetLength(ctx, arr, length) < 0)
		{
			JS_FreeValue(ctx, arr);
			return nullptr;
		}
	}
	if (JS_IsException(arr))  return nullptr;
	return takeObject(ctx, arr);
}

bool isArrayObject(Context /*cx*/, Object obj) { return obj != nullptr && JS_IsArray(OBJVAL(obj)); }

bool getArrayLength(Context cx, Object obj, std::uint32_t* length)
{
	std::int64_t n = 0;
	if (JS_GetLength(CX(cx), OBJVAL(obj), &n) < 0)  return false;
	*length = static_cast<std::uint32_t>(n);
	return true;
}

bool setArrayLength(Context cx, Object obj, std::uint32_t length)
{
	return JS_SetLength(CX(cx), OBJVAL(obj), length) >= 0;
}

// MARK: Enumeration ----------------------------------------------------------------------------------

IdArray* enumerate(Context cx, Object obj)
{
	JSContext* ctx = CX(cx);
	JSPropertyEnum* tab = nullptr;
	std::uint32_t len = 0;
	if (JS_GetOwnPropertyNames(ctx, &tab, &len, OBJVAL(obj), JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) < 0)  return nullptr;
	auto* out = new IdArray{};
	out->length = len;
	out->ids = new PropertyId[len > 0 ? len : 1];
	for (std::uint32_t i = 0; i < len; ++i)  out->ids[i] = idFromAtom(ctx, tab[i].atom);
	out->backend = nullptr;
	JS_FreePropertyEnum(ctx, tab, len);
	return out;
}

void destroyIdArray(Context /*cx*/, IdArray* ida)
{
	if (ida == nullptr)  return;
	delete[] ida->ids;
	delete ida;
}

// MARK: Functions ----------------------------------------------------------------------------------

String getFunctionId(Function fn)
{
	JSContext* ctx = gDefaultCtx;
	if (ctx == nullptr || fn == nullptr)  return nullptr;
	JSValue n = JS_GetPropertyStr(ctx, OBJVAL(reinterpret_cast<Object>(fn)), "name");
	if (JS_IsException(n))  { JS_FreeValue(ctx, JS_GetException(ctx)); return nullptr; }
	String s = takeString(ctx, n);
	if (s == nullptr)  return nullptr;
	std::size_t len = 0;
	stringChars(ctx, s, &len);
	return len > 0 ? s : nullptr;   // anonymous
}

Object getFunctionObject(Function fn) { return reinterpret_cast<Object>(fn); }

NativeFn getFunctionNative(Context /*cx*/, Function fn)
{
	if (fn == nullptr)  return nullptr;
	JSValue f = OBJVAL(reinterpret_cast<Object>(fn));
	if (JS_GetClassID(f) != gNativeClassId)  return nullptr;
	auto* rec = static_cast<NativeRec*>(JS_GetOpaque(f, gNativeClassId));
	return rec != nullptr ? rec->fn : nullptr;
}

bool callFunctionValue(Context cx, Object thisObj, Value fn, unsigned argc, Value* argv, Value* rval)
{
	JSContext* ctx = CX(cx);
	std::vector<JSValue> args(argc);
	for (unsigned i = 0; i < argc; ++i)  args[i] = toJS(argv[i]);
	JSValue r;
	{
		CallThisMark mark(OBJVAL_OR_NULL(thisObj));
		r = JS_Call(ctx, toJS(fn), OBJVAL_OR_NULL(thisObj), static_cast<int>(argc), args.data());
	}
	if (JS_IsException(r))
	{
		if (rval != nullptr)  *rval = undefinedValue();
		return finish(ctx, false);
	}
	if (rval != nullptr)  *rval = take(ctx, r);
	else                  JS_FreeValue(ctx, r);
	return true;
}

bool callFunctionName(Context cx, Object thisObj, const char* name, unsigned argc, Value* argv, Value* rval)
{
	JSContext* ctx = CX(cx);
	Value fn = undefinedValue();
	if (!getProperty(cx, thisObj, name, &fn))  return finish(ctx, false);
	return callFunctionValue(cx, thisObj, fn, argc, argv, rval);
}

// MARK: Script evaluation ---------------------------------------------------------------------------

bool evaluateScript(Context cx, Object scope, const char* src, unsigned length, const char* filename, unsigned lineno, Value* rval)
{
	return evalWithThis(CX(cx), scope, std::string(src, length), filename, lineno, rval);
}

bool evaluateUCScript(Context cx, Object scope, const Char16* src, unsigned length, const char* filename, unsigned lineno, Value* rval)
{
	return evalWithThis(CX(cx), scope, toUtf8(src, length), filename, lineno, rval);
}

// MARK: Scripts -----------------------------------------------------------------------------

Script compileUCScript(Context cx, Object scope, const Char16* src, unsigned length, const char* filename, unsigned lineno)
{
	JSContext* ctx = CX(cx);
	auto* s = new ScriptRep();
	s->rt = JS_GetRuntime(ctx);
	s->source = toUtf8(src, length);
	s->filename = filename != nullptr ? filename : "";
	s->lineno = lineno != 0 ? static_cast<int>(lineno) : 1;
	JSValue global = JS_GetGlobalObject(ctx);
	JSEvalOptions o = evalOptions(s->filename.c_str(), static_cast<unsigned>(s->lineno), JS_EVAL_FLAG_COMPILE_ONLY);
	s->bytecode = JS_EvalThis2(ctx, scope != nullptr ? OBJVAL(scope) : global, s->source.c_str(), s->source.size(), &o);
	JS_FreeValue(ctx, global);
	if (JS_IsException(s->bytecode))
	{
		delete s;
		finish(ctx, false);
		return nullptr;
	}
	return s;
}

Object newScriptObject(Context cx, Script script)
{
	JSContext* ctx = CX(cx);
	if (script == nullptr)  return nullptr;
	JSValue o = JS_NewObjectClass(ctx, gScriptClassId);
	if (JS_IsException(o))  return nullptr;
	++script->refs;
	JS_SetOpaque(o, script);
	return takeObject(ctx, o);
}

bool executeScript(Context cx, Object obj, Script script, Value* rval)
{
	JSContext* ctx = CX(cx);
	if (script == nullptr)  return false;
	Object global = getGlobalObject(cx);
	if (obj != nullptr && obj != global)
	{
		// QuickJS-ng runs precompiled global code only with the global object as `this`.
		return evalWithThis(ctx, obj, script->source, script->filename.c_str(), static_cast<unsigned>(script->lineno), rval);
	}
	JSValue r = JS_EvalFunction(ctx, JS_DupValue(ctx, script->bytecode));
	if (JS_IsException(r))
	{
		if (rval != nullptr)  *rval = undefinedValue();
		return finish(ctx, false);
	}
	if (rval != nullptr)  *rval = take(ctx, r);
	else                  JS_FreeValue(ctx, r);
	return true;
}

void destroyScript(Context cx, Script script)
{
	releaseScript(cx != nullptr ? JS_GetRuntime(CX(cx)) : nullptr, script);
}

bool serializeScript(Context cx, Script script, ByteBuffer* out)
{
	out->data = nullptr;
	out->length = 0;
	if (script == nullptr)  return false;
	JSContext* ctx = CX(cx);
	std::size_t bcLen = 0;
	std::uint8_t* bc = JS_WriteObject(ctx, &bcLen, script->bytecode, JS_WRITE_OBJ_BYTECODE);
	if (bc == nullptr)  return false;
	std::vector<std::uint8_t> blob(kScriptMagic, kScriptMagic + sizeof kScriptMagic);
	writeU32(blob, static_cast<std::uint32_t>(script->lineno));
	writeU32(blob, static_cast<std::uint32_t>(script->filename.size()));
	blob.insert(blob.end(), script->filename.begin(), script->filename.end());
	writeU32(blob, static_cast<std::uint32_t>(script->source.size()));
	blob.insert(blob.end(), script->source.begin(), script->source.end());
	writeU32(blob, static_cast<std::uint32_t>(bcLen));
	blob.insert(blob.end(), bc, bc + bcLen);
	js_free(ctx, bc);
	auto* data = static_cast<std::uint8_t*>(std::malloc(blob.size()));
	if (data == nullptr)  return false;
	std::memcpy(data, blob.data(), blob.size());
	out->data = data;
	out->length = blob.size();
	return true;
}

Script deserializeScript(Context cx, const std::uint8_t* data, std::size_t length)
{
	JSContext* ctx = CX(cx);
	if (data == nullptr || length < sizeof kScriptMagic || std::memcmp(data, kScriptMagic, sizeof kScriptMagic) != 0)  return nullptr;
	const std::uint8_t* p = data + sizeof kScriptMagic;
	const std::uint8_t* end = data + length;
	std::uint32_t line = 0, fnLen = 0, srcLen = 0, bcLen = 0;
	if (!readU32(p, end, &line) || !readU32(p, end, &fnLen) || static_cast<std::size_t>(end - p) < fnLen)  return nullptr;
	std::string filename(reinterpret_cast<const char*>(p), fnLen);
	p += fnLen;
	if (!readU32(p, end, &srcLen) || static_cast<std::size_t>(end - p) < srcLen)  return nullptr;
	std::string source(reinterpret_cast<const char*>(p), srcLen);
	p += srcLen;
	if (!readU32(p, end, &bcLen) || static_cast<std::size_t>(end - p) < bcLen)  return nullptr;
	JSValue bc = JS_ReadObject(ctx, p, bcLen, JS_READ_OBJ_BYTECODE);
	if (JS_IsException(bc))  { finish(ctx, false); return nullptr; }
	auto* s = new ScriptRep();
	s->rt = JS_GetRuntime(ctx);
	s->source = std::move(source);
	s->filename = std::move(filename);
	s->lineno = static_cast<int>(line);
	s->bytecode = bc;
	return s;
}

void destroyByteBuffer(ByteBuffer* buf)
{
	if (buf == nullptr)  return;
	std::free(buf->data);
	buf->data = nullptr;
	buf->length = 0;
}

// MARK: Strings ---------------------------------------------------------------------------------

namespace {

// Keeps an interned string for the runtime's life (SpiderMonkey never collects ATOM_INTERNED).
String keepInterned(JSContext* ctx, JSAtom atom)
{
	if (atom == JS_ATOM_NULL)  return nullptr;
	JSValue v = JS_AtomToString(ctx, atom);
	JS_FreeAtom(ctx, atom);
	if (!JS_IsString(v))  { JS_FreeValue(ctx, v); return nullptr; }
	RuntimeState* rs = rsOf(ctx);
	void* p = JS_VALUE_GET_PTR(v);
	if (!rs->permanentStrings.insert(p).second)  JS_FreeValue(ctx, v);   // already held once
	return static_cast<String>(p);
}

} // namespace

String internString(Context cx, const char* s)
{
	JSContext* ctx = CX(cx);
	return keepInterned(ctx, JS_NewAtom(ctx, s));
}

String internUCStringN(Context cx, const Char16* s, std::size_t n)
{
	JSContext* ctx = CX(cx);
	JSValue v = JS_NewStringUTF16(ctx, reinterpret_cast<const std::uint16_t*>(s), n);
	if (JS_IsException(v))  return nullptr;
	const JSAtom atom = JS_ValueToAtom(ctx, v);
	JS_FreeValue(ctx, v);
	return keepInterned(ctx, atom);
}

String newStringCopyZ(Context cx, const char* s)
{
	JSContext* ctx = CX(cx);
	return takeString(ctx, JS_NewStringLen(ctx, s, std::strlen(s)));
}

String newStringCopyN(Context cx, const char* s, std::size_t n)
{
	JSContext* ctx = CX(cx);
	return takeString(ctx, JS_NewStringLen(ctx, s, n));
}

String newUCStringCopyN(Context cx, const Char16* s, std::size_t n)
{
	JSContext* ctx = CX(cx);
	return takeString(ctx, JS_NewStringUTF16(ctx, reinterpret_cast<const std::uint16_t*>(s), n));
}

Value emptyStringValue(Context cx)
{
	JSContext* ctx = CX(cx);
	return take(ctx, JS_NewStringLen(ctx, "", 0));
}

std::size_t getStringLength(String str)
{
	std::size_t len = 0;
	stringChars(gDefaultCtx, str, &len);
	return len;
}

const Char16* getStringCharsAndLength(Context cx, String str, std::size_t* length)
{
	return stringChars(ctxOr(cx), str, length);
}

const Char16* getInternedStringChars(String str)
{
	return stringChars(gDefaultCtx, str, nullptr);
}

bool stringEqualsAscii(Context cx, String str, const char* ascii, bool* match)
{
	std::size_t len = 0;
	const Char16* chars = stringChars(ctxOr(cx), str, &len);
	if (chars == nullptr && len != 0)  return false;
	bool eq = std::strlen(ascii) == len;
	for (std::size_t i = 0; eq && i < len; ++i)  eq = chars[i] == static_cast<unsigned char>(ascii[i]);
	*match = eq;
	return true;
}

bool stringHasBeenInterned(Context cx, String str)
{
	JSContext* ctx = ctxOr(cx);
	if (ctx == nullptr || str == nullptr)  return false;
	RuntimeState* rs = rsOf(ctx);
	return rs->permanentStrings.count(str) != 0 || rs->internedStrings.count(str) != 0;
}

void setCStringsAreUTF8() {}   // QuickJS-ng always reads C strings as UTF-8

// MARK: Regular expressions -----------------------------------------------------------------

Object newUCRegExpObjectNoStatics(Context cx, const Char16* chars, std::size_t length, std::uint32_t flags)
{
	// SpiderMonkey 1.8.5 regexp flag bits: JSREG_FOLD 1, JSREG_GLOB 2, JSREG_MULTILINE 4, JSREG_STICKY 8.
	// QuickJS-ng has no RegExp statics at all, so every RegExp is a "no statics" one.
	JSContext* ctx = CX(cx);
	std::string f;
	if (flags & 0x2)  f += 'g';
	if (flags & 0x1)  f += 'i';
	if (flags & 0x4)  f += 'm';
	if (flags & 0x8)  f += 'y';
	JSValue global = JS_GetGlobalObject(ctx);
	JSValue ctor = JS_GetPropertyStr(ctx, global, "RegExp");
	JS_FreeValue(ctx, global);
	JSValue args[2] = { JS_NewStringUTF16(ctx, reinterpret_cast<const std::uint16_t*>(chars), length), JS_NewStringLen(ctx, f.c_str(), f.size()) };
	JSValue re = JS_CallConstructor(ctx, ctor, 2, args);
	JS_FreeValue(ctx, args[0]);
	JS_FreeValue(ctx, args[1]);
	JS_FreeValue(ctx, ctor);
	if (JS_IsException(re))  return nullptr;
	return takeObject(ctx, re);
}

// MARK: Exceptions and error reporting ----------------------------------------------------------
//
// QuickJS-ng keeps one pending exception per runtime; JS_GetException both reads AND clears it,
// so a read re-arms it with JS_Throw straight away.

bool isExceptionPending(Context cx)  { return JS_HasException(CX(cx)); }

bool getPendingException(Context cx, Value* vp)
{
	JSContext* ctx = CX(cx);
	if (!JS_HasException(ctx))  return false;
	JSValue exc = JS_GetException(ctx);   // clears the pending slot; we now own exc
	*vp = fromJS(ctx, exc);
	JS_Throw(ctx, exc);                   // re-arm: consumes our ownership, restores pending state
	return true;
}

void setPendingException(Context cx, Value v)
{
	JSContext* ctx = CX(cx);
	JS_Throw(ctx, JS_DupValue(ctx, toJS(v)));
}

void clearPendingException(Context cx)
{
	JSContext* ctx = CX(cx);
	if (JS_HasException(ctx))  JS_FreeValue(ctx, JS_GetException(ctx));
}

bool reportPendingException(Context cx) { return reportPendingImpl(CX(cx)); }

void reportError(Context cx, const char* message) { reportErrorImpl(CX(cx), message); }

bool reportWarning(Context cx, const char* message)
{
	// Warnings never become exceptions (js_ErrorToException ignores them).
	JSContext* ctx = CX(cx);
	std::string file;
	unsigned line = 0;
	currentLocation(ctx, &file, &line);
	const std::u16string uc = utf8ToU16(message);
	invokeReporter(ctx, message, static_cast<unsigned>(ReportFlag::Warning), &file, line, &uc);
	return true;
}

void reportOutOfMemory(Context cx)
{
	// js_ReportOutOfMemory: clear any pending exception and report; nothing is left pending, so a
	// native returning false after this aborts the script uncatchably.
	JSContext* ctx = CX(cx);
	if (JS_HasException(ctx))  JS_FreeValue(ctx, JS_GetException(ctx));
	const std::u16string uc = u"out of memory";
	invokeReporter(ctx, "out of memory", static_cast<unsigned>(ReportFlag::Error), nullptr, 0, &uc);
}

ErrorReporter setErrorReporter(Context cx, ErrorReporter reporter)
{
	ContextState* cs = csOf(CX(cx));
	if (cs == nullptr)  return nullptr;
	ErrorReporter old = cs->reporter;
	cs->reporter = reporter;
	return old;
}

ExceptionState* saveExceptionState(Context cx)
{
	JSContext* ctx = CX(cx);
	auto* st = new ExceptionState();
	if (JS_HasException(ctx))
	{
		st->hadException = true;
		st->value = JS_GetException(ctx);   // clears pending; the snapshot now owns this ref
	}
	return st;
}

void restoreExceptionState(Context cx, ExceptionState* state)
{
	JSContext* ctx = CX(cx);
	if (state == nullptr)  return;
	if (JS_HasException(ctx))  JS_FreeValue(ctx, JS_GetException(ctx));
	if (state->hadException)  JS_Throw(ctx, state->value);   // consumes the snapshot's owned ref
	delete state;
}

void dropExceptionState(Context cx, ExceptionState* state)
{
	if (state == nullptr)  return;
	if (state->hadException)  JS_FreeValue(CX(cx), state->value);
	delete state;
}

// MARK: GC roots ----------------------------------------------------------------------------
//
// A root is an address; flushArena() reads it when it runs (see the banner). Adding a root also
// takes an arena reference to the value there now, so a value rooted straight after it was
// created stays alive even if the arena it came in on is flushed before the root is first read.

namespace {

bool addRoot(Context cx, void* addr, RootSlot kind, JSValueConst current)
{
	if (addr == nullptr)  return false;
	JSContext* ctx = CX(cx);
	RuntimeState* rs = rsOf(ctx);
	rs->roots[addr] = kind;
	if (JS_VALUE_HAS_REF_COUNT(current))  rs->arena.push_back(JS_DupValue(ctx, current));
	return true;
}

bool removeRoot(Context cx, void* addr)
{
	return rsOf(CX(cx))->roots.erase(addr) != 0;
}

} // namespace

bool addNamedObjectRoot(Context cx, Object* rp, const char* /*name*/)
{
	return addRoot(cx, rp, RootSlot::Object, (rp != nullptr && *rp != nullptr) ? OBJVAL(*rp) : JS_NULL);
}
bool addNamedValueRoot(Context cx, Value* vp, const char* /*name*/)
{
	return addRoot(cx, vp, RootSlot::Value, vp != nullptr ? toJS(*vp) : JS_UNDEFINED);
}
bool addNamedStringRoot(Context cx, String* sp, const char* /*name*/)
{
	return addRoot(cx, sp, RootSlot::String, (sp != nullptr && *sp != nullptr) ? STRVAL(*sp) : JS_UNDEFINED);
}
bool removeObjectRoot(Context cx, Object* rp)  { return removeRoot(cx, rp); }
bool removeValueRoot(Context cx, Value* vp)    { return removeRoot(cx, vp); }
bool removeStringRoot(Context cx, String* sp)  { return removeRoot(cx, sp); }

// MARK: Runtime, contexts -------------------------------------------------------------------------

Runtime newRuntime(std::uint32_t maxBytes)
{
	JSRuntime* rt = JS_NewRuntime();
	if (rt == nullptr)  return nullptr;
	auto* rs = new RuntimeState();
	rs->rt = rt;
	rs->maxBytes = maxBytes;
	JS_SetRuntimeOpaque(rt, rs);
	if (maxBytes != 0)  JS_SetMemoryLimit(rt, maxBytes);
	JS_SetInterruptHandler(rt, InterruptTramp, rs);

	if (gNativeClassId == 0)  gNativeClassId = allocClassId();
	if (gScriptClassId == 0)  gScriptClassId = allocClassId();
	JSClassDef native{};
	native.class_name = "Function";
	native.finalizer  = NativeFinalizer;
	native.call       = NativeCallTramp;
	JS_NewClass(rt, gNativeClassId, &native);
	JSClassDef script{};
	script.class_name = "Script";
	script.finalizer  = ScriptObjectFinalizer;
	JS_NewClass(rt, gScriptClassId, &script);
	if (gScopeFallbackClassId == 0)  gScopeFallbackClassId = allocClassId();
	JSClassDef fallback{};
	fallback.class_name = "Object";
	fallback.exotic     = &gScopeFallbackExotic;
	JS_NewClass(rt, gScopeFallbackClassId, &fallback);
	return wrap(rt);
}

void destroyRuntime(Runtime rt)
{
	JSRuntime* jrt = RT(rt);
	RuntimeState* rs = rsOf(jrt);
	if (rs != nullptr)
	{
		rs->roots.clear();
		releaseScopes(jrt);
		for (auto& e : gSharedPermanent)
		{
			for (SharedPermanent& sp : e.second)  JS_FreeAtomRT(jrt, sp.atom);
		}
		gSharedPermanent.clear();
		flushArena(rs, false);
		for (auto& c : rs->chars)  JS_FreeCStringRT_UTF16(jrt, c.second.p);
		rs->chars.clear();
		for (void* s : rs->permanentStrings)  JS_FreeValueRT(jrt, JS_MKPTR(JS_TAG_STRING, s));
		rs->permanentStrings.clear();
	}
	// Erase after freeing: JS_FreeRuntime runs the pending finalizers, and FinalizeTramp looks up
	// gCtxForRuntime (already erased by destroyContext() when the context went first, bead oo-902s).
	JS_FreeRuntime(jrt);
	gCtxForRuntime.erase(jrt);
	delete rs;
}

void shutDown() {}

Context newContext(Runtime rt, std::size_t /*stackChunkSize*/)
{
	JSRuntime* jrt = RT(rt);
	JSContext* ctx = JS_NewContext(jrt);
	if (ctx == nullptr)  return nullptr;
	RuntimeState* rs = rsOf(jrt);
	auto* cs = new ContextState();
	cs->ctx = ctx;
	cs->rs = rs;
	JSValue tmp = JS_NewObject(ctx);
	cs->objectProto = JS_GetPrototype(ctx, tmp);
	JS_FreeValue(ctx, tmp);
	gContexts[ctx] = cs;
	rs->contexts.push_back(cs);
	gCtxForRuntime[jrt] = ctx;
	gDefaultCtx = ctx;
	installScopeFallback(ctx);
	if (gContextCallbackHook != nullptr)  gContextCallbackHook(wrap(ctx), ContextOp::New);
	return wrap(ctx);
}

void destroyContext(Context cx)
{
	JSContext* ctx = CX(cx);
	if (gContextCallbackHook != nullptr)  gContextCallbackHook(cx, ContextOp::Destroy);
	ContextState* cs = csOf(ctx);
	RuntimeState* rs = rsOf(ctx);
	if (cs != nullptr)
	{
		rs->contexts.erase(std::remove(rs->contexts.begin(), rs->contexts.end(), cs), rs->contexts.end());
		if (rs->contexts.empty())
		{
			// The last context: nothing can read a root again, so release everything. (With other
			// contexts still alive the arena is left for the next gc(): the caller may be holding
			// unrooted handles, which SpiderMonkey's conservative scan would have kept.)
			rs->roots.clear();
			releaseScopes(JS_GetRuntime(ctx));
			flushArena(rs, false);
		}
		for (JSValue v : cs->held)  JS_FreeValue(ctx, v);
		JS_FreeValue(ctx, cs->objectProto);
		gContexts.erase(ctx);
		delete cs;
	}

	// Erase gCtxForRuntime's entry for this context (bead oo-902s) before freeing it, so a
	// finalizer that runs later (QuickJS-ng finalizes cycles lazily, in JS_FreeRuntime) sees no
	// context rather than this dangling one.
	JSRuntime* jrt = JS_GetRuntime(ctx);
	auto it = gCtxForRuntime.find(jrt);
	if (it != gCtxForRuntime.end() && it->second == ctx)
	{
		if (!rs->contexts.empty())  it->second = rs->contexts.back()->ctx;
		else                        gCtxForRuntime.erase(it);
	}
	if (gDefaultCtx == ctx)  gDefaultCtx = gContexts.empty() ? nullptr : gContexts.begin()->first;

	JS_FreeContext(ctx);
}

Runtime getRuntime(Context cx)                 { return wrap(JS_GetRuntime(CX(cx))); }
void*   getContextPrivate(Context cx)          { return JS_GetContextOpaque(CX(cx)); }
void    setContextPrivate(Context cx, void* d) { JS_SetContextOpaque(CX(cx), d); }

// MARK: Requests ------------------------------------------------------------------------------------

void beginRequest(Context cx)
{
	if (ContextState* cs = csOf(CX(cx)))  ++cs->requestDepth;
}

void endRequest(Context cx)
{
	if (ContextState* cs = csOf(CX(cx)))  { if (cs->requestDepth > 0) --cs->requestDepth; }
}

bool isInRequest(Context cx)
{
	ContextState* cs = csOf(CX(cx));
	return cs != nullptr && cs->requestDepth > 0;
}

bool isThreadsafeBuild() { return false; }   // QuickJS-ng runtimes are single-threaded; requests are bookkeeping

// MARK: Options and versions ------------------------------------------------------------------------

ContextOption setOptions(Context cx, ContextOption options)
{
	ContextState* cs = csOf(CX(cx));
	if (cs == nullptr)  return ContextOption::None;
	const ContextOption old = cs->options;
	cs->options = options;
	return old;
}

ContextOption getOptions(Context cx)
{
	ContextState* cs = csOf(CX(cx));
	return cs != nullptr ? cs->options : ContextOption::None;
}

Version setVersion(Context cx, Version v)
{
	ContextState* cs = csOf(CX(cx));
	if (cs == nullptr)  return Version::Unknown;
	const Version old = cs->version;
	cs->version = v;
	return old;
}

Version getVersion(Context cx)
{
	ContextState* cs = csOf(CX(cx));
	return cs != nullptr ? cs->version : Version::Unknown;
}

const char* versionToString(Version v)
{
	switch (v)
	{
		case Version::Default: return "default";
		case Version::ECMA5:   return "ECMAv5";
		case Version::Latest:  return "ECMAv5";   // JSVERSION_LATEST is ECMA_5 in 1.8.5
		case Version::Unknown: return "unknown";
	}
	return "unknown";
}

// MARK: Garbage collection ----------------------------------------------------------------------------

std::uint32_t getGCParameter(Runtime rt, GCParam key)
{
	RuntimeState* rs = rsOf(RT(rt));
	switch (key)
	{
		case GCParam::MaxBytes:       return rs->maxBytes;
		case GCParam::MaxMallocBytes: return rs->maxMallocBytes;
		case GCParam::Bytes:
		{
			JSMemoryUsage u{};
			JS_ComputeMemoryUsage(RT(rt), &u);
			const std::int64_t b = u.malloc_size;
			return b < 0 ? 0 : (b > static_cast<std::int64_t>(std::numeric_limits<std::uint32_t>::max()) ? std::numeric_limits<std::uint32_t>::max() : static_cast<std::uint32_t>(b));
		}
		case GCParam::NumberOfGCs:    return rs->gcCount;
	}
	return 0;
}

void setGCParameter(Runtime rt, GCParam key, std::uint32_t value)
{
	RuntimeState* rs = rsOf(RT(rt));
	switch (key)
	{
		case GCParam::MaxBytes:       rs->maxBytes = value; JS_SetMemoryLimit(RT(rt), value); break;
		case GCParam::MaxMallocBytes: rs->maxMallocBytes = value; JS_SetGCThreshold(RT(rt), value); break;
		case GCParam::Bytes:          break;   // read-only in SpiderMonkey too
		case GCParam::NumberOfGCs:    break;
	}
}

void gc(Context cx)
{
	JSContext* ctx = CX(cx);
	RuntimeState* rs = rsOf(ctx);
	if (canFlush(rs))  flushArena(rs, true);
	JS_RunGC(JS_GetRuntime(ctx));
	++rs->gcCount;
}

void maybeGC(Context cx)
{
	// QuickJS-ng schedules its own cycle collection on allocation; what only the façade can do is
	// drop the arena's references, which frees every acyclic unreachable value immediately.
	RuntimeState* rs = rsOf(CX(cx));
	if (canFlush(rs))  flushArena(rs, true);
}

void setGCZeal(Context /*cx*/, std::uint8_t /*zeal*/) {}
bool gcZealSupported() { return false; }

// MARK: Operation callback ------------------------------------------------------------------------------

OperationCallback setOperationCallback(Context cx, OperationCallback cb)
{
	ContextState* cs = csOf(CX(cx));
	if (cs == nullptr)  return nullptr;
	OperationCallback old = cs->opcb;
	cs->opcb = cb;
	return old;
}

void triggerOperationCallback(Context cx)
{
	if (ContextState* cs = csOf(CX(cx)))  cs->triggered.store(true);
}

void triggerAllOperationCallbacks(Runtime rt)
{
	RuntimeState* rs = rsOf(RT(rt));
	for (ContextState* cs : rs->contexts)  cs->triggered.store(true);
}

// MARK: Completing the retarget (bead oo-1gc.3) -------------------------------------------------

// QuickJS-ng has no threads to hand a request to, so a suspension is a no-op token.
unsigned suspendRequest(Context)                           { return 0; }
void     resumeRequest(Context, unsigned)                  { }

bool compareStrings(Context cx, String a, String b, std::int32_t* result)
{
	// SpiderMonkey compares UTF-16 code units lexicographically and returns their difference's sign.
	JSContext* ctx = CX(cx);
	const std::u16string sa = toU16(ctx, toJS(stringValue(a)));
	const std::u16string sb = toU16(ctx, toJS(stringValue(b)));
	const int c = sa.compare(sb);
	*result = c < 0 ? -1 : (c > 0 ? 1 : 0);
	return true;
}

bool freezeObject(Context cx, Object obj)
{
	JSContext* ctx = CX(cx);
	JSValue global = JS_GetGlobalObject(ctx);
	JSValue objectCtor = JS_GetPropertyStr(ctx, global, "Object");
	JSValue freeze = JS_GetPropertyStr(ctx, objectCtor, "freeze");
	JSValue arg = OBJVAL(obj);
	JSValue r = JS_Call(ctx, freeze, objectCtor, 1, &arg);
	const bool ok = !JS_IsException(r);
	JS_FreeValue(ctx, r);
	JS_FreeValue(ctx, freeze);
	JS_FreeValue(ctx, objectCtor);
	JS_FreeValue(ctx, global);
	return ok ? true : finish(ctx, false);
}

Function compileUCFunction(Context cx, Object scope, const char* name, unsigned nargs, const char** argnames,
                           const Char16* chars, std::size_t length, const char* filename, unsigned lineno)
{
	// The engine compiles a function from a body and a parameter list. The same source text is
	// built here as one parenthesised function expression whose body starts on a new line, so the
	// body's line numbers are the caller's `lineno` exactly (the header line is lineno - 1).
	std::string src = "(function ";
	if (name != nullptr)  src += name;
	src += "(";
	for (unsigned i = 0; i < nargs; ++i)
	{
		if (i != 0)  src += ", ";
		src += argnames[i];
	}
	src += ") {\n";
	src += toUtf8(chars, length);
	src += "\n})";
	Value fv = undefinedValue();
	const unsigned headerLine = lineno > 1 ? lineno - 1 : 1;
	if (!evalWithThis(CX(cx), scope, src, filename, headerLine, &fv))  return nullptr;
	if (!isObject(fv))  return nullptr;
	return reinterpret_cast<Function>(toObject(fv));
}

bool callFunction(Context cx, Object thisObj, Function fn, unsigned argc, Value* argv, Value* rval)
{
	return callFunctionValue(cx, thisObj, objectValue(reinterpret_cast<Object>(fn)), argc, argv, rval);
}

bool bufferIsCompilableUnit(Context cx, Object obj, const char* bytes, std::size_t length)
{
	// "Would more input help?" SpiderMonkey answers false only when compilation fails because the
	// text ended early; any other outcome (success, or a different syntax error) is a unit.
	JSContext* ctx = CX(cx);
	JSValue global = JS_GetGlobalObject(ctx);
	JSEvalOptions o = evalOptions("typein", 1, JS_EVAL_FLAG_COMPILE_ONLY);
	const std::string src(bytes, length);
	JSValue r = JS_EvalThis2(ctx, obj != nullptr ? OBJVAL(obj) : global, src.c_str(), src.size(), &o);
	JS_FreeValue(ctx, global);
	if (!JS_IsException(r))  { JS_FreeValue(ctx, r); return true; }
	JSValue e = JS_GetException(ctx);
	JSValue m = JS_IsObject(e) ? JS_GetPropertyStr(ctx, e, "message") : JS_UNDEFINED;
	const std::string msg = JS_IsString(m) ? toStdString(ctx, m) : std::string();
	JS_FreeValue(ctx, m);
	JS_FreeValue(ctx, e);
	return msg.find("end of") == std::string::npos && msg.find("unexpected end") == std::string::npos
	    && msg.find("expecting") == std::string::npos;
}

// MARK: Debugging and profiling -----------------------------------------------------------------
//
// QuickJS-ng exposes no frame objects; the stack it can describe is the one an Error records. A
// walk therefore snapshots `new Error().stack` when it starts and hands out 1-based indices into
// that snapshot. Frames carry a filename and line only: no `this`, no scope chain, no variables,
// and the debugger/profiler hooks have nothing to attach to. These are diagnostics only
// (JSEngine.hpp: nothing here may affect what a golden observes).

namespace {
struct FrameSnapshot
{
	struct Frame { std::string file; unsigned line; };
	std::vector<Frame> frames;
};
std::unordered_map<JSContext*, FrameSnapshot>& gFrames = *new std::unordered_map<JSContext*, FrameSnapshot>;
std::unordered_map<std::string, ScriptRep*>&   gFrameScripts = *new std::unordered_map<std::string, ScriptRep*>;   // one stable Script token per filename
DebuggerHandler gDebuggerHandler = nullptr;

void snapshotFrames(JSContext* ctx)
{
	FrameSnapshot& snap = gFrames[ctx];
	snap.frames.clear();
	JSValue e = JS_NewError(ctx);
	if (JS_IsException(e))  { JS_FreeValue(ctx, JS_GetException(ctx)); return; }
	JSValue st = JS_GetPropertyStr(ctx, e, "stack");
	const std::string stack = JS_IsString(st) ? toStdString(ctx, st) : std::string();
	JS_FreeValue(ctx, st);
	JS_FreeValue(ctx, e);
	std::size_t pos = 0;
	while (pos < stack.size())
	{
		std::size_t end = stack.find('\n', pos);
		if (end == std::string::npos)  end = stack.size();
		std::string file;
		unsigned line = 0;
		if (parseLocation(stack.substr(pos, end - pos), &file, &line))  snap.frames.push_back({ file, line });
		pos = end + 1;
	}
}

const FrameSnapshot::Frame* frameAt(JSContext* ctx, StackFrame fp)
{
	const auto it = gFrames.find(ctx);
	const std::size_t i = reinterpret_cast<std::uintptr_t>(fp);
	if (it == gFrames.end() || i == 0 || i > it->second.frames.size())  return nullptr;
	return &it->second.frames[i - 1];
}
}

StackFrame frameIterator(Context cx, StackFrame* iter)
{
	JSContext* ctx = CX(cx);
	std::uintptr_t i = reinterpret_cast<std::uintptr_t>(*iter);
	if (i == 0)  snapshotFrames(ctx);
	++i;
	if (i > gFrames[ctx].frames.size())  { *iter = nullptr; return nullptr; }
	*iter = reinterpret_cast<StackFrame>(i);
	return *iter;
}
bool frameIsScript(Context cx, StackFrame fp)             { return frameAt(CX(cx), fp) != nullptr; }
bool frameIsConstructor(Context, StackFrame)              { return false; }
bool frameIsDebugger(Context, StackFrame)                 { return false; }
Script frameScript(Context cx, StackFrame fp)
{
	const FrameSnapshot::Frame* f = frameAt(CX(cx), fp);
	if (f == nullptr)  return nullptr;
	ScriptRep*& token = gFrameScripts[f->file];
	if (token == nullptr)
	{
		token = new ScriptRep();   // never compiled and never freed: an identity for the filename
		token->filename = f->file;
	}
	return token;
}
const char* scriptFilename(Context, Script script)       { return script != nullptr ? script->filename.c_str() : nullptr; }
unsigned frameLineNumber(Context cx, StackFrame fp)
{
	const FrameSnapshot::Frame* f = frameAt(CX(cx), fp);
	return f != nullptr ? f->line : 0;
}
Function frameFunction(Context, StackFrame)               { return nullptr; }
bool     frameThis(Context, StackFrame, Value*)           { return false; }
Object   frameScopeChain(Context, StackFrame)             { return nullptr; }

bool getScopeVariables(Context, Object, VariableList* out)
{
	out->length = 0; out->vars = nullptr; out->backend = nullptr;
	return false;
}
void destroyScopeVariables(Context, VariableList*)        { }

void setDebuggerHandler(Runtime, DebuggerHandler handler, void*)   { gDebuggerHandler = handler; }
bool setFunctionCallback(Context, FunctionCallback)       { return false; }
ContextCallback setContextCallback(Runtime, ContextCallback cb)
{
	ContextCallback old = gContextCallbackHook;
	gContextCallbackHook = cb;
	return old;
}

bool dumpNamedRoots(Runtime, RootDumper, void*)           { return false; }
bool dumpHeap(Context cx, void* file)
{
	JSMemoryUsage u;
	JS_ComputeMemoryUsage(JS_GetRuntime(CX(cx)), &u);
	JS_DumpMemoryUsage(static_cast<FILE*>(file), &u, JS_GetRuntime(CX(cx)));
	return true;
}

// MARK: Backend identity ----------------------------------------------------------------------

// The pre-existing unit test pins this exact string (the engine and its vendored version).
const char* backendName() { return "quickjs-ng-0.16.2"; }

// MARK: Test-only glue (not part of the façade) ------------------------------------------------
//
// A per-class (name -> tinyid) table consulted by get_own_property/get_own_property_names so the
// resolve/enumerate hooks can be exercised with int ids before initClass existed (bead oo-0kq's
// unit test). initClass does not use it.

void registerResolvableProperty(Context cx, ClassDef* def, const char* name, std::int32_t tinyid)
{
	BackendClass* bc = attach(def, CX(cx));
	if (bc != nullptr)  bc->tinyidProps.emplace_back(name, tinyid);
}

} // namespace ooscript
