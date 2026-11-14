/*

OOTextureLoader.h

Abstract base class for asynchronous texture loaders, which are dispatched by
OOTextureLoadDispatcher. In general, this should be used through OOTexture.

Note: interface is likely to change in future to support other buffer types
(like S3TC/DXT#).


Copyright (C) 2007-2014 Jens Ayton

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

#ifndef OOTEXTURELOADER_H
#define OOTEXTURELOADER_H

#import "OOAsyncWorkManager.h"
#import "OOTexture.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOTextureLoader;

/*	Foundation sweep (proposed ADR-0043 Amendments 1-2, bead oo-wzti): the path is a UTF-8
        std::string (never empty once initialised: a nil path failed -init); paths passed in are
        std::optional where the old code accepted nil; a texture specifier is an oo::PList.

        Phase 3 (bead oo-zl36, proposed ADR-0056 amendments oo-whzh, oo-bj8 and oo-zl36): the C++ root
        of the texture loaders. OOPixMapTextureLoader and the generators are still Objective-C
        subclasses of the facade (OOTextureLoader+ObjCBridge.h), and read the state below through its
        _cxxLoader (amendment oo-bj8 items 1-2), so the state is public; the converted
        OOPNGTextureLoader (bead oo-z889) derives from this class. A loader is a
        task on the work manager, which holds the Objective-C object.
*/
namespace cxx {

class OOTextureLoader : public oo::RefCounted {
public:
    OOTextureLoader();
    ~OOTextureLoader() override; // was -dealloc: frees the pixels not handed over

    /*	Were +cxx_loaderWithPath:options: and +cxx_loaderWithTextureSpecifier:extraOptions:folder:.
            The loader they make (the C++ OOPNGTextureLoader, bead oo-z889) is a task of the work
            manager, which holds its facade, so the facade is answered retained (amendment oo-2en
            item 2), already queued; null where they answered nil.
    */
    static oo::ObjCRef<::OOTextureLoader*> loaderWithPath(const std::optional<std::string>& path, uint32_t options);

    /*	Convenience method to load images not destined for normal texture use.
            Specifier is a string or a dictionary as with textures. ExtraOptions is
            ored into the option flags interpreted from the specifier. Folder is the
            directory to look in, typically Textures or Images. Options in the
            specifier which are applied at the OOTexture level will be ignored.
    */
    static oo::ObjCRef<::OOTextureLoader*> loaderWithTextureSpecifier(const oo::PList& specifier, uint32_t extraOptions, const std::optional<std::string>& folder);

    bool isReady();

    /*	Return value indicates success. This may only be called once (subsequent
            attempts will return failure), and only on the main thread.
    */
    virtual bool getResult(OOPixMap* result,
        OOTextureDataFormat* outFormat,
        uint32_t* outWidth,
        uint32_t* outHeight);

    /*	Hopefully-unique string for texture loader; analagous, but not identical,
            to corresponding texture cacheKey.
    */
    virtual std::optional<std::string> cacheKey();

    // What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h), and the short form's.
    virtual std::optional<std::string> descriptionComponents() const;
    virtual std::optional<std::string> shortDescriptionComponents() const;

    /*** Subclass interface; do not use on pain of pain. Unless you're subclassing. ***/

    /*	Was -cxx_initWithPath:options:, after [super init] (subclasses shouldn't do much on init,
            because of the whole asynchronous thing): false where it answered nil, for no path.
    */
    bool initWithPath(const std::optional<std::string>& path, uint32_t options);

    std::optional<std::string> path();

    /*	Load data, setting up _data, _format, _width, and _height; also _rowBytes
            if it's not _width * OOTextureComponentsForFormat(_format), and
            _originalWidth/_originalHeight if _width and _height for some reason aren't
            the original pixel dimensions.

            Thread-safety concerns: this will be called in a worker thread, and there
            may be several worker threads. The caller takes responsibility for
            autorelease pools and exception safety.

            Superclass will handle scaling and mip-map generation. Data must be
            allocated with malloc() family.
    */
    virtual void loadTexture();

    // OOAsyncWorkTask, through the facade: on a work thread, then on the main thread.
    void performAsyncTask();
    void completeAsyncTask();

    // The state (were the @protected ivars).
    std::string _path = { };

    OOTextureFlags _options = { };
    uint8_t _generateMipMaps : 1 = 0,
                               _scaleAsNormalMap : 1 = 0,
                               _avoidShrinking : 1 = 0,
                               _noScalingWhatsoever : 1 = 0,
                               _extractChannel : 1 = 0,
                               _allowCubeMap : 1 = 0,
                               _isCubeMap : 1 = 0,
                               _ready : 1 = 0;
    uint8_t _extractChannelIndex = { };
    OOTextureDataFormat _format = { };

    void* _data = { };
    uint32_t _width = { },
             _height = { },
             _originalWidth = { },
             _originalHeight = { },
             _shrinkThreshold = { },
             _maxSize = { };
    size_t _rowBytes = { };

private:
    static void setUp();

    void applySettings();
    void getDesiredWidth(OOPixMapDimension* outDesiredWidth, OOPixMapDimension* outDesiredHeight);
    void generateMipMapsForCubeMap();
};

} // namespace cxx

// Transitional: the Objective-C OOTextureLoader, for its callers and the loaders not yet
// converted. Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOTextureLoader+ObjCBridge.h"

#endif // OOTEXTURELOADER_H
