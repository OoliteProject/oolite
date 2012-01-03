/*

OOLight.m


Copyright (C) 2008-2012 Jens Ayton

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

#import "OOLight.h"
#include <limits.h>
#import "OOFunctionAttributes.h"
#import "Universe.h"


enum
{
	kLightCount = 8
};


static OOLight *sBindings[kLightCount] = { nil };


OOINLINE GLenum LightIndexToGLLight(OOLightIndex idx)  INLINE_CONST_FUNC;
OOINLINE GLenum LightIndexToGLLight(OOLightIndex idx)
{
	return GL_LIGHT0 + idx;
}


OOINLINE BOOL ComponentsEqual(OORGBAComponents a, OORGBAComponents b)
{
	return	a.r == b.r &&
			a.g == b.g &&
			a.b == b.b &&
			a.a == b.a;
}


@interface OOLight (OOPrivate)

- (void) updateWithGlobalAmbient:(OORGBAComponents *)ioAmbient;

@end


@implementation OOLight

- (id) init
{
	return [self initWithAmbient:nil
						 diffuse:nil
						specular:nil];
}


- (id) initWithAmbient:(OOColor *)ambient
			   diffuse:(OOColor *)diffuse
			  specular:(OOColor *)specular
{
	OORGBAComponents		amb = { 0.0f, 0.0f, 0.0f, 1.0f },
							dif = { 0.8f, 0.8f, 0.8f, 1.0f },
							spc = { 0.8f, 0.8f, 0.8f, 1.0f };
	
	if (ambient != nil)  amb = [ambient rgbaComponents];
	if (diffuse != nil)  dif = [diffuse rgbaComponents];
	if (specular != nil)  spc = [specular rgbaComponents];
	
	return [self initWithAmbientRGBA:amb
						 diffuseRGBA:dif
						specularRGBA:spc];
}

- (id) initWithAmbientRGBA:(OORGBAComponents)ambient
			   diffuseRGBA:(OORGBAComponents)diffuse
			  specularRGBA:(OORGBAComponents)specular
{
	self = [super init];
	if (self != nil)
	{
		_ambient = ambient;
		_diffuse = diffuse;
		_specular = specular;
		_bound = kOOLightNotBound;
	}
	return self;
}


- (void) dealloc
{
	[self unbindLight];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"color: %@, position: %@", OORGBAComponentsDescription(_diffuse), VectorDescription(_position)];
}


- (void) bindToLight:(OOLightIndex)lightNumber
{
	if (lightNumber != _bound)
	{
		// Can't be bound to more than one light number.
		[self unbindLight];
		
		if (lightNumber < kLightCount)
		{
			// Can't have more than one light bound to a light number.
			[OOLight unbindLight:lightNumber];
			
			// Apply binding.
			sBindings[lightNumber] = self;
			glEnable(LightIndexToGLLight(_bound));
			_dirty = YES;
			_bound = lightNumber;
		}
	}
}


- (BOOL) bound
{
	return _bound != kOOLightNotBound;
}


- (OOLightIndex) boundLight
{
	return _bound;
}


- (void) unbindLight
{
	const float zerofv[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	
	if (_bound != kOOLightNotBound)
	{
		// Apply non-lighting to light.
		// In addition to disabling the light, we set its colours to zero, for shaders.
		glDisable(LightIndexToGLLight(_bound));
		glLightfv(LightIndexToGLLight(_bound), GL_AMBIENT, zerofv);
		glLightfv(LightIndexToGLLight(_bound), GL_DIFFUSE, zerofv);
		glLightfv(LightIndexToGLLight(_bound), GL_SPECULAR, zerofv);
		
		sBindings[_bound] = nil;
		_bound = kOOLightNotBound;
	}
}


+ (void) unbindLight:(OOLightIndex)lightNumber
{
	if (lightNumber < kLightCount)
	{
		[sBindings[lightNumber] unbindLight];
	}
}


+ (OOLight *) boundLight:(OOLightIndex)lightNumber
{
	if (lightNumber < kLightCount)
	{
		return sBindings[lightNumber];
	}
	else
	{
		return nil;
	}
}


+ (void) unbindAllLights
{
	OOLightIndex		i;
	
	for (i = 0; i < kLightCount; i++)
	{
		[self unbindLight:i];
	}
}


+ (void) updateLights
{
	OOLightIndex		i;
	OORGBAComponents	ambient = { 0.0f, 0.0f, 0.0f, 1.0f };
	
	// Update all lights with changes.
	for (i = 0; i < kLightCount; i++)
	{
		if (sBindings[i] != nil)
		{
			/* if (sBindings[i]->_dirty) */  [sBindings[i] updateWithGlobalAmbient:&ambient];
			
			ambient.r += sBindings[i]->_ambient.r * sBindings[i]->_ambient.a;
			ambient.g += sBindings[i]->_ambient.g * sBindings[i]->_ambient.a;
			ambient.b += sBindings[i]->_ambient.b * sBindings[i]->_ambient.a;
		}
	}
	
	CheckOpenGLErrors(@"After updating lights.");
	
	float val[4] = { ambient.r, ambient.g, ambient.b, ambient.a };
	glLightModelfv(GL_LIGHT_MODEL_AMBIENT, val);
	
	CheckOpenGLErrors(@"After updating ambient lighting.");
}


- (Vector) position
{
	return _position;
}


- (void) setPosition:(Vector)position
{
	if (!vector_equal(_position, position))
	{
		_position = position;
		_dirty = YES;
	}
}


- (OOColor *) ambient
{
	return [OOColor colorWithRGBAComponents:_ambient];
}


- (OORGBAComponents) ambientRGBA
{
	return _ambient;
}


- (void) setAmbient:(OOColor *)color
{
	[self setAmbientRGBA:[color rgbaComponents]];
}


- (void) setAmbientRGBA:(OORGBAComponents)components
{
	if (!ComponentsEqual(_ambient, components))
	{
		_ambient = components;
		_dirty = YES;
	}
}


- (OOColor *) diffuse
{
	return [OOColor colorWithRGBAComponents:_diffuse];
}


- (OORGBAComponents) diffuseRGBA
{
	return _diffuse;
}


- (void) setDiffuse:(OOColor *)color
{
	[self setDiffuseRGBA:[color rgbaComponents]];
}


- (void) setDiffuseRGBA:(OORGBAComponents)components
{
	if (!ComponentsEqual(_diffuse, components))
	{
		_diffuse = components;
		_dirty = YES;
	}
}


- (OOColor *) specular
{
	return [OOColor colorWithRGBAComponents:_specular];
}


- (OORGBAComponents) specularRGBA
{
	return _specular;
}


- (void) setSpecular:(OOColor *)color
{
	[self setSpecularRGBA:[color rgbaComponents]];
}


- (void) setSpecularRGBA:(OORGBAComponents)components
{
	if (!ComponentsEqual(_specular, components))
	{
		_specular = components;
		_dirty = YES;
	}
}

@end


@implementation OOLight (OOPrivate)

- (void) updateWithGlobalAmbient:(OORGBAComponents *)ioAmbient
{
	float				val[4];
	
#define APPLY_COLOR(n, c)	val[0] = c.r; \
							val[1] = c.g; \
							val[2] = c.b; \
							val[3] = c.a; \
							glLightfv(LightIndexToGLLight(_bound), n, val);
	
	APPLY_COLOR(GL_DIFFUSE, _diffuse);
	APPLY_COLOR(GL_SPECULAR, _specular);
	
	// ModelView matrix? Never heard of it, guv.
	Vector pos = _position;
//	mult_vector_gl_matrix(&pos, [UNIVERSE activeViewMatrix]);
	val[0] = pos.x;
	val[1] = pos.y;
	val[2] = pos.z;
	val[3] = 1.0f;
	glLightfv(LightIndexToGLLight(_bound), GL_POSITION, val);
	_dirty = NO;
}

@end
