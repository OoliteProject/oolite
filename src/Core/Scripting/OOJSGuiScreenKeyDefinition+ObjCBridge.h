/*

OOJSGuiScreenKeyDefinition+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-xg7g): the Objective-C OOJSGuiScreenKeyDefinition, a
subclass of the Objective-C OOWeakRefObject, over the C++ cxx::OOJSGuiScreenKeyDefinition
(OOJSGuiScreenKeyDefinition.h). A class whose superclass is still Objective-C (amendment oo-o89): the
facade keeps the old superclass, so it is still weakly referenced as before (-weakRetain), makes
and owns the C++ object in -init, and forwards every method. Its interface is the one
OOJSGuiScreenKeyDefinition.h declared before the conversion, copied exactly (same selectors and
types; the ivar is the C++ object). Imported as the last line of OOJSGuiScreenKeyDefinition.h; do
not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  -------------------------
        still Objective-C                      OOJSGuiScreenKeyDefinition *       nothing: messages as before
        converted (C++)                        the facade (it carries the weak-reference state)
          the C++ object of a facade                                            oo::ToCxx(objcDefinition)
          the facade of a C++ object                                            oo::ToObjC(definition): live or nil

oo::ToObjC never makes a facade (amendment oo-o89 item 2). Never add to this file; converted code
does not message the facade. Deleted by its deletion bead once its holders (PlayerEntity and OOJSGlobal) are C++
and hold it with oo::WeakRef; OOWeakRefObject goes after that (bead oo-9ht.22).


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

#ifndef OOJSGUISCREENKEYDEFINITION_OBJCBRIDGE_H
#define OOJSGUISCREENKEYDEFINITION_OBJCBRIDGE_H

#import "OOWeakReference.h"

@interface OOJSGuiScreenKeyDefinition : OOWeakRefObject {
@private
    oo::Ref<cxx::OOJSGuiScreenKeyDefinition> _cxxDefinition;
}

- (std::optional<std::string>)cxx_name; // nullopt until set (bead oo-3rb.289.7)
- (void)cxx_setName:(const std::optional<std::string>&)name;
- (oo::PList)registerKeys;
- (void)setRegisterKeys:(const oo::PList&)registerKeys;
// Returned values are owned by the caller.
- (JSValue)callback;
- (void)setCallback:(JSValueConst)callback;
- (JSValue)callbackThis;
- (void)setCallbackThis:(JSValueConst)callbackthis;

- (void)runCallback:(const std::string&)key;

- (OOComparisonResult)interfaceCompare:(OOJSGuiScreenKeyDefinition*)other;

@end

namespace oo {

// The definition's live facade, or nil: never makes one (amendment oo-o89 item 2).
::OOJSGuiScreenKeyDefinition* ToObjC(cxx::OOJSGuiScreenKeyDefinition* definition);

// The C++ definition behind a facade, borrowed (the facade owns it); null for nil.
cxx::OOJSGuiScreenKeyDefinition* ToCxx(::OOJSGuiScreenKeyDefinition* definition);

} // namespace oo

#endif // OOJSGUISCREENKEYDEFINITION_OBJCBRIDGE_H
