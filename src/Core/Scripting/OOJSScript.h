/*

OOJSScript.h

JavaScript support for Oolite
Copyright (C) 2007-2012 David Taylor and Jens Ayton.

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


#import "OOScript.h"
#import "OOJavaScriptEngine.h"


@interface OOJSScript: OOScript <OOWeakReferenceSupport>
{
@private
	JSObject			*_jsSelf;
	
	NSString			*name;
	NSString			*description;
	NSString			*version;
	NSString			*filePath;
	
	OOWeakReference		*weakSelf;
}

+ (id) scriptWithPath:(NSString *)path properties:(NSDictionary *)properties;

- (id) initWithPath:(NSString *)path properties:(NSDictionary *)properties;

+ (OOJSScript *) currentlyRunningScript;
+ (NSArray *) scriptStack;

/*	External manipulation of acrtive script stack. Used, for instance, by
	timers. Failing to balance these will crash!
	Passing a nil script is valid for cases where JS is used which is not
	attached to a specific script.
*/
+ (void) pushScript:(OOJSScript *)script;
+ (void) popScript:(OOJSScript *)script;

/*	Call a method.
	Requires a request on context.
	outResult may be NULL.
*/
- (BOOL) callMethod:(jsid)methodID
		  inContext:(JSContext *)context
	  withArguments:(jsval *)argv count:(intN)argc
			 result:(jsval *)outResult;

- (id) propertyWithID:(jsid)propID inContext:(JSContext *)context;
// Set a property which can be modified or deleted by the script.
- (BOOL) setProperty:(id)value withID:(jsid)propID inContext:(JSContext *)context;
// Set a special property which cannot be modified or deleted by the script.
- (BOOL) defineProperty:(id)value withID:(jsid)propID inContext:(JSContext *)context;

- (id) propertyNamed:(NSString *)name;
- (BOOL) setProperty:(id)value named:(NSString *)name;
- (BOOL) defineProperty:(id)value named:(NSString *)name;

@end


@interface OOScript (JavaScriptEvents)

// For simplicity, calling methods on non-JS scripts works but does nothing.
- (BOOL) callMethod:(jsid)methodID
		  inContext:(JSContext *)context
	  withArguments:(jsval *)argv count:(intN)argc
			 result:(jsval *)outResult;

@end


void InitOOJSScript(JSContext *context, JSObject *global);

