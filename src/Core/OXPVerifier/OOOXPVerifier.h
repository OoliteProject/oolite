/*

OOOXPVerifier.h

Oolite expansion pack verification manager.

NOTE: the overall design is discussed in OXP verifier design.txt.


Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef OO_OXP_VERIFIER_ENABLED
	#ifdef NDEBUG
		#define OO_OXP_VERIFIER_ENABLED 0
	#else
		#define OO_OXP_VERIFIER_ENABLED 1
	#endif
#endif

#if OO_OXP_VERIFIER_ENABLED

#import "OOCocoa.h"

@class OOOXPVerifierStage;


@interface OOOXPVerifier: NSObject
{
	NSDictionary				*_verifierPList;
	
	NSString					*_basePath;
	NSString					*_displayName;
	
	NSMutableDictionary			*_stagesByName;
	NSMutableSet				*_waitingStages;
	
	BOOL						_openForRegistration;
}

/*	Look for command-line arguments requesting OXP verification. If any are
	found, run the verification and return YES. Otherwise, return NO.
	
	At the moment, only one OXP may be verified per run; additional requests
	are ignored.
*/
+ (BOOL)runVerificationIfRequested;


/*	Stage registration. Currently, stages are registered by OOOXPVerifier
	itself. Stages may also register other stages - substages, as it were -
	in their -initWithVerifier: methods, or when -dependencies or
	-dependents are called. Registration at later points is not permitted.
*/
- (void)registerStage:(OOOXPVerifierStage *)stage;


//	All other methods are for use by verifier stages.
- (NSString *)oxpPath;
- (NSString *)oxpDisplayName;

- (id)stageWithName:(NSString *)name;

// Read from verifyOXP.plist
- (id)configurationValueForKey:(NSString *)key;
- (NSArray *)configurationArrayForKey:(NSString *)key;
- (NSDictionary *)configurationDictionaryForKey:(NSString *)key;
- (NSString *)configurationStringForKey:(NSString *)key;
- (NSSet *)configurationSetForKey:(NSString *)key;

@end

#endif
