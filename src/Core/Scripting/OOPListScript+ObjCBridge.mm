/*

OOPListScript+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-q9q4): the Objective-C OOPListScript facade; see
OOPListScript+ObjCBridge.h. Each method forwards in one line to cxx::OOPListScript.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "OOPListScript.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@implementation OOPListScript

// Inside the @implementation for the private ivar.
::OOPListScript* oo::ToObjC(cxx::OOPListScript* script)
{
    return Peers().peerFor(script, [] { return (id)nil; });
}

cxx::OOPListScript* oo::ToCxx(::OOPListScript* script)
{
    if (script == nil)
        return nullptr;
    return script->_cxxScript.get();
}

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)scriptsInPListFile:(const std::string&)filePath
{
    return cxx::OOPListScript::scriptsInPListFile(filePath);
}

- (id)initWithName:(const std::string&)name scriptArray:(const oo::PList&)script metadata:(const oo::PList*)metadata
{
    self = [super init];
    if (self != nil) {
        _cxxScript = oo::makeRef<cxx::OOPListScript>(name, script, metadata);
        @autoreleasepool {
            Peers().peerFor(_cxxScript.get(), [self] { return [self retain]; });
        }
    }

    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxScript.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_name
{
    return _cxxScript->name();
}
- (std::optional<std::string>)scriptDescription
{
    return _cxxScript->scriptDescription();
}
- (std::optional<std::string>)cxx_version
{
    return _cxxScript->version();
}
- (BOOL)requiresTickle
{
    return _cxxScript->requiresTickle();
}
- (void)runWithTarget:(Entity*)target
{
    _cxxScript->runWithTarget(target);
}

@end
