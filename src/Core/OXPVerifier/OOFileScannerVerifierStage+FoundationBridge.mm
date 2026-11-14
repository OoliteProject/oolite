/*

OOFileScannerVerifierStage+FoundationBridge.mm

TRANSITIONAL: see OOFileScannerVerifierStage+FoundationBridge.h. Each method forwards to its cxx_
counterpart and converts the result exactly as the old method produced it (nil for nil).

*/

#import "OOFileScannerVerifierStage.h" // declares the bridge category at its end

#if OO_OXP_VERIFIER_ENABLED

#import "OOFoundationBridge.h"

@implementation OOFileScannerVerifierStage (OOFoundationBridge)

- (BOOL)fileExists:(NSString*)file
          inFolder:(NSString*)folder
    referencedFrom:(NSString*)context
      checkBuiltIn:(BOOL)checkBuiltIn
{
    return [self cxx_fileExists:oo::OptionalString(file) inFolder:oo::OptionalString(folder) referencedFrom:oo::OptionalString(context) checkBuiltIn:checkBuiltIn];
}

- (NSString*)pathForFile:(NSString*)file
                inFolder:(NSString*)folder
          referencedFrom:(NSString*)context
            checkBuiltIn:(BOOL)checkBuiltIn
{
    return oo::NSStringOrNil([self cxx_pathForFile:oo::OptionalString(file) inFolder:oo::OptionalString(folder) referencedFrom:oo::OptionalString(context) checkBuiltIn:checkBuiltIn]);
}

- (id)plistNamed:(NSString*)file
          inFolder:(NSString*)folder
    referencedFrom:(NSString*)context
      checkBuiltIn:(BOOL)checkBuiltIn
{
    return oo::ObjectFromPList([self cxx_plistNamed:oo::OptionalString(file) inFolder:oo::OptionalString(folder) referencedFrom:oo::OptionalString(context) checkBuiltIn:checkBuiltIn]);
}

- (id)displayNameForFile:(NSString*)file andFolder:(NSString*)folder
{
    return oo::NSStringOrNil([self cxx_displayNameForFile:oo::OptionalString(file) andFolder:oo::OptionalString(folder)]);
}

- (NSArray*)filesInFolder:(NSString*)folder
{
    const std::optional<std::vector<std::string>> files = [self cxx_filesInFolder:oo::OptionalString(folder)];
    return files.has_value() ? oo::NSArrayFromStrings(*files) : nil;
}

@end

#endif
