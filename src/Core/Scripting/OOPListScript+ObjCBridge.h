/*

OOPListScript+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-q9q4): the Objective-C OOPListScript, a subclass of the
Objective-C OOScript, over the C++ cxx::OOPListScript (OOPListScript.h). A class whose superclass
is still Objective-C (amendment oo-o89): the facade keeps the old superclass, makes and owns the
C++ object in its initialiser, and forwards the OOScript overrides, which OOScript and its callers
send. Its interface is the one OOPListScript.h declared before the conversion; the initialiser,
which the file's private category declared, is in category OOObjCBridge for cxx::OOPListScript's
factories. Imported as the last line of OOPListScript.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  -------------------------
        still Objective-C                      OOPListScript * / OOScript *    nothing: messages as before
        converted (C++)                        oo::ObjCRef<OOScript *>, as the superclass is Objective-C
          the C++ object of a facade                                            oo::ToCxx(objcScript)
          the facade of a C++ object                                            oo::ToObjC(script): live or nil

oo::ToObjC never makes a facade: a new one would have fresh OOScript state (amendment oo-o89
item 2). Never add to this file; converted code does not message the facade except to make one.
Deleted by its deletion bead once OOScript is C++.


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

#ifndef OOPLISTSCRIPT_OBJCBRIDGE_H
#define OOPLISTSCRIPT_OBJCBRIDGE_H

#import "OOScript.h"

@interface OOPListScript : OOScript {
@private
    oo::Ref<cxx::OOPListScript> _cxxScript;
}

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)scriptsInPListFile:(const std::string&)filePath;

@end

@interface OOPListScript (OOObjCBridge)

// Makes the C++ script and records the facade as its peer (for cxx::OOPListScript's factories).
- (id)initWithName:(const std::string&)name scriptArray:(const oo::PList&)script metadata:(const oo::PList*)metadata;

@end

namespace oo {

// The script's live facade, or nil: never makes one (amendment oo-o89 item 2).
::OOPListScript* ToObjC(cxx::OOPListScript* script);

// The C++ script behind a facade, borrowed (the facade owns it); null for nil.
cxx::OOPListScript* ToCxx(::OOPListScript* script);

} // namespace oo

#endif // OOPLISTSCRIPT_OBJCBRIDGE_H
