/*

OOFileScannerVerifierStage.h

OOOXPVerifierStage which keeps track of which files are used and ensures file
name capitalization is consistent. It also provides the file lookup service
for other stages.


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

#import "OOOXPVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

@interface OOFileScannerVerifierStage: OOOXPVerifierStage
{
@private
	NSString					*_basePath;
	NSMutableSet				*_usedFiles;
	NSMutableSet				*_caseWarnings;
	NSDictionary				*_directoryListings;
	NSDictionary				*_directoryCases;
	NSMutableSet				*_badPLists;
	NSSet						*_junkFileNames;
	NSSet						*_skipDirectoryNames;
}

// Returns name to be used in -dependencies by other stages; also registers stage.
+ (NSString *)nameForDependencyForVerifier:(OOOXPVerifier *)verifier;

/*	This method does the following:
		A.	Checks whether a file exists.
		B.	Checks whether case matches, and logs a warning otherwise.
		C.	Maintains list of files which are referred to.
		D.	Optionally falls back on Oolite's built-in files.
	
	For example, to test whether a texture referenced in a shipdata.plist entry
	exists, one would use:
	[fileScanner fileExists:textureName inFolder:@"Textures" referencedFrom:@"shipdata.plist" checkBuiltIn:YES];
*/
- (BOOL)fileExists:(NSString *)file
		  inFolder:(NSString *)folder
	referencedFrom:(NSString *)context
	  checkBuiltIn:(BOOL)checkBuiltIn;

//	This method performs all the checks the previous one does, but also returns a file path.
- (NSString *)pathForFile:(NSString *)file
				 inFolder:(NSString *)folder
		   referencedFrom:(NSString *)context
			 checkBuiltIn:(BOOL)checkBuiltIn;

//	Data getters based on above method.
- (NSData *)dataForFile:(NSString *)file
			   inFolder:(NSString *)folder
		 referencedFrom:(NSString *)context
		   checkBuiltIn:(BOOL)checkBuiltIn;

- (id)plistNamed:(NSString *)file	// Only uses "real" plist parser, not homebrew.
		inFolder:(NSString *)folder
  referencedFrom:(NSString *)context
	checkBuiltIn:(BOOL)checkBuiltIn;


/*	Utility to handle display names of files.
	If a file and folder are provided, returns folder/file, otherwise just file.
*/
- (id)displayNameForFile:(NSString *)file andFolder:(NSString *)folder;

/*	Get a list of files in a subfolder of the OXP. Order is undefined.
*/
- (NSArray *)filesInFolder:(NSString *)folder;

@end


@interface OOListUnusedFilesStage: OOOXPVerifierStage

// Returns name to be used in -dependents by other stages; also registers stage.
+ (NSString *)nameForReverseDependencyForVerifier:(OOOXPVerifier *)verifier;

@end


@interface OOOXPVerifier(OOFileScannerVerifierStage)

- (OOFileScannerVerifierStage *)fileScannerStage;

@end


// Convenience base class for stages that require OOFileScannerVerifierStage and OOListUnusedFilesStage.
@interface OOFileHandlingVerifierStage: OOOXPVerifierStage

@end

#endif
