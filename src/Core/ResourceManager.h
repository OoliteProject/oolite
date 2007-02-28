/*

ResourceManager.h

Singleton class responsible for loading various data files.

For Oolite
Copyright (C) 2004  Giles C Williams

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOCocoa.h"
#import "OOOpenGL.h"

#ifdef GNUSTEP
#import "SDLImage.h"
#endif


#define OOLITE_EXCEPTION_XML_PARSING_FAILURE	@"OOXMLException"
#define OOLITE_EXCEPTION_FATAL					@"OoliteFatalException"

@class OOSound, OOMusic;

typedef struct
{
	NSString*		tag;		// name of the tag
	NSObject*		content;	// content of tag
} OOXMLElement;

extern int debug;

BOOL always_include_addons;

@interface ResourceManager : NSObject
{
	NSMutableArray  *paths;
}

- (id) initIncludingAddOns: (BOOL) include_addons;

+ (NSString *) errors;
+ (NSMutableArray *) paths;
+ (NSMutableArray *) pathsUsingAddOns:(BOOL) include_addons;
+ (BOOL) areRequirementsFulfilled:(NSDictionary*) requirements;
+ (void) addExternalPath:(NSString *)filename;

+ (NSDictionary *) dictionaryFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles;
+ (NSDictionary *) dictionaryFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles smart:(BOOL) smartMerge;
+ (NSArray *) arrayFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles;

+ (OOSound *) ooSoundNamed:(NSString *)filename inFolder:(NSString *)foldername;
+ (OOMusic *) ooMusicNamed:(NSString *)filename inFolder:(NSString *)foldername;

#ifndef GNUSTEP
+ (NSImage *) imageNamed:(NSString *)filename inFolder:(NSString *)foldername;
#endif
+ (NSString *) stringFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername;
#ifdef GNUSTEP
+ (SDLImage *) surfaceNamed:(NSString *)filename inFolder:(NSString *)foldername;
#endif

+ (NSMutableArray *) scanTokensFromString:(NSString*) values;
+ (NSString *) decodeString:(NSString*) encodedString;
+ (OOXMLElement) parseOOXMLElement:(NSScanner*) scanner upTo:(NSString*)closingTag;
+ (NSObject*) parseXMLPropertyList:(NSString*)xmlString;
+ (NSObject*) objectFromXMLElement:(NSArray*) xmlElement;
+ (NSNumber*) trueFromXMLContent:(NSObject*) xmlContent;
+ (NSNumber*) falseFromXMLContent:(NSObject*) xmlContent;
+ (NSNumber*) realFromXMLContent:(NSObject*) xmlContent;
+ (NSNumber*) integerFromXMLContent:(NSObject*) xmlContent;
+ (NSString*) stringFromXMLContent:(NSObject*) xmlContent;
+ (NSDate*) dateFromXMLContent:(NSObject*) xmlContent;
+ (NSData*) dataFromXMLContent:(NSObject*) xmlContent;
+ (NSArray*) arrayFromXMLContent:(NSObject*) xmlContent;
+ (NSDictionary*) dictionaryFromXMLContent:(NSObject*) xmlContent;

+ (NSString*) stringFromGLFloats: (GLfloat*) float_array : (int) n_floats;
+ (void) GLFloatsFromString: (NSString*) float_string: (GLfloat*) float_array;

+ (NSString*) stringFromNSPoint: (NSPoint) point;
+ (NSPoint) NSPointFromString: (NSString*) point_string;

+ (NSDictionary *) loadScripts;
@end
