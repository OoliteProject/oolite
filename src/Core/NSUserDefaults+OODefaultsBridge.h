/*

NSUserDefaults+OODefaultsBridge.h

TRANSITIONAL (bead oo-mwo0; ADR-0032 point 5 as amended; the ADR-0043 Amendment 1 bridge
pattern). One preferences store for the whole game: the game's +[NSUserDefaults
standardUserDefaults] answers from oo::Defaults::standard(), so a value set through either API is
read back through the other, and only oo::Defaults writes GNUstep/Defaults/<domain>.plist. Files
can then be swept off NSUserDefaults one at a time, readers and writers alike.

How: on first use GNUstep builds its standard defaults object as always (argument, language and
GNUstep configuration domains included); the bridge then retargets that one object to a subclass
without instance variables whose getters (-objectForKey:, -stringForKey:, -arrayForKey:,
-dictionaryForKey:, -boolForKey:, -integerForKey:, -floatForKey:, -doubleForKey:; GNUstep's
others, such as -dataForKey: and -stringArrayForKey:, read -objectForKey:), setters (-setObject:forKey:, -setBool:forKey:,
-setInteger:forKey:, -setFloat:forKey:, -setDouble:forKey:), -removeObjectForKey:,
-registerDefaults: and -synchronize forward to oo::Defaults, converting with oo::PListFrom /
oo::ObjectFromPList. A key oo::Defaults does not have (GNUstep's own settings, in its language,
GSConfigDomain and registration domains) is answered by GNUstep as before. Other NSUserDefaults
instances are untouched. The first change after a save schedules one -synchronize 30 s later
(OOScheduleDeferredCall; gnustep-base's automatic-save interval, bead oo-xeve, ADR-0032
Amendment 2).

The shim goes (bead oo-iobt, "Delete NSUserDefaults+OODefaultsBridge") once no file uses
NSUserDefaults; oo-qps (the removal of gnustep-base) cannot compile while it exists.

Oolite
Copyright (C) 2004-2025 Giles C Williams and contributors
GPL v2 or later; see NSUserDefaults+Override.h.

*/

#ifndef NSUSERDEFAULTS_OODEFAULTSBRIDGE_H
#define NSUSERDEFAULTS_OODEFAULTSBRIDGE_H

// Declares only C++ functions: no Foundation import needed here (the .mm has it).
namespace oo {
class Defaults;
}

// FOR TESTS ONLY: the store the bridge forwards to (nullptr: oo::Defaults::standard(), the default).
// Set it before the first +standardUserDefaults, or between uses from one thread.
void OODefaultsBridgeSetStore(oo::Defaults* store);

// Whether +standardUserDefaults' object is backed by oo::Defaults (true after its first use).
bool OODefaultsBridgeIsInstalled(void);

#endif // NSUSERDEFAULTS_OODEFAULTSBRIDGE_H
