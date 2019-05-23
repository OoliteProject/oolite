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

#import "OOProbabilisticTextureManager.h"
#import "ResourceManager.h"
#import "OOTexture.h"
#import "OOCollectionExtractors.h"
#import "PlayerEntityScriptMethods.h"


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
	NSUInteger			i, count, j;
	id					entry = nil;
	NSString			*name = nil;
	float				probability;
	OOTexture			*texture = nil;
	int 				galID = -1;
	id					object = nil;

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
		_galaxy = malloc(sizeof *_galaxy * count);
		_probMaxGal = malloc(sizeof *_probMaxGal * kOOMaximumGalaxyID);

		if (_textures == NULL || _prob == NULL || _galaxy == NULL)  OK = NO;
	}
	
	if (OK)
	{
		for (i = 0; i <= kOOMaximumGalaxyID; i++) _probMaxGal[i] = 0;

		//  Go through list and load textures.
		for (i = 0; i != count; ++i)
		{
			entry = [config objectAtIndex:i];
			galID = -1;
			if ([entry isKindOfClass:[NSDictionary class]])
			{
				name = [(NSDictionary *)entry oo_stringForKey:@"texture"];
				probability = [entry oo_floatForKey:@"probability" defaultValue:1.0f];
				object = [entry objectForKey:@"galaxy"];
				if ([object isKindOfClass:[NSString class]])  
				{
					galID = [object intValue];
				}
				else if (object != nil)
				{
					OOLog(@"textures.load", @"***** ERROR: %@ for texture %@ is not a string.", @"galaxy", name);
				}
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
					_prob[_count] = probability + (galID >= 0 ? _probMaxGal[galID] : _probMax);
					_galaxy[_count] = (galID >= 0 ? galID : -1);
					if (galID >= 0) {
						_probMaxGal[galID] += probability;
					}
					else
					{
						for (j = 0; j <= kOOMaximumGalaxyID; j++) _probMaxGal[j] += probability;
						_probMax += probability;
					}
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
	if (_galaxy != NULL)  free(_galaxy);
	if (_probMaxGal != NULL)  free(_probMaxGal);

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
	int						hold = -1;
	int                		galID = (int)[PLAYER currentGalaxyID];

	selection = randfWithSeed(&_seed);
	
	selection *= _probMaxGal[galID];
	
	for (i = 0; i != _count; ++i)
	{
		if (_galaxy[i] == -1 || _galaxy[i] == galID)
		{
			// make a note of the index of the first texture that meets the galaxy list criteria (but only if _galaxy is set)
			if (hold == -1 && _prob[i] > 0 && _galaxy[i] == galID) hold = i;
			if (selection <= _prob[i])  return _textures[i];
		}
	}
	
	// first catch point if loop above fails to return a texture
	// return first texture that meets the galaxy list criteria and has a probability > 0
	if (hold >= 0) 
	{
		OOLog(@"probabilisticTextureManager.internalWarning", @"%s: overrun! Galaxy List requirements not met. Choosing first texture available for galaxy.", __PRETTY_FUNCTION__);
		return _textures[hold];
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
