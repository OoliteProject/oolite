/*

OONullTexture+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056): the Objective-C OONullTexture facade over cxx::OONullTexture.
Deleted, with OONullTexture+ObjCBridge.h, by the bridge's deletion bead.


Copyright (C) 2008-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OONullTexture.h"

@implementation OONullTexture

/*	The singleton keeps one facade for the life of the process, retained once, so
        [OONullTexture sharedNullTexture] == [OOTexture nullTexture] whenever it is asked (proposed
        ADR-0056 amendment oo-r7m0 item 5).
        NOTE: assumes single-threaded access.
*/
+ (OONullTexture*)sharedNullTexture
{
    static OONullTexture* sFacade = nil;
    if (sFacade == nil)
        sFacade = [oo::ToObjC(cxx::OONullTexture::sharedNullTexture()) retain];
    return sFacade;
}

@end

// A C++ null texture's facade is an OONullTexture: the root's oo::ToObjC picks the Objective-C
// class named as the C++ class is (amendment oo-up4b item 3).
OONullTexture* oo::ToObjC(cxx::OONullTexture* texture)
{
    return static_cast<OONullTexture*>(oo::ToObjC(static_cast<cxx::OOTexture*>(texture)));
}

cxx::OONullTexture* oo::ToCxx(OONullTexture* texture)
{
    return static_cast<cxx::OONullTexture*>(oo::ToCxx(static_cast<OOTexture*>(texture)));
}
