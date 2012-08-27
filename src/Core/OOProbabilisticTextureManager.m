/*

OOProbabilisticTextureManager.m


Copyright (C) 2007-2012 Jens Ayton

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

#import "OOProbabilisticTextureManager.h"
#import "ResourceManager.h"
#import "OOTexture.h"
#import "OOCollectionExtractors.h"


@implementation OOProbabilisticTextureManager

- (id)initWithPListName:(NSString *)plistName 
				options:(uint32_t)options
			 anisotropy:(GLfloat)anisotropy
				lodBias:(GLfloat)lodBias
{
	return [self initWithPListName:plistName
						   options:options
						anisotropy:anisotropy
						   lodBias:lodBias
							  seed:RANROTGetFullSeed()];
}


- (id)initWithPListName:(NSString *)plistName 
				options:(uint32_t)options
			 anisotropy:(GLfloat)anisotropy
				lodBias:(GLfloat)lodBias
				   seed:(RANROTSeed)seed
{
	BOOL				OK = YES;
	NSArray				*config = nil;
	OOUInteger			i, count;
	id					entry = nil;
	NSString			*name = nil;
	float				probability;
	OOTexture			*texture = nil;
	
	self = [super init];
	if (self == nil)  OK = NO;
	
	if (OK)
	{
		config = [ResourceManager arrayFromFilesNamed:plistName inFolder:@"Config" andMerge:YES];
		if (config == nil)  OK = NO;
	}
	
	if (OK)
	{
		count = [config count];
		
		_textures = malloc(sizeof *_textures * count);
		_prob = malloc(sizeof *_prob * count);
		
		if (_textures == NULL || _prob == NULL)  OK = NO;
	}
	
	if (OK)
	{
		//  Go through list and load textures.
		for (i = 0; i != count; ++i)
		{
			entry = [config objectAtIndex:i];
			if ([entry isKindOfClass:[NSDictionary class]])
			{
				name = [(NSDictionary *)entry oo_stringForKey:@"texture"];
				probability = [entry oo_floatForKey:@"probability" defaultValue:1.0f];
			}
			else if ([entry isKindOfClass:[NSString class]])
			{
				name = entry;
				probability = 1.0f;
			}
			else
			{
				name = nil;
			}
			
			if (name != nil && 0.0f < probability)
			{
				texture = [OOTexture textureWithName:name
											inFolder:@"Textures"
											 options:options
										  anisotropy:anisotropy
											 lodBias:lodBias];
				if (texture != nil)
				{
					_textures[_count] = [texture retain];
					_prob[_count] = probability + _probMax;
					_probMax += probability;
					++_count;
				}
			}
		}
		
		if (_count == 0) OK = NO;
	}
	
	if (OK)  _seed = seed;
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	
	return self;
}


- (void)dealloc
{
	unsigned				i;
	
	if (_textures != NULL)
	{
		for (i = 0; i != _count; ++i)
		{
			[_textures[i] release];
		}
		free(_textures);
	}
	
	if (_prob != NULL)  free(_prob);
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{%u textures, cumulative probability=%g}", [self class], self, _count, _probMax];
}


- (OOTexture *)selectTexture
{
	float					selection;
	unsigned				i;
	
	selection = randfWithSeed(&_seed);
	
	selection *= _probMax;
	
	for (i = 0; i != _count; ++i)
	{
		if (selection <= _prob[i])  return _textures[i];
	}
	
	OOLog(@"probabilisticTextureManager.internalFailure", @"%s: overrun! Choosing last texture.", __PRETTY_FUNCTION__);
	return _textures[_count - 1];
}


- (unsigned)textureCount
{
	return _count;
}


- (void)ensureTexturesLoaded
{
	unsigned				i;
	
	for (i = 0; i != _count; ++i)
	{
		[_textures[i] ensureFinishedLoading];
	}
}


- (RANROTSeed)seed
{
	return _seed;
}


- (void)setSeed:(RANROTSeed)seed
{
	_seed = seed;
}

@end
