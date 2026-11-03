/*

OOALSound+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-2en): the Objective-C OOSound, a facade over the
C++ cxx::OOSound (OOALSound.h), for the callers that message sounds (the sound sources, the
channels, the resource manager, the player, the JavaScript Sound class) and for the sounds not
converted yet (OOALBufferedSound, OOALStreamedSound, OOMusic). Its interface is the one OOALSound.h
declared before the conversion, copied exactly (same selectors, same types), so they compile and
behave unchanged. Imported as the last line of OOALSound.h; do not import it directly.

It is a hierarchy root's facade, as OODrawable+ObjCBridge.h is; the table there applies here:

        the sound is                         its facade is                      virtual calls on the
                                                                                  C++ side reach
        -----------------------------------  ---------------------------------  ---------------------
        an Objective-C subclass              the subclass instance itself, and  the subclass's
          (unconverted, [[X alloc] init])    an adapter is its C++ part         methods
        a C++ subclass (converted)           made by oo::ToObjC, one live one   the C++ overrides
                                             per sound (oo::ObjCPeers)

-cxx_initWithContentsOfFile: answers another object than its receiver (an OOALBufferedSound or
an OOALStreamedSound, which cxx::OOSound::initWithContentsOfFile makes); a subclass that overrides
it (OOMusic) still does. A converted caller that keeps a sound while any subclass is Objective-C
holds oo::ObjCRef<OOSound *>: an Objective-C sound's C++ part does not retain it.

A converted subclass that its callers make by alloc/init (OOMusic) has a facade of its own, a
subclass of this one with no ivars (amendment oo-up4b item 3): oo::ToObjC picks the Objective-C
class named as the C++ class is, else OOSound. The OOALBufferedSound and OOALStreamedSound facades
were deleted by beads oo-9ht.83 and oo-9ht.84: their sounds cross as OOSound, which the class
cluster makes with -initWithNewCxxSound:.

oo::ToObjC(oo::ToCxx(s)) == s for both kinds. Never add to this file; converted code does not
message the facade. Deleted by its deletion bead once every caller and every sound is C++.


Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef OOALSOUND_OBJCBRIDGE_H
#define OOALSOUND_OBJCBRIDGE_H

@interface OOSound : OOObject {
@private
    oo::Ref<cxx::OOSound> _cxxSound;
}

+ (BOOL)setUp;
+ (void)update;

+ (void)setMasterVolume:(float)fraction;
+ (float)masterVolume;

- (id)cxx_initWithContentsOfFile:(const std::optional<std::string>&)path OO_RETURNS_RETAINED; // nullopt: nil (bead oo-3rb.292.2)

- (std::optional<std::string>)cxx_name; // nullopt: none (bead oo-3rb.289.3)

+ (BOOL)isSoundOK;

- (ALuint)soundBuffer;
- (BOOL)soundIncomplete;
- (void)rewind;

@end

@interface OOSound (OOObjCBridge)

/*	For the facades of converted subclasses (OOALMusic+ObjCBridge.h) and the class cluster: the
        facade made by alloc and an initialiser adopts its new C++ sound and is that sound's peer (the
        one oo::ToObjC answers), as amendment oo-vl43 item 2's -initWithNewCxxMaterial: is.
*/
- (id)initWithNewCxxSound:(const oo::Ref<cxx::OOSound>&)sound;

@end

namespace oo {

// The sound's Objective-C object: an Objective-C sound itself, else a C++ sound's live facade (or
// a new one); autoreleased. nil for null.
OOSound* ToObjC(cxx::OOSound* sound);
inline OOSound* ToObjC(const Ref<cxx::OOSound>& sound) { return ToObjC(sound.get()); }

// The C++ sound behind an Objective-C one, borrowed (the Objective-C object retains it); null for nil.
cxx::OOSound* ToCxx(OOSound* sound);

} // namespace oo

#endif // OOALSOUND_OBJCBRIDGE_H
