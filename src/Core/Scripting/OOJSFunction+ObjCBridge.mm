/*

OOJSFunction+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-3smy): the Objective-C OOJSFunction facade; see
OOJSFunction+ObjCBridge.h. Each method forwards in one line to cxx::OOJSFunction.


JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOJSFunction.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOJSFunction (OOObjCBridgePrivate)

// For oo::ToObjC, under the peer table's lock: stores the C++ object.
- (id)initWithCxxFunction:(cxx::OOJSFunction*)function;

// For the initialisers: releases self and answers nil for null, else stores the new C++ object
// and records the facade as its peer (amendment oo-bhb9 item 3).
- (id)initWithNewCxxFunction:(const oo::Ref<cxx::OOJSFunction>&)function;

@end

@implementation OOJSFunction

// Inside the @implementation for the private ivar.
::OOJSFunction* oo::ToObjC(cxx::OOJSFunction* function)
{
    return Peers().peerFor(function, [function] { return [[::OOJSFunction alloc] initWithCxxFunction:function]; });
}

cxx::OOJSFunction* oo::ToCxx(::OOJSFunction* function)
{
    if (function == nil)
        return nullptr;
    return function->_cxxFunction.get();
}

- (id)initWithCxxFunction:(cxx::OOJSFunction*)function
{
    self = [super init];
    if (self != nil)
        _cxxFunction = oo::Ref<cxx::OOJSFunction>(function);
    return self;
}

- (id)initWithNewCxxFunction:(const oo::Ref<cxx::OOJSFunction>&)function
{
    if (function == nullptr) {
        [self release];
        return nil;
    }
    self = [super init];
    if (self != nil) {
        _cxxFunction = function;
        @autoreleasepool {
            Peers().peerFor(_cxxFunction.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)initWithFunction:(JSValueConst)function context:(JSContext*)context
{
    return [self initWithNewCxxFunction:cxx::OOJSFunction::initWithFunction(function, context)];
}

- (id)initWithName:(const std::optional<std::string>&)name
             scope:(JSValueConst)scope
              code:(const std::optional<std::string>&)code
     argumentCount:(NSUInteger)argCount
     argumentNames:(const char**)argNames
          fileName:(const std::optional<std::string>&)fileName
        lineNumber:(NSUInteger)lineNumber
           context:(JSContext*)context
{
    return [self initWithNewCxxFunction:cxx::OOJSFunction::initWithName(name, scope, code, argCount, argNames, fileName, lineNumber, context)];
}

- (void)dealloc
{
    Peers().forget(_cxxFunction.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxFunction->descriptionComponents();
}
- (std::optional<std::string>)cxx_name
{
    return _cxxFunction->name();
}
- (JSValueConst)function
{
    return _cxxFunction->function();
}
- (JSValue)functionValue
{
    return _cxxFunction->functionValue();
}

- (BOOL)evaluateWithContext:(JSContext*)context
                      scope:(JSValueConst)jsThis
                       argc:(int)argc
                       argv:(JSValueConst*)argv
                     result:(JSValue*)result
{
    return _cxxFunction->evaluateWithContext(context, jsThis, argc, argv, result);
}

- (BOOL)evaluatePredicateWithContext:(JSContext*)context
                               scope:(id)jsThis
                           arguments:(const std::vector<oo::ObjCRef<id>>&)arguments
{
    return _cxxFunction->evaluatePredicateWithContext(context, jsThis, arguments);
}

@end
