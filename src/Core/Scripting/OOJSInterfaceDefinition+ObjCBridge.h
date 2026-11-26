/*

OOJSInterfaceDefinition+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-8fpc): the Objective-C OOJSInterfaceDefinition, a
subclass of the Objective-C OOWeakRefObject, over the C++ cxx::OOJSInterfaceDefinition
(OOJSInterfaceDefinition.h). A class whose superclass is still Objective-C (amendment oo-o89): the
facade keeps the old superclass, so it is still weakly referenced as before (-weakRetain), makes
and owns the C++ object in -init, and forwards every method. Its interface is the one
OOJSInterfaceDefinition.h declared before the conversion, copied exactly (same selectors and
types; the ivar is the C++ object). Imported as the last line of OOJSInterfaceDefinition.h; do
not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  -------------------------
        still Objective-C                      OOJSInterfaceDefinition *       nothing: messages as before
        converted (C++)                        the facade (it carries the weak-reference state)
          the C++ object of a facade                                            oo::ToCxx(objcDefinition)
          the facade of a C++ object                                            oo::ToObjC(definition): live or nil

oo::ToObjC never makes a facade (amendment oo-o89 item 2). Never add to this file; converted code
does not message the facade. Deleted by its deletion bead once its holders (PlayerEntity, StationEntity and OOJSStation) are C++
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

#ifndef OOJSINTERFACEDEFINITION_OBJCBRIDGE_H
#define OOJSINTERFACEDEFINITION_OBJCBRIDGE_H

#import "OOWeakReference.h"

@interface OOJSInterfaceDefinition : OOWeakRefObject {
@private
    oo::Ref<cxx::OOJSInterfaceDefinition> _cxxDefinition;
}

- (std::optional<std::string>)cxx_title; // nullopt: none (bead oo-3rb.290)
- (void)cxx_setTitle:(const std::optional<std::string>&)title; // bead oo-3rb.290
- (std::optional<std::string>)category;
- (void)setCategory:(const std::string&)category;
- (std::optional<std::string>)summary;
- (void)setSummary:(const std::string&)summary;
// Returned values are owned by the caller.
- (JSValue)callback;
- (void)setCallback:(JSValueConst)callback;
- (JSValue)callbackThis;
- (void)setCallbackThis:(JSValueConst)callbackthis;

- (void)runCallback:(const std::string&)key;

- (OOComparisonResult)interfaceCompare:(OOJSInterfaceDefinition*)other;

@end

namespace oo {

// The definition's live facade, or nil: never makes one (amendment oo-o89 item 2).
::OOJSInterfaceDefinition* ToObjC(cxx::OOJSInterfaceDefinition* definition);

// The C++ definition behind a facade, borrowed (the facade owns it); null for nil.
cxx::OOJSInterfaceDefinition* ToCxx(::OOJSInterfaceDefinition* definition);

} // namespace oo

#endif // OOJSINTERFACEDEFINITION_OBJCBRIDGE_H
