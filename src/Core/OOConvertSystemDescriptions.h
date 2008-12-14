#import <Foundation/Foundation.h>


/*	Functions to convert system descriptions between dictionary and array
	formats.
	
	The array format is used in descriptions.plist. Each set of strings is an
	array, the sets are stored in a master array, and cross-references are
	indices into the master array.
	
	The dictionary format is more human-friendly, with string sets identified
	by name and cross-references using names.
	
	The indicesToKeys parameter is optional; if it is nil or incomplete,
	indices or (index-based) keys will be synthesized.
*/
NSArray *OOConvertSystemDescriptionsToArrayFormat(NSDictionary *descriptionsInDictionaryFormat, NSDictionary *indicesToKeys);
NSDictionary *OOConvertSystemDescriptionsToDictionaryFormat(NSArray *descriptionsInArrayFormat, NSDictionary *indicesToKeys);

NSString *OOStringifySystemDescriptionLine(NSString *line, NSDictionary *indicesToKeys, BOOL useFallback);

//	Higher-level functions to drive the entire conversion.
void CompileSystemDescriptions(BOOL asXML);
void ExportSystemDescriptions(BOOL asXML);


