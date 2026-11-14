/*

OOProbabilisticTextureManager.m


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

#include "OOProbabilisticTextureManager.h"
#include "OOTexture.h"
#include "PlayerEntityScriptMethods.h"
#include "ResourceManager.h"

#include "oofnd/String.hpp"

namespace {

// oo_stringForKey: a string, a number's string value, or nil (Foundation sweep, proposed ADR-0043).
std::optional<std::string> OptionalStringForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dict.get<std::string>(key);
}

} // namespace

oo::Ref<OOProbabilisticTextureManager> OOProbabilisticTextureManager::createWithPListName(const std::string& plistName,
    uint32_t options,
    GLfloat anisotropy,
    GLfloat lodBias)
{
    return createWithPListName(plistName,
        options,
        anisotropy,
        lodBias,
        RANROTGetFullSeed());
}

// -initWithPListName:...seed: on a new object; null where it answered nil (amendment oo-fg7i item 1).
oo::Ref<OOProbabilisticTextureManager> OOProbabilisticTextureManager::createWithPListName(const std::string& plistName,
    uint32_t options,
    GLfloat anisotropy,
    GLfloat lodBias,
    RANROTSeed seed)
{
    oo::Ref<OOProbabilisticTextureManager> manager = oo::adopt(new OOProbabilisticTextureManager);
    if (!manager->initWithPListName(plistName, options, anisotropy, lodBias, seed))
        return nullptr;
    return manager;
}

bool OOProbabilisticTextureManager::initWithPListName(const std::string& plistName,
    uint32_t options,
    GLfloat anisotropy,
    GLfloat lodBias,
    RANROTSeed seed)
{
    bool OK = true;
    oo::PList config;
    NSUInteger i, count, j;
    const oo::PList* entry = nullptr;
    std::optional<std::string> name;
    float probability = 0.0f; // set wherever name is (GCC -Wmaybe-uninitialized; bead oo-1q4)
    oo::Ref<OOTexture> texture;
    int galID = -1;
    const oo::PList* object = nullptr;

    if (OK) {
        config = ResourceManager::arrayFromFilesNamed(plistName, "Config", YES);
        if (!config)
            OK = false;
    }

    if (OK) {
        count = config.count();

        _textures = (OOTexture**)malloc(sizeof *_textures * count);
        _prob = (float*)malloc(sizeof *_prob * count);
        _galaxy = (int*)malloc(sizeof *_galaxy * count);
        _probMaxGal = (float*)malloc(sizeof *_probMaxGal * (kOOMaximumGalaxyID + 1));

        if (_textures == NULL || _prob == NULL || _galaxy == NULL)
            OK = false;
    }

    if (OK) {
        for (i = 0; i <= kOOMaximumGalaxyID; i++)
            _probMaxGal[i] = 0;

        //  Go through list and load textures.
        for (i = 0; i != count; ++i) {
            entry = config.at(i);
            galID = -1;
            if (entry->isDict()) {
                name = OptionalStringForKey(*entry, "texture");
                probability = entry->get<float>("probability", 1.0f);
                object = entry->find("galaxy");
                if (object != nullptr && object->isString()) {
                    galID = oo::str::intValue(*object->getIf<std::string>());
                } else if (object != nullptr) {
                    OO_LOG("textures.load", "***** ERROR: {} for texture {} is not a string.", "galaxy", name.value_or("(null)"));
                }
            } else if (entry->isString()) {
                name = *entry->getIf<std::string>();
                probability = 1.0f;
            } else {
                name = std::nullopt;
            }

            if (name.has_value() && 0.0f < probability) {
                texture = OOTexture::textureWithName(name, "Textures", options, anisotropy, lodBias);
                if (texture != nullptr) {
                    _textures[_count] = oo::Ref<OOTexture>(texture).leakRef(); // released in the destructor
                    _prob[_count] = probability + (galID >= 0 ? _probMaxGal[galID] : _probMax);
                    _galaxy[_count] = (galID >= 0 ? galID : -1);
                    if (galID >= 0) {
                        _probMaxGal[galID] += probability;
                    } else {
                        for (j = 0; j <= kOOMaximumGalaxyID; j++)
                            _probMaxGal[j] += probability;
                        _probMax += probability;
                    }
                    ++_count;
                }
            }
        }

        if (_count == 0)
            OK = false;
    }

    if (OK)
        _seed = seed;

    return OK;
}

OOProbabilisticTextureManager::~OOProbabilisticTextureManager()
{
    unsigned i;

    if (_textures != NULL) {
        for (i = 0; i != _count; ++i) {
            oo::release(_textures[i]);
        }
        free(_textures);
    }

    if (_prob != NULL)
        free(_prob);
    if (_galaxy != NULL)
        free(_galaxy);
    if (_probMaxGal != NULL)
        free(_probMaxGal);
}

// OOObject's -description wrapped this as "<OOProbabilisticTextureManager 0x...>{...}", the text
// this class's own -description printed (proposed ADR-0043).
std::optional<std::string> OOProbabilisticTextureManager::descriptionComponents() const
{
    return oo::str::format("%u textures, cumulative probability=%g", _count, _probMax);
}

OOTexture* OOProbabilisticTextureManager::selectTexture()
{
    float selection;
    unsigned i;
    int hold = -1;
    int galID = (int)(PLAYER != nullptr ? PLAYER->PlayerEntity::currentGalaxyID() : 0); // qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it

    selection = randfWithSeed(&_seed);

    selection *= _probMaxGal[galID];

    for (i = 0; i != _count; ++i) {
        if (_galaxy[i] == -1 || _galaxy[i] == galID) {
            // make a note of the index of the first texture that meets the galaxy list criteria (but only if _galaxy is set)
            if (hold == -1 && _prob[i] > 0 && _galaxy[i] == galID)
                hold = i;
            if (selection <= _prob[i])
                return _textures[i];
        }
    }

    // first catch point if loop above fails to return a texture
    // return first texture that meets the galaxy list criteria and has a probability > 0
    if (hold >= 0) {
        OO_LOG("probabilisticTextureManager.internalWarning", "{}: overrun! Galaxy List requirements not met. Choosing first texture available for galaxy.", __PRETTY_FUNCTION__);
        return _textures[hold];
    }

    OO_LOG("probabilisticTextureManager.internalFailure", "{}: overrun! Choosing last texture.", __PRETTY_FUNCTION__);
    return _textures[_count - 1];
}

unsigned OOProbabilisticTextureManager::textureCount()
{
    return _count;
}

void OOProbabilisticTextureManager::ensureTexturesLoaded()
{
    unsigned i;

    for (i = 0; i != _count; ++i) {
        _textures[i]->ensureFinishedLoading();
    }
}

RANROTSeed OOProbabilisticTextureManager::seed()
{
    return _seed;
}

void OOProbabilisticTextureManager::setSeed(RANROTSeed seed)
{
    _seed = seed;
}
