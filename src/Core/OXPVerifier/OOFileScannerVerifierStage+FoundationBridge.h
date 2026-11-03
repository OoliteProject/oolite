/*

OOFileScannerVerifierStage+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-56tr). OOFileScannerVerifierStage's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in OOFileScannerVerifierStage.h. It exists so that the verifier stages
that call it compile unchanged; each caller moves to the cxx_ API in its own sweep bead. When
`git grep` finds no caller of anything declared here, the bridge bead deletes this file,
OOFileScannerVerifierStage+FoundationBridge.mm, its line in OXPVerifier/meson.build and the #import
at the end of OOFileScannerVerifierStage.h. Never add to it; never call it from migrated code.
oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2007-2013 Jens Ayton (OOFileScannerVerifierStage.h)

*/

// Imported only from the end of OOFileScannerVerifierStage.h (which declares everything used
// here); never import it directly, and never import OOFileScannerVerifierStage.h from it (a cycle).
#ifndef OOFILESCANNERVERIFIERSTAGE_FOUNDATIONBRIDGE_H
#define OOFILESCANNERVERIFIERSTAGE_FOUNDATIONBRIDGE_H

@interface OOFileScannerVerifierStage (OOFoundationBridge)

- (BOOL)fileExists:(NSString*)file
          inFolder:(NSString*)folder
    referencedFrom:(NSString*)context
      checkBuiltIn:(BOOL)checkBuiltIn; // -> -cxx_fileExists:inFolder:referencedFrom:checkBuiltIn:

- (NSString*)pathForFile:(NSString*)file
                inFolder:(NSString*)folder
          referencedFrom:(NSString*)context
            checkBuiltIn:(BOOL)checkBuiltIn; // -> -cxx_pathForFile:inFolder:referencedFrom:checkBuiltIn:

- (id)plistNamed:(NSString*)file // Only uses "real" plist parser, not homebrew.
          inFolder:(NSString*)folder
    referencedFrom:(NSString*)context
      checkBuiltIn:(BOOL)checkBuiltIn; // -> -cxx_plistNamed:inFolder:referencedFrom:checkBuiltIn:

- (id)displayNameForFile:(NSString*)file andFolder:(NSString*)folder; // -> -cxx_displayNameForFile:andFolder:

- (NSArray*)filesInFolder:(NSString*)folder; // -> -cxx_filesInFolder:

@end

#endif // OOFILESCANNERVERIFIERSTAGE_FOUNDATIONBRIDGE_H
