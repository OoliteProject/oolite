/*
	plistSchemaValidator
	
	Test rig for OOPListSchemaVerifier, and also a tool for checking plists
	against schemata.
	
	Usage: first argument should be a plist specifying a schema. Subsequent
	arguments are files to test against the schema.
 
	Build requirements:
	  * Foundation
	  * OOPListSchemaVerifier
	  * OOLogging
		- OOLogOutputHandler (currently Mac-only)
		  - OOAsyncQueue
	  * OOCollectionExtractors
		- OOStringParsing.m
		- OOMaths, OOVector, OOQuaternion
		  - OOFastArithmetic.m (currently PPC-only)
	  * legacy_random.c
*/

#define OO_OXP_VERIFIER_ENABLED 1

#import <stdlib.h>
#import <Foundation/Foundation.h>
#import "OOPListSchemaVerifier.h"
#import "OOLogging.h"
#import "OOMaths.h"


@interface VerifierDelegate: NSObject
{
	BOOL _notedDelgatedTypes;
}
@end


static void RegisterPhonyDefaults(void);
static OOPListSchemaVerifier *GetVerifier(const char *path);
static void Verify(OOPListSchemaVerifier *verifier, const char *path);
static id ReadPList(const char *path);


int main(int argc, const char * argv[])
{
    NSAutoreleasePool		*pool = nil;
	OOPListSchemaVerifier	*verifier = nil;
	unsigned				i;
	
	[[NSAutoreleasePool alloc] init];
	
	RegisterPhonyDefaults();
	OOLoggingInit();
	
	if (argc < 3)
	{
		OOLog(@"badUsage", @"Usage: %s schema file [, file...]", argc ? argv[0] : "plistschemaverifier");
		return EXIT_FAILURE;
	}
	
	verifier = GetVerifier(argv[1]);
	for (i = 2; i != argc; ++i)
	{
		pool = [[NSAutoreleasePool alloc] init];
		Verify(verifier, argv[i]);
		[pool release];
	}
	
    return EXIT_SUCCESS;
}


static void RegisterPhonyDefaults(void)
{
	NSDictionary			*defaults = nil;
	
	defaults = [NSMutableDictionary dictionaryWithObjectsAndKeys:
					[NSNumber numberWithBool:NO], @"logging-show-class",
					[NSNumber numberWithBool:YES], @"logging-echo-to-stderr",
					nil];
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}


static OOPListSchemaVerifier *GetVerifier(const char *path)
{
	id						schema = nil;
	OOPListSchemaVerifier	*verifier = nil;
	VerifierDelegate		*delegate = nil;
	
	schema = ReadPList(path);
	if (schema == nil)
	{
		OOLog(@"badSchema", @"Could not read schema.");
		exit(EXIT_FAILURE);
	}
	
	verifier = [OOPListSchemaVerifier verifierWithSchema:schema];
	if (verifier == nil)
	{
		OOLog(@"badSchema", @"Could not interpret %s as a schema.", path);
		exit(EXIT_FAILURE);
	}
	
	delegate = [[VerifierDelegate alloc] init];
	[verifier setDelegate:delegate];
	
	return verifier;
}


static void Verify(OOPListSchemaVerifier *verifier, const char *path)
{
	id						plist = nil;
	NSString				*name = nil;
	
	plist = ReadPList(path);
	if (plist != nil)
	{
		name = [NSString stringWithUTF8String:path];
		if (name == nil)  name = [NSString stringWithCString:path];
		name = [name lastPathComponent];
		
		OOLog(@"verifying", @"Verifying %@:", name);
		OOLogIndent();
		if ([verifier verifyPropertyList:plist named:name])
		{
			OOLog(@"verifying.success", @"OK.");
		}
		OOLogOutdent();
	}
}


static id ReadPList(const char *path)
{
	NSString				*nsPath = nil;
	NSData					*data = nil;
	id						result = nil;
	NSString				*error = nil;
	
	nsPath = [NSString stringWithUTF8String:path];
	if (nsPath == nil)  nsPath = [NSString stringWithCString:path];
	
	if (nsPath == nil)
	{
		OOLog(@"badPath", @"Could not interpret \"%s\" as a path.", path);
		exit(EXIT_FAILURE);
	}
	
	data = [[NSData alloc] initWithContentsOfFile:nsPath];
	if (data == nil)
	{
		OOLog(@"readError", @"Could not read %@.", nsPath);
		exit(EXIT_FAILURE);
	}
	
	result = [NSPropertyListSerialization propertyListFromData:data
											  mutabilityOption:NSPropertyListImmutable
														format:NULL 
											  errorDescription:&error];
	[data release];
	if (result == nil)
	{
		OOLog(@"badPList", @"Could not interpret contents of %@ as a property list: %@.", nsPath, error);
	}
	
	return result;
}


@implementation VerifierDelegate

- (BOOL)verifier:(OOPListSchemaVerifier *)verifier
withPropertyList:(id)rootPList
		   named:(NSString *)name
	testProperty:(id)subPList
		  atPath:(NSArray *)keyPath
	 againstType:(NSString *)typeKey
		   error:(NSError **)outError
{
	if (!_notedDelgatedTypes)
	{
		OOLog(@"delegatedTypes", @"Plist schema uses delegated types; all delegated types will be treated as matching.");
		_notedDelgatedTypes = YES;
	}
	
	return YES;
}

@end


/****** Shims *******
Everything beyond this point is stuff that's needed to link, but whose full
behaviour is not needed.
*/

@interface ResourceManager: NSObject
+ (NSArray *)rootPaths;
@end


@implementation ResourceManager
+ (NSArray *)rootPaths
{
	return [NSArray array];
}
@end


NSDictionary *OODictionaryFromFile(NSString *path)
{
	return [NSDictionary dictionaryWithContentsOfFile:path];
}

static NSString * const kOOLogStringVectorConversion			= @"strings.conversion.vector";
static NSString * const kOOLogStringQuaternionConversion		= @"strings.conversion.quaternion";

BOOL ScanVectorFromString(NSString *xyzString, Vector *outVector)
{
	GLfloat					xyz[] = {0.0, 0.0, 0.0};
	int						i = 0;
	NSString				*error = nil;
	NSScanner				*scanner = nil;
	
	if (xyzString == nil) return NO;
	else if (outVector == NULL) error = @"nil result pointer";
	
	if (!error) scanner = [NSScanner scannerWithString:xyzString];
	while (![scanner isAtEnd] && i < 3 && !error)
	{
		if (![scanner scanFloat:&xyz[i++]])  error = @"could not scan a float value.";
	}
	
	if (!error && i < 3)  error = @"found less than three float values.";
	
	if (!error)
	{
		*outVector = make_vector(xyz[0], xyz[1], xyz[2]);
		return YES;
	}
	else
	{
		OOLog(kOOLogStringVectorConversion, @"***** ERROR cannot make vector from '%@': %@", xyzString, error);
		return NO;
	}
}


BOOL ScanQuaternionFromString(NSString *wxyzString, Quaternion *outQuaternion)
{
	GLfloat					wxyz[] = {1.0, 0.0, 0.0, 0.0};
	int						i = 0;
	NSString				*error = nil;
	NSScanner				*scanner = nil;
	
	if (wxyzString == nil) return NO;
	else if (outQuaternion == NULL) error = @"nil result pointer";
	
	if (!error) scanner = [NSScanner scannerWithString:wxyzString];
	while (![scanner isAtEnd] && i < 4 && !error)
	{
		if (![scanner scanFloat:&wxyz[i++]])  error = @"could not scan a float value.";
	}
	
	if (!error && i < 4)  error = @"found less than four float values.";
	
	if (!error)
	{
		outQuaternion->w = wxyz[0];
		outQuaternion->x = wxyz[1];
		outQuaternion->y = wxyz[2];
		outQuaternion->z = wxyz[3];
		quaternion_normalize(outQuaternion);
		return YES;
	}
	else
	{
		OOLog(kOOLogStringQuaternionConversion, @"***** ERROR cannot make quaternion from '%@': %@", wxyzString, error);
		return NO;
	}
}

