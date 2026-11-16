/*

OOJSScript+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056; bead oo-u61e.4): the Objective-C OOJSScript, a facade over the C++
cxx::OOJSScript (OOJSScript.h), and a subclass of the OOScript facade (OOScript+ObjCBridge.h),
whose ivar holds the C++ object. Its interface is the one OOJSScript.h declared before the
conversion, copied exactly but for the ivars (same selectors, same types, same superclass and
protocol), so its callers compile and behave unchanged. Imported as the last line of
OOJSScript.h; do not import it directly.

The facade is the script's identity, as amendment oo-3kqi's is: the script's JS object holds a
weak reference to it, the stack of running scripts holds it, and so do the weak references other
objects keep. So it makes and owns its C++ object (-initWithPath:properties:), and oo::ToObjC
answers it while it lives; converted code does not make a cxx::OOJSScript. The category
OOScript (JavaScriptEvents), which every script answers, moved here from OOJSScript.h.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  --------------------------
        still Objective-C                      OOJSScript *                    nothing: messages as before
        converted (C++)                        ::OOJSScript * (the identity)   oo::ToCxx(script)->...
          inside a member of cxx::OOJSScript                                   oo::ToObjC(this)

Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once no file outside OOJSScript.* names the Objective-C class.

*/

#ifndef OOJSSCRIPT_OBJCBRIDGE_H
#define OOJSSCRIPT_OBJCBRIDGE_H

@interface OOJSScript : OOScript <OOWeakReferenceSupport>

// path nullopt is nil (the script is then named after its address); properties may hold live objects.
+ (id)scriptWithPath:(const std::optional<std::string>&)path properties:(const oo::PList&)properties;

- (id)initWithPath:(const std::optional<std::string>&)path properties:(const oo::PList&)properties;

+ (OOJSScript*)currentlyRunningScript;
+ (std::vector<oo::ObjCRef<OOJSScript*>>)scriptStack;

/*	External manipulation of acrtive script stack. Used, for instance, by
        timers. Failing to balance these will crash!
        Passing a nil script is valid for cases where JS is used which is not
        attached to a specific script.
*/
+ (void)pushScript:(OOJSScript*)script;
+ (void)popScript:(OOJSScript*)script;

/*	Call a method.
        outResult may be NULL; if not, it is owned by the caller.
*/
- (BOOL)callMethod:(JSAtom)methodID
         inContext:(JSContext*)context
     withArguments:(JSValueConst*)argv
             count:(int)argc
            result:(JSValue*)outResult;

// The property as cxx_OOJSPListFromJSValue() converts it; null when there is no script object or it could not be read.
- (oo::PList)cxx_propertyWithID:(JSAtom)propID inContext:(JSContext*)context;
// Set a property which can be modified or deleted by the script.
- (BOOL)setProperty:(const oo::PList&)value withID:(JSAtom)propID inContext:(JSContext*)context;
// Set a special property which cannot be modified or deleted by the script.
- (BOOL)defineProperty:(const oo::PList&)value withID:(JSAtom)propID inContext:(JSContext*)context;

- (oo::PList)cxx_propertyNamed:(const std::string&)name;
- (BOOL)setProperty:(const oo::PList&)value named:(const std::string&)name;
- (BOOL)defineProperty:(const oo::PList&)value named:(const std::string&)name;

@end

@interface OOScript (JavaScriptEvents)

// For simplicity, calling methods on non-JS scripts works but does nothing.
- (BOOL)callMethod:(JSAtom)methodID
         inContext:(JSContext*)context
     withArguments:(JSValueConst*)argv
             count:(int)argc
            result:(JSValue*)outResult;

@end

namespace oo {

// The script's facade (its identity): the live one, or nil. Autoreleased.
::OOJSScript* ToObjC(cxx::OOJSScript* script);

// The C++ script behind a facade, borrowed (the facade owns it); null for nil.
cxx::OOJSScript* ToCxx(::OOJSScript* script);

} // namespace oo

#endif // OOJSSCRIPT_OBJCBRIDGE_H
