/*

OOMaterialConvenienceCreators+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-o89 item 4): the category OOConvenienceCreators of the
Objective-C OOMaterial facade (see OOMaterialConvenienceCreators+ObjCBridge.h), one line per
method. Deleted with OOMaterialConvenienceCreators+ObjCBridge.h.


Copyright (C) 2007-2013 Jens Ayton

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

#import "OOMaterialConvenienceCreators.h"

@implementation OOMaterial (OOConvenienceCreators)

+ (OOMaterial*)materialWithName:(const std::optional<std::string>&)name
                       cacheKey:(const std::optional<std::string>&)cacheKey
                  configuration:(const oo::PList&)configuration
                         macros:(const oo::PList&)macros
                  bindingTarget:(id<OOWeakReferenceSupport>)object
                forSmoothedMesh:(BOOL)smooth
{
    return oo::ToObjC(cxx::OOMaterial::materialWithName(name, cacheKey, configuration, macros, object, smooth));
}

+ (OOMaterial*)materialWithName:(const std::optional<std::string>&)name
                       cacheKey:(const std::optional<std::string>&)cacheKey
             materialDictionary:(const oo::PList&)materialDict
              shadersDictionary:(const oo::PList&)shadersDict
                         macros:(const oo::PList&)macros
                  bindingTarget:(id<OOWeakReferenceSupport>)object
                forSmoothedMesh:(BOOL)smooth
{
    return oo::ToObjC(cxx::OOMaterial::materialWithName(name, cacheKey, materialDict, shadersDict, macros, object, smooth));
}

@end
