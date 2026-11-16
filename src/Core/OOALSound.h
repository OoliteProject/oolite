/*

OOALSound.h

OOALSound - OpenAL sound implementation for Oolite.

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

#import "OOFoundation.h"
#import "OOOpenALController.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/StdLib.hpp"

@interface OOSound : OOObject

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
