/*
	
	OOTexture.m
	
	Copyright (C) 2007-2013 Jens Ayton and contributors
	
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

#include "OOTexture.h"
#include "OOTextureInternal.h"
#include "OOConcreteTexture.h"
#include "OONullTexture.h"

#include "OOTextureLoader.h"
#include "OOTextureGenerator.h"

#include "Universe.h"
#include "ResourceManager.h"
#include "OOOpenGLExtensionManager.h"
#include "OOMacroOpenGL.h"
#include "OOCPUInfo.h"
#include "OOCache.h"
#include "OOObjCPList.h"
#include "OOPixMap.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListGet.hpp"

#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>


namespace {

// Used only by "internal" specifiers from cxx_OOMakeTextureSpecifier.
const char * const kOOTextureSpecifierFlagValueInternalKey = "_oo_internal_flags";

}	// namespace


/*	Texture caching:
	two and a half parallel caching mechanisms are used. sLiveTextureCache
	tracks all live texture objects with cache keys, without retaining them
	(a std::unordered_map of raw pointers keyed by the cache key's UTF-8).
	
	sAllLiveTextures tracks all textures, including ones without cache keys,
	so that they can be notified of graphics resets. This also holds raw
	pointers to avoid retaining the textures.
	
	sRecentTextures tracks up to kRecentTexturesCount textures which
	have been used recently, and retains them.
	
	This means that the number of live texture objects will never fall below
	80% of kRecentTexturesCount (80% comes from the behaviour of OOCache), but
	old textures will eventually be released. If the number of active textures
	exceeds kRecentTexturesCount, all of them will be reusable through
	sLiveTextureCache, but only a most-recently-fetched subset will be kept
	around by the cache when the number drops.
	
	Note the textures in sRecentTextures are a superset of the textures in
	sLiveTextureCache, and the textures in sLiveTextureCache are a superset
	of sRecentTextures.
*/
enum
{
	kRecentTexturesCount		= 50
};

namespace {

// Allocated on first use and never freed, so a texture deallocated during exit never finds them
// destroyed. Were a Foundation mutable dictionary / set of boxed pointers (bead oo-3rb.10).
// They hold the C++ textures.
std::unordered_map<std::string, OOTexture *>	*sLiveTextureCache;
std::unordered_set<OOTexture *>				*sAllLiveTextures;
// The textures, retained, as Object nodes (OOTextureObjectNode(); bead oo-9ht.99).
OOCache				*sRecentTextures;

}	// namespace


static BOOL					sCheckedExtensions;
OOTextureInfo				gOOTextureInfo;


#ifndef NDEBUG
namespace {

const char *sGlobalTraceContext = nullptr;

}	// namespace

#define SET_TRACE_CONTEXT(str) do { sGlobalTraceContext = (str); } while (0)
#else
#define SET_TRACE_CONTEXT(str) do { } while (0)
#endif
#define CLEAR_TRACE_CONTEXT() SET_TRACE_CONTEXT(nullptr)


OOTexture::NameFactory OOTexture::nameFactory = &OOTexture::loadTextureWithName;
OOTexture::ConfigurationFactory OOTexture::configurationFactory = &OOTexture::loadTextureWithConfiguration;


oo::Ref<OOTexture> OOTexture::textureWithName(const std::optional<std::string> &name,
											  const std::optional<std::string> &directory,
											  OOTextureFlags options,
											  GLfloat anisotropy,
											  GLfloat lodBias)
{
	return nameFactory(name, directory, options, anisotropy, lodBias);
}


oo::Ref<OOTexture> OOTexture::loadTextureWithName(const std::optional<std::string> &name,
												  const std::optional<std::string> &directory,
												  OOTextureFlags options,
												  GLfloat anisotropy,
												  GLfloat lodBias)
{
	std::string					key;
	oo::Ref<OOTexture>			result;
	std::optional<std::string>	path;
	BOOL						noFNF;

	if (EXPECT_NOT(!name.has_value()))  return nullptr;
	if (EXPECT_NOT(!sCheckedExtensions))  checkExtensions();

	if (!gOOTextureInfo.anisotropyAvailable || (options & kOOTextureMinFilterMask) != kOOTextureMinFilterMipMap)
	{
		anisotropy = 0.0f;
	}
	if (!gOOTextureInfo.textureLODBiasAvailable || (options & kOOTextureMinFilterMask) != kOOTextureMinFilterMipMap)
	{
		lodBias = 0.0f;
	}

	noFNF = (options & kOOTextureNoFNFMessage) != 0;
	options = OOApplyTextureOptionDefaults(options & ~kOOTextureNoFNFMessage);

	// Look for existing texture
	key = OOGenerateTextureCacheKey(directory, *name, options, anisotropy, lodBias);
	result = oo::Ref<OOTexture>(existingTextureForKey(key));
	if (result == nullptr)
	{
		path = ResourceManager::pathForFileNamed(*name, directory);
		if (!path.has_value())
		{
			if (!noFNF)  OO_LOG_WARN(cxx_kOOLogFileNotFound, "Could not find texture file \"{}\".", *name);
			return nullptr;
		}

		// No existing texture, load texture.
		result = ::OOConcreteTexture::initWithPath(*path, key, options, anisotropy, lodBias);
	}


	return result;
}


oo::Ref<OOTexture> OOTexture::textureWithName(const std::optional<std::string> &name,
											  const std::optional<std::string> &directory)
{
	return loadTextureWithName(name,
						   directory,
						   kOOTextureDefaultOptions,
						   kOOTextureDefaultAnisotropy,
						   kOOTextureDefaultLODBias);
}


oo::Ref<OOTexture> OOTexture::textureWithConfiguration(const oo::PList &configuration)
{
	return configurationFactory(configuration);
}


oo::Ref<OOTexture> OOTexture::loadTextureWithConfiguration(const oo::PList &configuration)
{
	return textureWithConfiguration(configuration, 0);
}


oo::Ref<OOTexture> OOTexture::textureWithConfiguration(const oo::PList &configuration, OOTextureFlags extraOptions)
{
	std::string				name;
	OOTextureFlags			options = 0;
	GLfloat					anisotropy = 0.0f;
	GLfloat					lodBias = 0.0f;

	if (!cxx_OOInterpretTextureSpecifier(configuration, &name, &options, &anisotropy, &lodBias, NO))  return nullptr;

	return loadTextureWithName(name, "Textures", options | extraOptions, anisotropy, lodBias);
}


oo::Ref<OOTexture> OOTexture::nullTexture()
{
	// The shared null texture, which OONullTexture keeps for the life of the process (its facade,
	// kept here until bead oo-9ht.99, was the same object whenever it was asked).
	return oo::Ref<OOTexture>(::OONullTexture::sharedNullTexture());
}


oo::Ref<OOTexture> OOTexture::textureWithGenerator(::OOTextureGenerator *generator)
{
	return textureWithGenerator(generator, false);
}


oo::Ref<OOTexture> OOTexture::textureWithGenerator(::OOTextureGenerator *generator, bool enqueue)
{
	if (generator == nullptr)  return nullptr;
	::OOTextureGenerator *cxxGenerator = generator;	// C++ since bead oo-9ht.118 deleted the generator's facade

#ifndef OOTEXTURE_NO_CACHE
	OOTexture *existing = existingTextureForKey(cxxGenerator->cacheKey());
	if (existing != nullptr && !enqueue)  return oo::Ref<OOTexture>(existing);
#endif

	if (!cxxGenerator->enqueue())
	{
		OO_LOG_ERR("texture.generator.queue.failed", "Failed to queue generator {}", generator->description());
		return nullptr;
	}
	OO_LOG("texture.generator.queue", "Queued texture generator {}", generator->description());

	oo::Ref<OOTexture> result = ::OOConcreteTexture::initWithLoader(generator,
																	 cxxGenerator->cacheKey(),
																	 OOApplyTextureOptionDefaults(cxxGenerator->textureOptions()),
																	 cxxGenerator->anisotropy(),
																	 cxxGenerator->lodBias());

	return result;
}


OOTexture::OOTexture()
{
	if (EXPECT_NOT(sAllLiveTextures == NULL))  sAllLiveTextures = new std::unordered_set<OOTexture *>;
	sAllLiveTextures->insert(this);
}


OOTexture::~OOTexture()
{
	if (sAllLiveTextures != NULL)  sAllLiveTextures->erase(this);
}


void OOTexture::apply()
{
	OOLogGenericSubclassResponsibility();
}


void OOTexture::applyNone()
{
	OO_ENTER_OPENGL();
	OOGL(glBindTexture(GL_TEXTURE_2D, 0));
#if OO_TEXTURE_CUBE_MAP
	if (OOCubeMapsAvailable())  OOGL(glBindTexture(GL_TEXTURE_CUBE_MAP, 0));
#endif

#if GL_EXT_texture_lod_bias
	if (gOOTextureInfo.textureLODBiasAvailable)  OOGL(glTexEnvf(GL_TEXTURE_FILTER_CONTROL_EXT, GL_TEXTURE_LOD_BIAS_EXT, 0));
#endif
}


void OOTexture::ensureFinishedLoading()
{
}


bool OOTexture::isFinishedLoading()
{
	return true;
}


std::optional<std::string> OOTexture::cacheKey()
{
	return std::nullopt;
}


NSSize OOTexture::dimensions()
{
	OOLogGenericSubclassResponsibility();
	return NSZeroSize;
}


NSSize OOTexture::originalDimensions()
{
	return dimensions();
}


bool OOTexture::isMipMapped()
{
	OOLogGenericSubclassResponsibility();
	return false;
}


OOPixMap OOTexture::copyPixMapRepresentation()
{
	return kOONullPixMap;
}


bool OOTexture::isRectangleTexture()
{
	return false;
}


bool OOTexture::isCubeMap()
{
	return false;
}


NSSize OOTexture::texCoordsScale()
{
	return NSMakeSize(1.0, 1.0);
}


GLint OOTexture::glTextureName()
{
	OOLogGenericSubclassResponsibility();
	return 0;
}


void OOTexture::clearCache()
{
	/*	Does not clear sAllLiveTextures - that really must refer to all
		live texture objects.
	*/
	SET_TRACE_CONTEXT("clearing sLiveTextureCache");
	if (sLiveTextureCache != NULL)  sLiveTextureCache->clear();

	SET_TRACE_CONTEXT("clearing sRecentTextures");
	// [sRecentTextures autorelease]: released at the drain of the nearest oo::AutoreleaseScope, as
	// upstream's pool did; the only caller, Universe::reinitAndShowDemo(), runs in the frame loop's
	// or the start-up's scope (ADR-0056 amendment oo-31u.9).
	oo::autorelease(sRecentTextures);
	sRecentTextures = nullptr;
	CLEAR_TRACE_CONTEXT();
}


void OOTexture::rebindAllTextures()
{
	// Keeping around unused, cached textures is unhelpful at this point.
	OOCache *recentTextures = sRecentTextures;	// DESTROY(): cleared before the release
	sRecentTextures = nullptr;
	oo::release(recentTextures);

	if (sAllLiveTextures == NULL)  return;
	// A copy: the set is unordered (as the Foundation set was) and must not change under the loop.
	const std::vector<OOTexture *> textures(sAllLiveTextures->begin(), sAllLiveTextures->end());
	for (OOTexture *texture : textures)
	{
		texture->forceRebind();
	}
}


#ifndef NDEBUG
std::vector<oo::Ref<OOTexture>> OOTexture::cachedTexturesByAge()
{
	std::vector<oo::Ref<OOTexture>> result;
	for (const oo::PList &texture : (sRecentTextures != nullptr) ? sRecentTextures->pListsByAge() : std::vector<oo::PList>())
	{
		result.emplace_back(OOTextureInObjectNode(texture));
	}
	return result;
}


std::vector<oo::Ref<OOTexture>> OOTexture::allTextures()
{
	std::vector<oo::Ref<OOTexture>> result;
	if (sAllLiveTextures != NULL)
	{
		result.reserve(sAllLiveTextures->size());
		for (OOTexture *texture : *sAllLiveTextures)  result.emplace_back(texture);
	}

	return result;
}


size_t OOTexture::dataSize()
{
	NSSize dimensions = this->dimensions();
	size_t size = dimensions.width * dimensions.height;
	if (isCubeMap())  size *= 6;
	if (isMipMapped())  size = size * 4 / 3;

	return size;
}


std::optional<std::string> OOTexture::name()
{
	OOLogGenericSubclassResponsibility();
	return std::nullopt;
}


void OOTexture::setTrace(bool trace)
{
	if (trace && !_trace)
	{
		OO_LOG("texture.allocTrace.begin", "Started tracing texture {} with retain count {}.", oo::str::pointerDescription(this), retainCount());
	}
	_trace = trace;
}
#endif


std::optional<std::string> OOTexture::descriptionComponents() const
{
	return std::nullopt;
}


std::optional<std::string> OOTexture::shortDescriptionComponents() const
{
	return std::nullopt;
}


namespace {

// The C++ class's name, as the facade's -cxx_description named it.
std::string ClassName(const OOTexture &texture)
{
	int status = 0;
	char *demangled = abi::__cxa_demangle(typeid(texture).name(), nullptr, nullptr, &status);
	std::string result = (status == 0 && demangled != nullptr) ? demangled : typeid(texture).name();
	std::free(demangled);
	return result;
}

}	// namespace


std::string OOTexture::description() const
{
	std::string result = oo::str::format("<%s %s>", ClassName(*this).c_str(), oo::str::pointerDescription(this).c_str());
	if (const std::optional<std::string> components = descriptionComponents())  result += "{" + *components + "}";
	return result;
}


std::string OOTexture::shortDescription() const
{
	std::string result = oo::str::format("<OOTexture %s>", oo::str::pointerDescription(this).c_str());
	if (const std::optional<std::string> components = shortDescriptionComponents())  result += "{" + *components + "}";
	return result;
}


std::string OOTexture::className() const
{
	return "OOTexture";
}


void OOTexture::forceRebind()
{
	OOLogGenericSubclassResponsibility();
}


void OOTexture::addToCaches()
{
#ifndef OOTEXTURE_NO_CACHE
	const std::optional<std::string> cacheKey = this->cacheKey();
	if (!cacheKey.has_value())  return;

	// Add self to in-use textures cache, as a raw pointer so the texture isn't retained by the cache.
	if (EXPECT_NOT(sLiveTextureCache == NULL))  sLiveTextureCache = new std::unordered_map<std::string, OOTexture *>;

	SET_TRACE_CONTEXT("in-use textures cache - SHOULD NOT RETAIN");
	(*sLiveTextureCache)[*cacheKey] = this;
	CLEAR_TRACE_CONTEXT();

	// Add self to recent textures cache.
	if (EXPECT_NOT(sRecentTextures == nullptr))
	{
		sRecentTextures = OOCache::cacheWithPList(oo::PList()).leakRef();
		sRecentTextures->setName(std::string("recent textures"));
		sRecentTextures->setAutoPrune(true);
		sRecentTextures->setPruneThreshold(kRecentTexturesCount);
	}

	SET_TRACE_CONTEXT("adding to recent textures cache");
	sRecentTextures->setPList(OOTextureObjectNode(this), *cacheKey);
	CLEAR_TRACE_CONTEXT();
#endif
}


void OOTexture::removeFromCaches()
{
#ifndef OOTEXTURE_NO_CACHE
	const std::optional<std::string> cacheKey = this->cacheKey();
	if (!cacheKey.has_value())  return;

	if (sLiveTextureCache != NULL)  sLiveTextureCache->erase(*cacheKey);
	// Called from a texture's destructor: the cached texture is compared by address.
	OOTexture *cached = OOTextureInObjectNode((sRecentTextures != nullptr) ? sRecentTextures->pListForKey(*cacheKey) : oo::PList());
	if (EXPECT_NOT(cached != nullptr && cached == this))
	{
		/* Experimental for now: I think the recent crash problems may
		 * be because if the last reference to a texture is in
		 * sRecentTextures, and the texture is regenerated, it
		 * replaces the texture, causing a release. Therefore, if this
		 * texture *isn't* overretained in the texture cache, the 2009
		 * crash avoider will delete its replacement from the cache
		 * ... possibly before that texture has been fully added to
		 * the cache itself. So, the texture is only removed from the
		 * cache by key if it was in it with that key. The extra time
		 * needed to generate a planet texture compared with loading a
		 * standard one may be why this problem shows up.  - CIM 20140122
		 */
		OOCAssert(0, "Texture retain count error for %s; cacheKey is %s.", cached->description().c_str(), cacheKey->c_str()); //miscount in autorelease
		// The following line is needed in order to avoid crashes when there's a 'texture retain count error'. Please do not delete. -- Kaks 20091221
		sRecentTextures->removePListForKey(*cacheKey); // make sure there's no reference left inside sRecentTexture ( was a show stopper for 1.73)
	}
#endif
}


OOTexture *OOTexture::existingTextureForKey(const std::optional<std::string> &key)
{
#ifndef OOTEXTURE_NO_CACHE
	if (key.has_value())
	{
		if (sLiveTextureCache == NULL)  return nullptr;
		auto it = sLiveTextureCache->find(*key);
		return (it != sLiveTextureCache->end()) ? it->second : nullptr;
	}
	return nullptr;
#else
	return nullptr;
#endif
}


void OOTexture::checkExtensions()
{
	OO_ENTER_OPENGL();

	sCheckedExtensions = YES;

	OOOpenGLExtensionManager	*extMgr = OOOpenGLExtensionManager::sharedManager();
	BOOL						ver120 = extMgr->versionIsAtLeastMajor(1, 2);
	BOOL						ver130 = extMgr->versionIsAtLeastMajor(1, 3);

#if GL_EXT_texture_filter_anisotropic
	gOOTextureInfo.anisotropyAvailable = extMgr->haveExtension("GL_EXT_texture_filter_anisotropic") ? 1 : 0;
	OOGL(glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &gOOTextureInfo.anisotropyScale));
	{
		const oo::PList anisoScale = oo::Defaults::standard().object("texture-anisotropy-scale");
		gOOTextureInfo.anisotropyScale *= OOClamp_0_1_f(oo::PListGet<float>::from(anisoScale.isNull() ? nullptr : &anisoScale, 0.5f));
	}
#endif

#ifdef GL_CLAMP_TO_EDGE
	gOOTextureInfo.clampToEdgeAvailable = ver120 || extMgr->haveExtension("GL_SGIS_texture_edge_clamp");
#endif

#if OO_GL_CLIENT_STORAGE
	gOOTextureInfo.clientStorageAvailable = extMgr->haveExtension("GL_APPLE_client_storage") ? 1 : 0;
#endif

	gOOTextureInfo.textureMaxLevelAvailable = ver120 || extMgr->haveExtension("GL_SGIS_texture_lod");

#if GL_EXT_texture_lod_bias
	{
		const oo::PList lodBias = oo::Defaults::standard().object("use-texture-lod-bias");
		if (oo::PListGet<bool>::from(lodBias.isNull() ? nullptr : &lodBias, true))
		{
			gOOTextureInfo.textureLODBiasAvailable = extMgr->haveExtension("GL_EXT_texture_lod_bias") ? 1 : 0;
		}
		else
		{
			gOOTextureInfo.textureLODBiasAvailable = NO;
		}
	}
#endif

#if GL_EXT_texture_rectangle
	gOOTextureInfo.rectangleTextureAvailable = extMgr->haveExtension("GL_EXT_texture_rectangle");
#endif

#if OO_TEXTURE_CUBE_MAP
	if (!oo::Defaults::standard().boolForKey("disable-cube-maps"))
	{
		gOOTextureInfo.cubeMapAvailable = ver130 || extMgr->haveExtension("GL_ARB_texture_cube_map");
	}
	else
	{
		gOOTextureInfo.cubeMapAvailable = NO;
	}

#endif
}

oo::PList cxx_OOTextureSpecFromObject(const oo::PList &object, const std::optional<std::string> &defaultName)
{
	oo::PList value = object;
	if (value.isNull())
	{
		if (!defaultName.has_value())  return oo::PList();
		value = oo::PList(*defaultName);
	}
	if (const std::string *name = value.getIf<std::string>())
	{
		if (name->empty())  return oo::PList();
		return oo::PList(oo::PList::Dict{ { "name", value } });
	}
	if (!value.isDict())  return oo::PList();

	// If we're here, it's a dictionary. (A "name" as the old string extractor read it: a string or a number.)
	const oo::PList *name = value.find("name");
	if (!defaultName.has_value() || (name != nullptr && (name->isString() || name->isNumber())))  return value;
	
	// If we get here, there's no "name" key and there is a default, so we fill it in:
	oo::PList::Dict mutableResult = *value.getIf<oo::PList::Dict>();
	mutableResult["name"] = oo::PList(*defaultName);
	return oo::PList(std::move(mutableResult));
}


uint8_t OOTextureComponentsForFormat(OOTextureDataFormat format)
{
	switch (format)
	{
		case kOOTextureDataRGBA:
			return 4;
			
		case kOOTextureDataGrayscale:
			return 1;
			
		case kOOTextureDataGrayscaleAlpha:
			return 2;
			
		case kOOTextureDataInvalid:
			break;
	}
	
	return 0;
}


BOOL OOCubeMapsAvailable(void)
{
	return gOOTextureInfo.cubeMapAvailable;
}


BOOL cxx_OOInterpretTextureSpecifier(const oo::PList &specifier, std::string *outName, OOTextureFlags *outOptions, float *outAnisotropy, float *outLODBias, BOOL ignoreExtract)
{
	std::string			name;
	OOTextureFlags		options = kOOTextureDefaultOptions;
	float				anisotropy = kOOTextureDefaultAnisotropy;
	float				lodBias = kOOTextureDefaultLODBias;
	
	if (const std::string *string = specifier.getIf<std::string>())
	{
		name = *string;
	}
	else if (specifier.isDict())
	{
		// The old string extractor gave nil unless the value was a string or a number.
		const oo::PList *nameValue = specifier.find(cxx_kOOTextureSpecifierNameKey);
		if (nameValue == nullptr || !(nameValue->isString() || nameValue->isNumber()))
		{
			OO_LOG("texture.load.noName", "Invalid texture configuration dictionary (must specify name):\n{}", oo::DescriptionOf(specifier));
			return NO;
		}
		name = specifier.get<std::string>(cxx_kOOTextureSpecifierNameKey);
		
		int quickFlags = specifier.get<int>(kOOTextureSpecifierFlagValueInternalKey, -1);
		if (quickFlags != -1)
		{
			options = quickFlags;
		}
		else
		{
			std::string filterString = specifier.get<std::string>(cxx_kOOTextureSpecifierMinFilterKey, "default");
			if (filterString == "nearest")  options |= kOOTextureMinFilterNearest;
			else if (filterString == "linear")  options |= kOOTextureMinFilterLinear;
			else if (filterString == "mipmap")  options |= kOOTextureMinFilterMipMap;
			else  options |= kOOTextureMinFilterDefault;	// Covers "default"
			
			filterString = specifier.get<std::string>(cxx_kOOTextureSpecifierMagFilterKey, "default");
			if (filterString == "nearest")  options |= kOOTextureMagFilterNearest;
			else  options |= kOOTextureMagFilterLinear;	// Covers "default" and "linear"
			
			if (specifier.get<bool>(cxx_kOOTextureSpecifierNoShrinkKey, false))  options |= kOOTextureNoShrink;
			if (specifier.get<bool>(cxx_kOOTextureSpecifierExtraShrinkKey, false))  options |= kOOTextureExtraShrink;
			if (specifier.get<bool>(cxx_kOOTextureSpecifierRepeatSKey, false))  options |= kOOTextureRepeatS;
			if (specifier.get<bool>(cxx_kOOTextureSpecifierRepeatTKey, false))  options |= kOOTextureRepeatT;
			if (specifier.get<bool>(cxx_kOOTextureSpecifierCubeMapKey, false))  options |= kOOTextureAllowCubeMap;
			
			if (!ignoreExtract)
			{
				const oo::PList *extractValue = specifier.find("extract_channel");
				if (extractValue != nullptr && (extractValue->isString() || extractValue->isNumber()))
				{
					const std::string extractChannel = specifier.get<std::string>("extract_channel");
					if (extractChannel == "r")  options |= kOOTextureExtractChannelR;
					else if (extractChannel == "g")  options |= kOOTextureExtractChannelG;
					else if (extractChannel == "b")  options |= kOOTextureExtractChannelB;
					else if (extractChannel == "a")  options |= kOOTextureExtractChannelA;
					else
					{
						OO_LOG_WARN("texture.load.extractChannel.invalid", "Unknown value \"{}\" for extract_channel in specifier \"{}\" (should be \"r\", \"g\", \"b\" or \"a\").", extractChannel, oo::DescriptionOf(specifier));
					}
				}
			}
		}
		anisotropy = specifier.get<float>("anisotropy", kOOTextureDefaultAnisotropy);
		lodBias = specifier.get<float>("texture_LOD_bias", kOOTextureDefaultLODBias);
	}
	else
	{
		// Bad type
		// "got" names an object's class, or the property-list type (it was the class of the Foundation
		// object built for the value, such as GSInlineArray). An Object node held no Objective-C object
		// (none is made since bead oo-4aq6a.5): nil's class, "(null)", as before.
		if (!specifier.isNull())  OO_LOG(cxx_kOOLogParameterError, "{}: expected string or dictionary, got {}.", __PRETTY_FUNCTION__, (specifier.type() == oo::PList::Type::Object) ? std::string("(null)") : std::string(oo::typeName(specifier.type())));
		return NO;
	}
	
	if (name.empty())  return NO;
	
	if (outName != NULL)  *outName = name;
	if (outOptions != NULL)  *outOptions = options;
	if (outAnisotropy != NULL)  *outAnisotropy = anisotropy;
	if (outLODBias != NULL)  *outLODBias = lodBias;
	
	return YES;
}


oo::PList cxx_OOMakeTextureSpecifier(const std::string &name, OOTextureFlags options, float anisotropy, float lodBias, BOOL internal)
{
	oo::PList::Dict result;
	
	result[cxx_kOOTextureSpecifierNameKey] = oo::PList(name);
	
	// -oo_setFloat:forKey: stored +numberWithFloat:, -oo_setUnsignedInteger: +numberWithUnsignedInteger:.
	if (anisotropy != kOOTextureDefaultAnisotropy)  result[cxx_kOOTextureSpecifierAnisotropyKey] = oo::PList::singleReal(anisotropy);
	if (lodBias != kOOTextureDefaultLODBias)  result[cxx_kOOTextureSpecifierLODBiasKey] = oo::PList::singleReal(lodBias);
	
	if (internal)
	{
		result[kOOTextureSpecifierFlagValueInternalKey] = oo::PList::unsignedInteger(options);
	}
	else
	{
		const char *value = nullptr;
		switch (options & kOOTextureMinFilterMask)
		{
			case kOOTextureMinFilterDefault:
				break;
				
			case kOOTextureMinFilterNearest:
				value = "nearest";
				break;
				
			case kOOTextureMinFilterLinear:
				value = "linear";
				break;
				
			case kOOTextureMinFilterMipMap:
				value = "mipmap";
				break;
		}
		if (value != nullptr)  result[cxx_kOOTextureSpecifierNoShrinkKey] = oo::PList(value);
		
		value = nullptr;
		switch (options & kOOTextureMagFilterMask)
		{
			case kOOTextureMagFilterNearest:
				value = "nearest";
				break;
				
			case kOOTextureMagFilterLinear:
				break;
		}
		if (value != nullptr)  result[cxx_kOOTextureSpecifierMagFilterKey] = oo::PList(value);
		
		value = nullptr;
		switch (options & kOOTextureExtractChannelMask)
		{
			case kOOTextureExtractChannelNone:
				break;
				
			case kOOTextureExtractChannelR:
				value = "r";
				break;
				
			case kOOTextureExtractChannelG:
				value = "g";
				break;
				
			case kOOTextureExtractChannelB:
				value = "b";
				break;
				
			case kOOTextureExtractChannelA:
				value = "a";
				break;
		}
		if (value != nullptr)  result[cxx_kOOTextureSpecifierSwizzleKey] = oo::PList(value);
		
		if (options & kOOTextureNoShrink)  result[cxx_kOOTextureSpecifierNoShrinkKey] = oo::PList(true);
		if (options & kOOTextureRepeatS)  result[cxx_kOOTextureSpecifierRepeatSKey] = oo::PList(true);
		if (options & kOOTextureRepeatT)  result[cxx_kOOTextureSpecifierRepeatTKey] = oo::PList(true);
		if (options & kOOTextureAllowCubeMap)  result[cxx_kOOTextureSpecifierCubeMapKey] = oo::PList(true);
	}
	
	return oo::PList(std::move(result));
}


OOTextureFlags OOApplyTextureOptionDefaults(OOTextureFlags options)
{
	// Set default flags if needed
	if ((options & kOOTextureMinFilterMask) == kOOTextureMinFilterDefault)
	{
		if ((UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false))
		{
			options |= kOOTextureMinFilterLinear;
		}
		else
		{
			options |= kOOTextureMinFilterMipMap;
		}
	}
	
	if (!gOOTextureInfo.textureMaxLevelAvailable)
	{
		/*	In the unlikely case of an OpenGL system without GL_SGIS_texture_lod,
		 disable mip-mapping completely. Strictly this is only needed for
		 non-square textures, but extra logic for such a rare case isn't
		 worth it.
		 */
		if ((options & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap)
		{
			options ^= kOOTextureMinFilterMipMap ^ kOOTextureMinFilterLinear;
		}
	}
	
	if (options & kOOTextureAllowRectTexture)
	{
		// Apply rectangle texture restrictions (regardless of whether rectangle textures are available, for consistency)
		options &= kOOTextureFlagsAllowedForRectangleTexture;
		if ((options & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap)
		{
			options = (kOOTextureMinFilterMask & ~kOOTextureMinFilterMask) | kOOTextureMinFilterLinear;
		}
		
#if GL_EXT_texture_rectangle
		if (!gOOTextureInfo.rectangleTextureAvailable)
		{
			options &= ~kOOTextureAllowRectTexture;
		}
#else
		options &= ~kOOTextureAllowRectTexture;
#endif
	}
	
	options &= kOOTextureDefinedFlags;
	
	return options;
}


std::string OOGenerateTextureCacheKey(const std::optional<std::string> &directory, const std::string &name, OOTextureFlags options, float anisotropy, float lodBias)
{
	if (!gOOTextureInfo.anisotropyAvailable || (options & kOOTextureMinFilterMask) != kOOTextureMinFilterMipMap)
	{
		anisotropy = 0.0f;
	}
	if (!gOOTextureInfo.textureLODBiasAvailable || (options & kOOTextureMinFilterMask) != kOOTextureMinFilterMipMap)
	{
		lodBias = 0.0f;
	}
	options = OOApplyTextureOptionDefaults(options & ~kOOTextureNoFNFMessage);
	
	return oo::str::format("%s%s%s:0x%.4X/%g/%g", directory.has_value() ? directory->c_str() : "", directory.has_value() ? "/" : "", name.c_str(), options, anisotropy, lodBias);
}


std::string cxx_OOTextureCacheKeyForSpecifier(const oo::PList &specifier)
{
	// Left as initialised when the specifier is not understood (they were uninitialised).
	std::string name;
	OOTextureFlags options = 0;
	float anisotropy = 0.0f;
	float lodBias = 0.0f;
	
	cxx_OOInterpretTextureSpecifier(specifier, &name, &options, &anisotropy, &lodBias, NO);
	return OOGenerateTextureCacheKey("Textures", name, options, anisotropy, lodBias);
}
