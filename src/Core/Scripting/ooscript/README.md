# ooscript — the JavaScript engine façade

`JSEngine.hpp` is the only header Oolite code uses to talk to its script engine (Phase 1 seam 1.1, bead oo-e7c; ADR-0002, architecture §4 R1). Since bead oo-7wx its only backend is `JSEngine_quickjs.cpp` (QuickJS-ng, linked statically); the SpiderMonkey 1.8.5 backend, the `js_backend` option, and the js/NSPR dependencies were removed. `tools/check-jsengine-facade.sh` is the acceptance for the header (engine-neutral, clean under `-Wall -Wextra -Werror`) and, absolutely, for the tree: no game source outside the backend names an engine symbol or header.

This file, not the header, carries the engine names: the deny-list forbids `JS_*` tokens in code files, comments included, and a Markdown file is not scanned.

## Retarget map: engine function -> façade call

Generated from the header's declarations. One row per façade function that replaces an engine call; the `CallArgs` accessors replace the `JS_ARGV` / `JS_THIS` / `JS_RVAL` / `JS_SET_RVAL` / `JS_CALLEE` macros, and a `nullptr` hook in `ClassDef` replaces the `JS_PropertyStub` / `JS_EnumerateStub` / `JS_ResolveStub` / `JS_ConvertStub` / `JS_StrictPropertyStub` / `JS_FinalizeStub` family.

| engine | façade | note |
|---|---|---|
| `JS_NewNumberValue` | `ooscript::numberValue` | without the always-true success flag |
| `JS_NewNumberValue` | `ooscript::newNumberValue` |  |
| `JS_ValueToNumber` | `ooscript::valueToNumber` |  |
| `JS_ValueToBoolean` | `ooscript::valueToBoolean` |  |
| `JS_ValueToObject` | `ooscript::valueToObject` |  |
| `JS_ValueToInt32` | `ooscript::valueToInt32` |  |
| `JS_ValueToECMAInt32` | `ooscript::valueToECMAInt32` |  |
| `JS_ValueToECMAUint32` | `ooscript::valueToECMAUint32` |  |
| `JS_ValueToString` | `ooscript::valueToString` | null on failure |
| `JS_ValueToFunction` | `ooscript::valueToFunction` | null on failure |
| `JS_ValueToId` | `ooscript::valueToId` |  |
| `JS_IdToValue` | `ooscript::idToValue` |  |
| `JS_TypeOfValue` | `ooscript::typeOfValue` |  |
| `JS_GetTypeName` | `ooscript::typeName` |  |
| `JS_ARGV` | `ooscript::argv` |  |
| `JS_CALLEE` | `ooscript::callee` |  |
| `JS_THIS` | `ooscript::thisValue` |  |
| `JS_THIS_OBJECT` | `ooscript::thisObject` | (may run script) |
| `JS_RVAL` | `ooscript::rval` |  |
| `JS_SET_RVAL` | `ooscript::setRval` |  |
| `JS_IsConstructing` | `ooscript::isConstructing` |  |
| `JS_NewObject` | `ooscript::newObject` |  |
| `JS_NewCompartmentAndGlobalObject` | `ooscript::newGlobalObject` |  |
| `JS_InitStandardClasses` | `ooscript::initStandardClasses` |  |
| `JS_ClearScope` | `ooscript::clearScope` |  |
| `JS_InitClass` | `ooscript::initClass` |  |
| `JS_DefineObject` | `ooscript::defineObject` |  |
| `JS_GetConstructor` | `ooscript::getConstructor` |  |
| `JS_GetPrototype` | `ooscript::getPrototype` |  |
| `JS_GetParent` | `ooscript::getParent` |  |
| `JS_GetGlobalObject` | `ooscript::getGlobalObject` |  |
| `JS_GetGlobalForObject` | `ooscript::getGlobalForObject` |  |
| `JS_GetClass` | `ooscript::getClass` | nullptr if the class is not ours |
| `JS_InstanceOf` | `ooscript::instanceOf` |  |
| `JS_SetPrivate` | `ooscript::setPrivate` |  |
| `JS_GetPrivate` | `ooscript::getPrivate` |  |
| `JS_GetInstancePrivate` | `ooscript::getInstancePrivate` |  |
| `JS_ObjectIsFunction` | `ooscript::objectIsFunction` |  |
| `JS_GetProperty` | `ooscript::getProperty` |  |
| `JS_SetProperty` | `ooscript::setProperty` |  |
| `JS_GetPropertyById` | `ooscript::getPropertyById` |  |
| `JS_SetPropertyById` | `ooscript::setPropertyById` |  |
| `JS_DefinePropertyById` | `ooscript::definePropertyById` |  |
| `JS_LookupProperty` | `ooscript::lookupProperty` |  |
| `JS_LookupPropertyById` | `ooscript::lookupPropertyById` |  |
| `JS_HasProperty` | `ooscript::hasProperty` |  |
| `JS_DeleteProperty` | `ooscript::deleteProperty` |  |
| `JS_GetMethodById` | `ooscript::getMethodById` |  |
| `JS_DefineProperty` | `ooscript::defineProperty` |  |
| `JS_DefineProperties` | `ooscript::defineProperties` |  |
| `JS_DefineFunction` | `ooscript::defineFunction` |  |
| `JS_DefineFunctions` | `ooscript::defineFunctions` |  |
| `JS_SetElement` | `ooscript::setElement` |  |
| `JS_GetElement` | `ooscript::getElement` |  |
| `JS_LookupElement` | `ooscript::lookupElement` |  |
| `JS_NewArrayObject` | `ooscript::newArrayObject` |  |
| `JS_IsArrayObject` | `ooscript::isArrayObject` |  |
| `JS_GetArrayLength` | `ooscript::getArrayLength` |  |
| `JS_SetArrayLength` | `ooscript::setArrayLength` |  |
| `JS_Enumerate` | `ooscript::enumerate` |  |
| `JS_DestroyIdArray` | `ooscript::destroyIdArray` |  |
| `JS_GetFunctionId` | `ooscript::getFunctionId` | null if anonymous |
| `JS_GetFunctionObject` | `ooscript::getFunctionObject` |  |
| `JS_GetFunctionNative` | `ooscript::getFunctionNative` | nullptr unless ours |
| `JS_CallFunctionValue` | `ooscript::callFunctionValue` |  |
| `JS_CallFunctionName` | `ooscript::callFunctionName` |  |
| `JS_EvaluateScript` | `ooscript::evaluateScript` |  |
| `JS_EvaluateUCScript` | `ooscript::evaluateUCScript` |  |
| `JS_CompileUCScript` | `ooscript::compileUCScript` |  |
| `JS_NewScriptObject` | `ooscript::newScriptObject` |  |
| `JS_ExecuteScript` | `ooscript::executeScript` |  |
| `JS_DestroyScript` | `ooscript::destroyScript` |  |
| `JS_XDRNewMem`+`JS_XDRScript`+`JS_XDRMemGetData`+`JS_XDRDestroy` | `ooscript::serializeScript` | owned `ByteBuffer` out; wire format stays backend-private |
| `JS_XDRNewMem`+`JS_XDRMemSetData`+`JS_XDRScript`+`JS_XDRDestroy` | `ooscript::deserializeScript` | wire format stays backend-private |
| `JS_InternString` | `ooscript::internString` |  |
| `JS_InternUCStringN` | `ooscript::internUCStringN` |  |
| `JS_NewStringCopyZ` | `ooscript::newStringCopyZ` |  |
| `JS_NewStringCopyN` | `ooscript::newStringCopyN` |  |
| `JS_NewUCStringCopyN` | `ooscript::newUCStringCopyN` |  |
| `JS_NewUCRegExpObjectNoStatics` | `ooscript::newUCRegExpObjectNoStatics` | no RegExp.$1.. statics binding |
| `JS_GetEmptyStringValue` | `ooscript::emptyStringValue` |  |
| `JS_GetStringLength` | `ooscript::getStringLength` |  |
| `JS_GetStringCharsAndLength` | `ooscript::getStringCharsAndLength` |  |
| `JS_GetInternedStringChars` | `ooscript::getInternedStringChars` |  |
| `JS_StringEqualsAscii` | `ooscript::stringEqualsAscii` |  |
| `JS_StringHasBeenInterned` | `ooscript::stringHasBeenInterned` |  |
| `JS_SetCStringsAreUTF8` | `ooscript::setCStringsAreUTF8` |  |
| `JS_SetGCZeal` | `ooscript::setGCZeal` |  |
| `JS_IsExceptionPending` | `ooscript::isExceptionPending` |  |
| `JS_GetPendingException` | `ooscript::getPendingException` |  |
| `JS_SetPendingException` | `ooscript::setPendingException` |  |
| `JS_ClearPendingException` | `ooscript::clearPendingException` |  |
| `JS_ReportPendingException` | `ooscript::reportPendingException` |  |
| `JS_ReportError` | `ooscript::reportError` | (cx, "%s", message) |
| `JS_ReportWarning` | `ooscript::reportWarning` | (cx, "%s", message) |
| `JS_ReportOutOfMemory` | `ooscript::reportOutOfMemory` |  |
| `JS_SetErrorReporter` | `ooscript::setErrorReporter` | returns the old one |
| `JS_SaveExceptionState` | `ooscript::saveExceptionState` |  |
| `JS_RestoreExceptionState` | `ooscript::restoreExceptionState` |  |
| `JS_DropExceptionState` | `ooscript::dropExceptionState` |  |
| `JS_AddNamedObjectRoot` | `ooscript::addNamedObjectRoot` |  |
| `JS_AddNamedValueRoot` | `ooscript::addNamedValueRoot` |  |
| `JS_AddNamedStringRoot` | `ooscript::addNamedStringRoot` |  |
| `JS_RemoveObjectRoot` | `ooscript::removeObjectRoot` |  |
| `JS_RemoveValueRoot` | `ooscript::removeValueRoot` |  |
| `JS_RemoveStringRoot` | `ooscript::removeStringRoot` |  |
| `JS_NewRuntime` | `ooscript::newRuntime` |  |
| `JS_DestroyRuntime` | `ooscript::destroyRuntime` |  |
| `JS_ShutDown` | `ooscript::shutDown` |  |
| `JS_NewContext` | `ooscript::newContext` |  |
| `JS_DestroyContext` | `ooscript::destroyContext` |  |
| `JS_GetRuntime` | `ooscript::getRuntime` |  |
| `JS_GetContextPrivate` | `ooscript::getContextPrivate` |  |
| `JS_SetContextPrivate` | `ooscript::setContextPrivate` |  |
| `JS_BeginRequest` | `ooscript::beginRequest` |  |
| `JS_EndRequest` | `ooscript::endRequest` |  |
| `JS_IsInRequest` | `ooscript::isInRequest` |  |
| `JS_SetOptions` | `ooscript::setOptions` | returns the old set |
| `JS_GetOptions` | `ooscript::getOptions` |  |
| `JS_SetVersion` | `ooscript::setVersion` | returns the old one |
| `JS_GetVersion` | `ooscript::getVersion` |  |
| `JS_VersionToString` | `ooscript::versionToString` |  |
| `JS_GetGCParameter` | `ooscript::getGCParameter` |  |
| `JS_SetGCParameter` | `ooscript::setGCParameter` |  |
| `JS_GC` | `ooscript::gc` |  |
| `JS_MaybeGC` | `ooscript::maybeGC` |  |
| `JS_SetOperationCallback` | `ooscript::setOperationCallback` | returns the old one |
| `JS_TriggerOperationCallback` | `ooscript::triggerOperationCallback` |  |
| `JS_TriggerAllOperationCallbacks` | `ooscript::triggerAllOperationCallbacks` |  |
| `JS_SuspendRequest` / `JS_ResumeRequest` | `ooscript::suspendRequest` / `ooscript::resumeRequest` | token-based (bead oo-1gc.3) |
| `JS_CompareStrings` | `ooscript::compareStrings` |  |
| `JS_FreezeObject` | `ooscript::freezeObject` |  |
| `JS_CompileUCFunction` | `ooscript::compileUCFunction` |  |
| `JS_CallFunction` | `ooscript::callFunction` |  |
| `JS_BufferIsCompilableUnit` | `ooscript::bufferIsCompilableUnit` |  |
| `JSREG_FOLD` / `JSREG_GLOB` / `JSREG_MULTILINE` / `JSREG_STICKY` | `ooscript::RegExpFoldCase` / `RegExpGlobal` / `RegExpMultiline` / `RegExpSticky` | constants |
| `JS_FrameIterator`, `JS_IsScriptFrame`, `JS_IsConstructorFrame`, `JS_IsDebuggerFrame`, `JS_GetFrameScript`, `JS_GetScriptFilename`, `JS_PCToLineNumber`+`JS_GetFramePC`, `JS_GetFrameFunction`, `JS_GetFrameThis`, `JS_GetFrameScopeChain` | `ooscript::frameIterator`, `frameIsScript`, `frameIsConstructor`, `frameIsDebugger`, `frameScript`, `scriptFilename`, `frameLineNumber`, `frameFunction`, `frameThis`, `frameScopeChain` | debug section; QuickJS-ng: file/line frames only (ADR-0022) |
| `JS_GetPropertyDescArray` / `JS_PutPropertyDescArray` | `ooscript::getScopeVariables` / `destroyScopeVariables` | false on QuickJS-ng |
| `JS_SetDebuggerHandler`, `JS_SetFunctionCallback`, `JS_SetContextCallback` | `ooscript::setDebuggerHandler`, `setFunctionCallback`, `setContextCallback` | debug section |
| `JS_DumpNamedRoots`, `JS_DumpHeap` | `ooscript::dumpNamedRoots`, `ooscript::dumpHeap` | DEBUG engine builds / QuickJS-ng memory summary |
| `JS_Now` | `std::chrono::steady_clock` (OOProfilingStopwatch.h) | not a façade call |

## Top-20 map: engine function -> façade call (histogram over upstream/oolite/src, 2026-09-18)

	  rank  sites  JS_* function                 façade
	     1    144  JS_NewNumberValue             ooscript::newNumberValue / ooscript::numberValue
	     2    102  JS_ValueToNumber              ooscript::valueToNumber
	     3     63  JS_ValueToBoolean             ooscript::valueToBoolean
	     4     29  JS_InitClass                  ooscript::initClass
	     5     27  JS_GetProperty                ooscript::getProperty
	     6     25  JS_ValueToObject              ooscript::valueToObject
	     7     22  JS_SetPrivate                 ooscript::setPrivate
	     8     21  JS_IsInRequest                ooscript::isInRequest
	     9     19  JS_NewObject                  ooscript::newObject
	    10     17  JS_RemoveObjectRoot           ooscript::removeObjectRoot (RootedObject for scoped roots)
	    11     14  JS_RemoveValueRoot            ooscript::removeValueRoot (RootedValue for scoped roots)
	    12     13  JS_InternString               ooscript::internString
	    13     11  JS_DefineObject               ooscript::defineObject
	    14     10  JS_GetPrivate                 ooscript::getPrivate
	    15      9  JS_SetElement                 ooscript::setElement
	    16      8  JS_ReportPendingException     ooscript::reportPendingException
	    17      8  JS_ClearPendingException      ooscript::clearPendingException
	    18      7  JS_LookupElement              ooscript::lookupElement
	    19      7  JS_GetGCParameter             ooscript::getGCParameter
	    20      7  JS_CallFunctionValue          ooscript::callFunctionValue

	The stub family (JS_PropertyStub 60, JS_EnumerateStub 29, JS_ResolveStub 32, JS_ConvertStub
	32) has no façade call: a nullptr hook in ooscript::ClassDef is the stub. The value macros
	(JSVAL_IS_NULL 79, JSVAL_VOID 78, INT_TO_JSVAL 77, JSVAL_TO_OBJECT 48, JSVAL_IS_VOID 43,
	JSVAL_IS_OBJECT 43, JSVAL_NULL 37, OBJECT_TO_JSVAL 34, STRING_TO_JSVAL 23, ...) map onto the
	Value construction and inspection block above. The call-argument macros (JS_ARGV, JS_THIS,
	JS_THIS_OBJECT, JS_RVAL, JS_SET_RVAL, JS_CALLEE, behind OOJS_ARGV and friends) map onto
	ooscript::CallArgs.

## The QuickJS-ng backend

`JSEngine_quickjs.cpp` implements every function in `JSEngine.hpp` (bead oo-1gc.2) against the vendored QuickJS-ng; `tools/check-jsengine-facade-quickjs.sh` and `tools/check-jsengine-facade-quickjs-asan.sh` are its acceptance. Its file banner is the design record: the handle arena that stands in for SpiderMonkey's conservative stack scan (roots are addresses read at `gc()`/`maybeGC()` time), strings and property ids, how `ClassDef` hooks map onto exotic methods and per-object slots, natives, scripts, errors, and every place it knowingly diverges from SpiderMonkey 1.8.5 (grep `DIVERGENCE`).

## Not in the façade, and why

	JS_EnterLocalRootScope, JS_LeaveLocalRootScope: superseded. SpiderMonkey's conservative stack
	scan and the QuickJS-ng backend's handle arena both keep a native's locals alive; the three
	sites were deleted (bead oo-1gc.3).

	The engine's frame walk, debugger hook, function-call tracer and root/heap dumps used to be
	listed here; they are now the façade's "Debugging and profiling" section, with the explicit
	contract that a backend may answer with less (ADR-0022).
