/*

OOMaterialConvenienceCreators+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-o89 item 4): the category OOConvenienceCreators of
the Objective-C OOMaterial facade, for the caller that still messages it (OOMesh). Its interface is
the one OOMaterialConvenienceCreators.h declared before the conversion, copied exactly; each method
forwards to the static member of cxx::OOMaterial of the same name and answers the result's facade.
Imported as the last line of OOMaterialConvenienceCreators.h; do not import it directly. Deleted
by its deletion bead once OOMesh is C++.


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

#ifndef OOMATERIALCONVENIENCECREATORS_OBJCBRIDGE_H
#define OOMATERIALCONVENIENCECREATORS_OBJCBRIDGE_H

@interface OOMaterial (OOConvenienceCreators)

/*	Get a material based on configuration. The result will be an
        OOBasicMaterial, OOSingleTextureMaterial or OOShaderMaterial (the latter
        only if shaders are available). cacheKey is used for caching of synthesized
        shader materials; nullopt may be passed for no caching.
        Unique selectors (ADR-0043): name/cacheKey are optional UTF-8 strings;
        configuration and macros are oo::PList (null = nil).
*/
+ (OOMaterial*)materialWithName:(const std::optional<std::string>&)name
                       cacheKey:(const std::optional<std::string>&)cacheKey
                  configuration:(const oo::PList&)configuration
                         macros:(const oo::PList&)macros
                  bindingTarget:(id<OOWeakReferenceSupport>)object
                forSmoothedMesh:(BOOL)smooth;

/*	Select an appropriate material description (based on availability of
        shaders and content of dictionaries, which may be null) and call
        +materialWithName:cacheKey:configuration:macros:bindingTarget:forSmoothedMesh:.
*/
+ (OOMaterial*)materialWithName:(const std::optional<std::string>&)name
                       cacheKey:(const std::optional<std::string>&)cacheKey
             materialDictionary:(const oo::PList&)materialDict
              shadersDictionary:(const oo::PList&)shadersDict
                         macros:(const oo::PList&)macros
                  bindingTarget:(id<OOWeakReferenceSupport>)object
                forSmoothedMesh:(BOOL)smooth;

@end

#endif // OOMATERIALCONVENIENCECREATORS_OBJCBRIDGE_H
