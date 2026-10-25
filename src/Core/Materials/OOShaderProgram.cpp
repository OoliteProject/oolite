/*

OOShaderProgram.m


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

#include "OOOpenGLExtensionManager.h"

#if OO_SHADERS

#include "OOShaderProgram.h"
#include "OOFunctionAttributes.h"
#include "OOStringParsing.h"
#include "ResourceManager.h"
#include "OOOpenGLExtensionManager.h"
#include "OOMacroOpenGL.h"
#include "OODebugFlags.h"
#include "Universe.h"
#include "MyOpenGLView.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"


namespace {

// What "%@" printed for a nil-able string.
std::string StringOrNull(const std::optional<std::string> &string)
{
	return string.value_or("(null)");
}


BOOL GetShaderSource(const std::optional<std::string> &fileName, const std::string &shaderType, std::optional<std::string> *outResult);
std::string GetGLSLInfoLog(GLhandleARB shaderObject);


// The game view's matrix manager, taken from the C++ view. Null when there is no universe or view.
OOOpenGLMatrixManager *GameViewMatrixManager()
{
	MyOpenGLView *view = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	return (view != nullptr) ? view->getOpenGLMatrixManager() : nullptr;
}

}	// namespace


/*	Cache key -> program, not retained: a program removes itself in its destructor. Was an
	Objective-C mutable dictionary of boxed values (bead oo-3rb.10); keys are the cache keys' UTF-8.
	Allocated on first use and never freed, as the dictionary was, so a program destroyed
	during exit never finds it destroyed.
*/
namespace {

std::unordered_map<std::string, OOShaderProgram *> *sShaderCache = NULL;

OOShaderProgram *CachedShaderProgram(const std::optional<std::string> &cacheKey)
{
	if (!cacheKey.has_value() || sShaderCache == NULL)  return nullptr;
	auto it = sShaderCache->find(*cacheKey);
	return (it != sShaderCache->end()) ? it->second : nullptr;
}

void CacheShaderProgram(const std::string &cacheKey, OOShaderProgram *program)
{
	if (sShaderCache == NULL)  sShaderCache = new std::unordered_map<std::string, OOShaderProgram *>;
	(*sShaderCache)[cacheKey] = program;
}


/*	The program in use, retained (sActiveProgram). Never destroyed, as the static pointer was not
	(proposed ADR-0056, amendment oo-smy item 3).
*/
oo::Ref<OOShaderProgram> &ActiveProgram()
{
	static auto *active = new oo::Ref<OOShaderProgram>;
	return *active;
}

}	// namespace


oo::Ref<OOShaderProgram> OOShaderProgram::shaderProgramWithVertexShader(const std::optional<std::string> &vertexShaderSource,
																		const std::optional<std::string> &fragmentShaderSource,
																		const std::optional<std::string> &vertexShaderName,
																		const std::optional<std::string> &fragmentShaderName,
																		const std::optional<std::string> &inPrefixString,			// String prepended to program source (both vs and fs)
																		const oo::PList &attributeBindings,	// Maps vertex attribute names to "locations".
																		const std::optional<std::string> &cacheKey)
{
	oo::Ref<OOShaderProgram>	result;
	std::optional<std::string>	prefixString = inPrefixString;

	if (prefixString.has_value() && prefixString->empty())  prefixString = std::nullopt;

	// Use cache to avoid creating duplicate shader programs -- saves on GPU resources and potentially state changes.
	// FIXME: probably needs to respond to graphics resets.
	result = oo::Ref<OOShaderProgram>(CachedShaderProgram(cacheKey));

	if (result == nullptr)
	{
		// No cached program; create one...
		result = oo::adopt(new OOShaderProgram());
		if (!result->initWithVertexShaderSource(vertexShaderSource,
												fragmentShaderSource,
												prefixString,
												vertexShaderName,
												fragmentShaderName,
												attributeBindings,
												cacheKey))  result = nullptr;

		if (result != nullptr && cacheKey.has_value())
		{
			// ...and add it to the cache.
			CacheShaderProgram(*cacheKey, result.get());	// the cache doesn't retain the program
		}
	}

	return result;
}


oo::Ref<OOShaderProgram> OOShaderProgram::shaderProgramWithVertexShaderName(const std::string &vertexShaderName,
																			const std::string &fragmentShaderName,
																			const std::optional<std::string> &inPrefixString,
																			const oo::PList &attributeBindings)
{
	std::string					cacheKey;
	oo::Ref<OOShaderProgram>	result;
	std::optional<std::string>	vertexSource;
	std::optional<std::string>	fragmentSource;
	std::optional<std::string>	prefixString = inPrefixString;

	if (prefixString.has_value() && prefixString->empty())  prefixString = std::nullopt;

	// Use cache to avoid creating duplicate shader programs -- saves on GPU resources and potentially state changes.
	// FIXME: probably needs to respond to graphics resets.
	cacheKey = "vertex:" + vertexShaderName + "\nfragment:" + fragmentShaderName + "\n----\n" + prefixString.value_or("");
	result = oo::Ref<OOShaderProgram>(CachedShaderProgram(cacheKey));

	if (result == nullptr)
	{
		// No cached program; create one...
		if (!GetShaderSource(vertexShaderName, "vertex", &vertexSource))  return nullptr;
		if (!GetShaderSource(fragmentShaderName, "fragment", &fragmentSource))  return nullptr;
		result = oo::adopt(new OOShaderProgram());
		if (!result->initWithVertexShaderSource(vertexSource,
												fragmentSource,
												prefixString,
												vertexShaderName,
												fragmentShaderName,
												attributeBindings,
												cacheKey))  result = nullptr;

		if (result != nullptr)
		{
			// ...and add it to the cache.
			CacheShaderProgram(cacheKey, result.get());	// the cache doesn't retain the program
		}
	}

	return result;
}


OOShaderProgram::~OOShaderProgram()
{
	OO_ENTER_OPENGL();

#ifndef NDEBUG
	// Cannot happen while being in use retains the program; kept as the old imbalance check.
	if (EXPECT_NOT(ActiveProgram() != nullptr && ActiveProgram().get() == this))
	{
		OO_LOG("shader.dealloc.imbalance", "{}", "***** OOShaderProgram deallocated while active, indicating a retain/release imbalance. Expect imminent crash.");
		// applyNone(), but not released: it is being destroyed.
		(void)ActiveProgram().leakRef();
		OOGL(glUseProgramObjectARB(NULL_SHADER));
	}
#endif

	if (key.has_value())
	{
		if (sShaderCache != NULL)  sShaderCache->erase(*key);
		key = std::nullopt;
	}

	OOGL(glDeleteObjectARB(_program));
}


void OOShaderProgram::apply()
{
	OO_ENTER_OPENGL();

	if (ActiveProgram().get() != this)
	{
		ActiveProgram() = oo::Ref<OOShaderProgram>(this);
		OOGL(glUseProgramObjectARB(_program));
		bindStandardMatrixUniforms();
	}
}


void OOShaderProgram::applyNone()
{
	OO_ENTER_OPENGL();

	if (ActiveProgram() != nullptr)
	{
		ActiveProgram() = nullptr;
		OOGL(glUseProgramObjectARB(NULL_SHADER));
	}
}


GLhandleARB OOShaderProgram::program()
{
	return _program;
}


namespace {

BOOL ValidateShaderObject(GLhandleARB object, const std::optional<std::string> &name)
{
	GLint		type, subtype = 0, status;
	GLenum		statusType;
	std::string	subtypeString;
	std::string	actionString;
	
	OO_ENTER_OPENGL();
	
	OOGL(glGetObjectParameterivARB(object, GL_OBJECT_TYPE_ARB, &type));
	BOOL linking = type == GL_PROGRAM_OBJECT_ARB;
	
	if (linking)
	{
		subtypeString = "shader program";
		actionString = "linking";
		statusType = GL_OBJECT_LINK_STATUS_ARB;
	}
	else
	{
		// FIXME
		OOGL(glGetObjectParameterivARB(object, GL_OBJECT_SUBTYPE_ARB, &subtype));
		switch (subtype)
		{
			case GL_VERTEX_SHADER_ARB:
				subtypeString = "vertex shader";
				break;
				
			case GL_FRAGMENT_SHADER_ARB:
				subtypeString = "fragment shader";
				break;
				
#if GL_EXT_geometry_shader4
			case GL_GEOMETRY_SHADER_EXT:
				subtypeString = "geometry shader";
				break;
#endif
				
			default:
				subtypeString = oo::str::format("<unknown shader type 0x%.4X>", subtype);
		}
		actionString = "compilation";
		statusType = GL_OBJECT_COMPILE_STATUS_ARB;
	}
	
	OOGL(glGetObjectParameterivARB(object, statusType, &status));
	if (status == GL_FALSE)
	{
		const std::string msgClass = oo::str::format("shader.%s.failure", linking ? "link" : "compile");
		OO_LOG_ERR(msgClass, "GLSL {} {} failed for {}:\n>>>>> GLSL log:\n{}\n", subtypeString, actionString, name.value_or("(null)"), GetGLSLInfoLog(object));
		return NO;
	}
	
#ifndef NDEBUG
	if (0 && (gDebugFlags & DEBUG_SHADER_VALIDATION))
	{
		OOGL(glValidateProgramARB(object));
		OOGL(glGetObjectParameterivARB(object, GL_OBJECT_VALIDATE_STATUS_ARB, &status));
		if (status == GL_FALSE)
		{
			const std::string msgClass = oo::str::format("shader.%s.validationFailure", linking ? "link" : "compile");
			OO_LOG_WARN(msgClass, "GLSL {} {} failed for {}:\n>>>>> GLSL log:\n{}\n", subtypeString, "validation", name.value_or("(null)"), GetGLSLInfoLog(object));
			return NO;
		}
	}
#endif
	
	return YES;
}

}	// namespace


bool OOShaderProgram::initWithVertexShaderSource(const std::optional<std::string> &vertexSource,
												 const std::optional<std::string> &fragmentSource,
												 const std::optional<std::string> &prefixString,
												 const std::optional<std::string> &vertexName,
												 const std::optional<std::string> &fragmentName,
												 const oo::PList &attributeBindings,
												 const std::optional<std::string> &inKey)
{
	BOOL					OK = YES;
	const GLcharARB			*sourceStrings[3] = { "", "#line 0\n", NULL };
	GLhandleARB				vertexShader = NULL_SHADER;
	GLhandleARB				fragmentShader = NULL_SHADER;

	OO_ENTER_OPENGL();

	// ([super init] could not fail: the object is already constructed.)

	if (OK && !vertexSource.has_value() && !fragmentSource.has_value())  OK = NO;	// Must have at least one shader!

	if (OK && prefixString.has_value())
	{
		sourceStrings[0] = prefixString->c_str();
	}

	if (OK && vertexSource.has_value())
	{
		// Compile vertex shader.
		OOGL(vertexShader = glCreateShaderObjectARB(GL_VERTEX_SHADER_ARB));
		if (vertexShader != NULL_SHADER)
		{
			sourceStrings[2] = vertexSource->c_str();
			OOGL(glShaderSourceARB(vertexShader, 3, sourceStrings, NULL));
			OOGL(glCompileShaderARB(vertexShader));

			OK = ValidateShaderObject(vertexShader, vertexName);
		}
		else  OK = NO;
	}

	if (OK && fragmentSource.has_value())
	{
		// Compile fragment shader.
		OOGL(fragmentShader = glCreateShaderObjectARB(GL_FRAGMENT_SHADER_ARB));
		if (fragmentShader != NULL_SHADER)
		{
			sourceStrings[2] = fragmentSource->c_str();
			OOGL(glShaderSourceARB(fragmentShader, 3, sourceStrings, NULL));
			OOGL(glCompileShaderARB(fragmentShader));

			OK = ValidateShaderObject(fragmentShader, fragmentName);
		}
		else  OK = NO;
	}

	if (OK)
	{
		// Link shader.
		OOGL(_program = glCreateProgramObjectARB());
		if (_program != NULL_SHADER)
		{
			if (vertexShader != NULL_SHADER)  OOGL(glAttachObjectARB(_program, vertexShader));
			if (fragmentShader != NULL_SHADER)  OOGL(glAttachObjectARB(_program, fragmentShader));
			bindAttributes(attributeBindings);
			OOGL(glLinkProgramARB(_program));

			OK = ValidateShaderObject(_program, StringOrNull(vertexName) + "/" + StringOrNull(fragmentName));
		}
		else  OK = NO;
	}

	if (OK)
	{
		key = inKey;
	}

	if (vertexShader != NULL_SHADER)  OOGL(glDeleteObjectARB(vertexShader));
	if (fragmentShader != NULL_SHADER)  OOGL(glDeleteObjectARB(fragmentShader));

	if (OK)
	{
		// The matrix manager is C++: taken from the C++ game view (null-guarded, as a message to
		// nil answered a null list).
		OOOpenGLMatrixManager *matrixManager = GameViewMatrixManager();
		standardMatrixUniformLocations = (matrixManager != nullptr) ? matrixManager->standardMatrixUniformLocations(_program) : oo::PList();
	}
	else
	{
		if (_program != NULL_SHADER)
		{
			OOGL(glDeleteObjectARB(_program));
			_program = NULL_SHADER;
		}

		// [self release]; self = nil: the factory drops the object.
	}
	return OK;
}


void OOShaderProgram::bindAttributes(const oo::PList &attributeBindings)
{
	OO_ENTER_OPENGL();

	if (!attributeBindings.isDict())  return;
	for (const auto &[attrKey, location] : *attributeBindings.getIf<oo::PList::Dict>())
	{
		OOGL(glBindAttribLocationARB(_program, attributeBindings.get<unsigned int>(attrKey), attrKey.c_str()));
	}
}

void OOShaderProgram::bindStandardMatrixUniforms()
{
	if (standardMatrixUniformLocations.isArray())
	{
		OOOpenGLMatrixManager *matrixManager = GameViewMatrixManager();

		OO_ENTER_OPENGL();

		// Null-guarded as messages to nil: nothing synced, and a zero matrix (amendment oo-vt0o item 3).
		if (matrixManager != nullptr)  matrixManager->syncModelView();
		for (const oo::PList &pair : *standardMatrixUniformLocations.getIf<oo::PList::Array>())
		{
			if (pair.isArray())
			{
				// -[nil compare:] answered 0, so an entry without a type string counts as "mat3".
				const oo::PList *typeName = pair.at<oo::PList>(2);
				const bool noTypeName = typeName == nullptr || !(typeName->isString() || typeName->isNumber());
				if (noTypeName || pair.at<std::string>(2) == "mat3")
				{
					OOGL(GLUniformMatrix3(pair.at<int>(0), matrixManager != nullptr ? matrixManager->getMatrix(pair.at<int>(1)) : kZeroMatrix));
				}
				else
				{
					OOMatrix matrix = matrixManager != nullptr ? matrixManager->getMatrix(pair.at<int>(1)) : kZeroMatrix;
					GLUniformMatrix(pair.at<int>(0), matrix);
				}
			}
		}
	}
	return;
}


namespace {

/*	Attempt to load fragment or vertex shader source from a file.
	Returns YES if source was loaded or no shader was specified, and NO if an
	external shader was specified but could not be found. (The prefix it took went unused.)
*/
BOOL GetShaderSource(const std::optional<std::string> &fileName, const std::string &shaderType, std::optional<std::string> *outResult)
{
	std::optional<std::string>	result;

	if (!fileName.has_value())  return YES;	// It's OK for one or the other of the shaders to be undefined.

	result = ResourceManager::stringFromFilesNamed(*fileName, "Shaders");
	if (!result.has_value())
	{
		const std::vector<std::string> extensions { shaderType, shaderType.substr(0, 4) };	// vertex and vert, or fragment and frag

		// Futureproofing -- in future, we may wish to support automatic selection between supported shader languages.
		if (!oo::str::pathHasExtensionIn(*fileName, extensions))
		{
			for (const std::string &extension : extensions)
			{
				result = ResourceManager::stringFromFilesNamed(oo::str::appendingPathExtension(*fileName, extension), "Shaders");
				if (result.has_value()) break;
			}
		}
		if (!result.has_value())
		{
			OO_LOG(cxx_kOOLogFileNotFound, "GLSL ERROR: failed to find fragment program {}.", *fileName);
			return NO;
		}
	}
	/*	
	if (result != nil && prefix != nil)
	{
		result = [prefix stringByAppendingString:result];
	}
	*/
	if (outResult != NULL) *outResult = result;
	return YES;
}


// Whether <bytes> is well-formed UTF-8 (shortest forms, no surrogates, at most U+10FFFF).
bool IsWellFormedUTF8(std::string_view bytes)
{
	std::size_t i = 0;
	while (i < bytes.size())
	{
		const unsigned char b = static_cast<unsigned char>(bytes[i]);
		std::size_t extra = 0;
		char32_t c = 0, minimum = 0;
		if (b < 0x80)  { ++i; continue; }
		else if ((b & 0xE0) == 0xC0)  { extra = 1; c = b & 0x1F; minimum = 0x80; }
		else if ((b & 0xF0) == 0xE0)  { extra = 2; c = b & 0x0F; minimum = 0x800; }
		else if ((b & 0xF8) == 0xF0)  { extra = 3; c = b & 0x07; minimum = 0x10000; }
		else  return false;
		if (i + extra >= bytes.size())  return false;
		for (std::size_t k = 1; k <= extra; ++k)
		{
			const unsigned char next = static_cast<unsigned char>(bytes[i + k]);
			if ((next & 0xC0) != 0x80)  return false;
			c = (c << 6) | (next & 0x3F);
		}
		if (c < minimum || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF))  return false;
		i += extra + 1;
	}
	return true;
}


// The info log as UTF-8: +stringWithUTF8String: of it, or (when that failed) its bytes read as
// ISO Latin-1.
std::string GetGLSLInfoLog(GLhandleARB shaderObject)
{
	GLint					length;
	GLcharARB				*log = NULL;
	std::string				result;

	OO_ENTER_OPENGL();

	if (EXPECT_NOT(shaderObject == NULL_SHADER))  return "(null)";	// what "%@" printed for the nil result

	OOGL(glGetObjectParameterivARB(shaderObject, GL_OBJECT_INFO_LOG_LENGTH_ARB, &length));
	log = (GLcharARB *)malloc(length);
	if (log == NULL)
	{
		length = 1024;
		log = (GLcharARB *)malloc(length);
		if (log == NULL)  return "<out of memory>";
	}
	OOGL(glGetInfoLogARB(shaderObject, length, NULL, log));

	result = log;
	if (!IsWellFormedUTF8(result))
	{
		result.clear();
		for (GLint i = 0; i < length - 1; ++i)
		{
			const unsigned char b = static_cast<unsigned char>(log[i]);
			if (b < 0x80)  result += static_cast<char>(b);
			else
			{
				result += static_cast<char>(0xC0 | (b >> 6));
				result += static_cast<char>(0x80 | (b & 0x3F));
			}
		}
	}
	free(log);
	
	return result;
}

}	// namespace

#endif // OO_SHADERS
