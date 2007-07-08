/*

OOLogOutputHandler.m
By Jens Ayton


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


#import "OOLogOutputHandler.h"
#import "OOLogging.h"
#import <CoreFoundation/CoreFoundation.h>
#import "OOAsyncQueue.h"
#import <stdlib.h>
#import <stdio.h>


#undef NSLog		// We need to be able to call the real NSLog.


typedef void (*LogCStringFunctionProc)(const char *string, unsigned length, BOOL withSyslogBanner);
typedef LogCStringFunctionProc (*LogCStringFunctionGetterProc)(void);
typedef void (*LogCStringFunctionSetterProc)(LogCStringFunctionProc);

static LogCStringFunctionGetterProc _NSLogCStringFunction = NULL;
static LogCStringFunctionSetterProc _NSSetLogCStringFunction = NULL;

static void LoadLogCStringFunctions(void);

static void OONSLogCStringFunction(const char *string, unsigned length, BOOL withSyslogBanner);


#define kFlushInterval	2.0		// Lower bound on interval between explicit log file flushes.


@interface OOAsyncLogger: NSObject
{
	OOAsyncQueue		*messageQueue;
	NSConditionLock		*threadStateMonitor;
	NSFileHandle		*logFile;
	NSTimer				*flushTimer;
}

- (void)asyncLogMessage:(NSString *)message;
- (void)endLogging;

// Internal
- (void)loggerThread;
- (BOOL)directoryExists:(NSString *)inPath create:(BOOL)inCreate;

@end


static BOOL						sInited = NO;
static BOOL						sWriteToStderr = YES;
static OOAsyncLogger			*sLogger = nil;
static LogCStringFunctionProc	sDefaultLogCStringFunction = nil;


void OOLogOutputHandlerInit(void)
{
	if (sInited)  return;
	
	sLogger = [[OOAsyncLogger alloc] init];
	sInited = YES;
	
	if (sLogger != nil)
	{
		sWriteToStderr = [[NSUserDefaults standardUserDefaults] boolForKey:@"logging-echo-to-stderr"];
	}
	else
	{
		sWriteToStderr = YES;
	}
	
	LoadLogCStringFunctions();
	if (_NSSetLogCStringFunction != NULL)
	{
		sDefaultLogCStringFunction = _NSLogCStringFunction();
		_NSSetLogCStringFunction(OONSLogCStringFunction);
	}
	else
	{
		OOLog(@"logging.nsLogFilter.install.failed", @"Failed to install NSLog() filter; system messages will not be logged in log file.");
	}
	
	atexit(OOLogOutputHandlerClose);
}


void OOLogOutputHandlerClose(void)
{
	if (sInited)
	{
		[sLogger endLogging];
		[sLogger release];
		sLogger = nil;
		
		if (sDefaultLogCStringFunction != NULL && _NSSetLogCStringFunction != NULL)
		{
			_NSSetLogCStringFunction(sDefaultLogCStringFunction);
			sDefaultLogCStringFunction = NULL;
		}
		
		sInited = NO;
		sWriteToStderr = YES;
	}
}


void OOLogOutputHandlerPrint(NSString *string)
{
	if (sInited && sLogger != nil)  [sLogger asyncLogMessage:string];
	
	if (sWriteToStderr)
	{
		fputs([[string stringByAppendingString:@"\n"] UTF8String], stderr);
	}
}


enum
{
	kConditionReadyToDealloc = 1,
	kConditionWorking
};


@implementation OOAsyncLogger

- (id)init
{
	BOOL				OK = YES;
	NSString			*basePath = nil;
	NSString			*logPath = nil;
	NSString			*oldPath = nil;
	NSBundle			*bundle = nil;
	NSString			*appName = nil;
	NSFileManager		*fmgr = nil;
	NSString			*preamble = nil;
	NSString			*versionString = nil;
	
	// We'll need these for a couple of things.
	bundle = [NSBundle mainBundle];
	appName = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
	if (appName == nil)  appName = [bundle bundleIdentifier];
	if (appName == nil)  appName = @"<unknown application>";
	fmgr = [NSFileManager defaultManager];
	
	self = [super init];
	if (self == nil)  OK = NO;
	
	if (OK)
	{
		messageQueue = [[OOAsyncQueue alloc] init];
		if (messageQueue == nil)  OK = NO;
	}
	
	if (OK)
	{
		// set up threadStateMonitor -- used as a binary semaphore of sorts to check when the worker thread starts and stops.
		threadStateMonitor = [[NSConditionLock alloc] initWithCondition:kConditionReadyToDealloc];
		if (threadStateMonitor == nil)  OK = NO;
	}
	
	if (OK)
	{
		// Create work thread to actually handle messages.
		// This needs to be done early to avoid messy state if something goes wrong.
		[NSThread detachNewThreadSelector:@selector(loggerThread) toTarget:self withObject:nil];
		// Wait for it to start.
		if (![threadStateMonitor lockWhenCondition:kConditionWorking beforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]])
		{
			// If it doesn't signal a start within five seconds, assume something's wrong.
			// Send kill signal, just in case it comes to life...
			[messageQueue enqueue:@"die"];
			// ...and stop -dealloc from waiting for thread death
			[threadStateMonitor release];
			threadStateMonitor = nil;
			OK = NO;
		}
		[threadStateMonitor unlockWithCondition:kConditionWorking];
	}
	
	if (OK)
	{
		// Set up base path -- ~/Library/Logs/Oolite
		basePath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
		basePath = [basePath stringByAppendingPathComponent:@"Logs"];
		if (![self directoryExists:basePath create:YES]) OK = NO;
		else
		{
			basePath = [basePath stringByAppendingPathComponent:appName];
			if (![self directoryExists:basePath create:YES]) OK = NO;
		}
		if (OK)  logPath = [basePath stringByAppendingPathComponent:@"Latest.log"];
	}
	
	if (OK)
	{
		// If there is an existing file, move it to Previous.log.
		if ([fmgr fileExistsAtPath:logPath])
		{
			oldPath = [basePath stringByAppendingPathComponent:@"Previous.log"];
			[fmgr removeFileAtPath:oldPath handler:nil];
			if (![fmgr movePath:logPath toPath:oldPath handler:nil])
			{
				if (![fmgr removeFileAtPath:logPath handler:nil])
				{
					NSLog(@"Log setup: could not move or delete existing log at %@, will log to stdout instead.", logPath);
					OK = NO;
				}
			}
		}
	}
	
	if (OK)
	{
		// Create shiny new log file
		OK = [fmgr createFileAtPath:logPath contents:nil attributes:nil];
		if (OK)
		{
			logFile = [[NSFileHandle fileHandleForWritingAtPath:logPath] retain];
			OK = (logFile != nil);
		}
		if (!OK)
		{
			NSLog(@"Log setup: could not open log at %@, will log to stdout instead.", logPath);
			OK = NO;
		}
	}
	
	if (OK)
	{
		// Queue log preamble
		versionString = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
		if (versionString == nil)  versionString = @"<unknown version>";
		
		preamble = [NSString stringWithFormat:@"Opening log for %@ version %@ at %@.\nNote that the contents of the log file can be adjusted by editing logcontrol.plist.\n", appName, versionString, [NSDate date]];
		[self asyncLogMessage:preamble];
	}
	
	if (!OK)
	{
		// Fail to create logger; OOLogOutputHandlerPrint() will use puts() fallback.
		[self release];
		self = nil;
	}
	return self;
}


- (void)dealloc
{
	[messageQueue release];
	[threadStateMonitor release];
	[logFile release];
	[flushTimer invalidate];
	
	[super dealloc];
}


- (void)endLogging
{
	NSString				*postamble = nil;
	
	if (messageQueue != nil && threadStateMonitor != nil)
	{
		// We're fully inited; write postamble, wait for worker thread to terminate cleanly, and close file.
		postamble = [NSString stringWithFormat:@"\nClosing log at %@.", [NSDate date]];
		[self asyncLogMessage:postamble];
		[messageQueue enqueue:@"die"];	// Kill message
		[threadStateMonitor lockWhenCondition:kConditionReadyToDealloc];
		[threadStateMonitor unlock];
		
		[logFile closeFile];
	}
}


- (void)asyncLogMessage:(NSString *)message
{
	if (message != nil)
	{
		[messageQueue enqueue:[[message stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
		
		if (flushTimer == nil)
		{
			// No pending flush
			flushTimer = [NSTimer scheduledTimerWithTimeInterval:kFlushInterval target:self selector:@selector(flushLog) userInfo:nil repeats:NO];
		}
	}
}


- (void)flushLog
{
	flushTimer = nil;
	[messageQueue enqueue:@"flush"];
}


- (void)loggerThread
{
	id					message = nil;
	NSAutoreleasePool	*rootPool = nil, *pool = nil;
	
	rootPool = [[NSAutoreleasePool alloc] init];
	
	// Signal readiness
	[messageQueue retain];
	[threadStateMonitor lock];
	[threadStateMonitor unlockWithCondition:kConditionWorking];
	
	NS_DURING
		for (;;)
		{
			pool = [[NSAutoreleasePool alloc] init];
			
			message = [messageQueue dequeue];
			
			if ([message isKindOfClass:[NSData class]])
			{
				[logFile writeData:message];
			}
			else if ([message isEqual:@"flush"])
			{
				[logFile synchronizeFile];
			}
			else if ([message isEqual:@"die"])
			{
				break;
			}
			
			[pool release];
		}
	NS_HANDLER
	NS_ENDHANDLER
	[pool release];
	
	// Clean up; after this, ivars are out of bounds.
	[messageQueue release];
	[threadStateMonitor lock];
	[threadStateMonitor unlockWithCondition:kConditionReadyToDealloc];
	
	[rootPool release];
}


- (BOOL)directoryExists:(NSString *)inPath create:(BOOL)inCreate
{
	BOOL				exists, directory;
	NSFileManager		*fmgr =  [NSFileManager defaultManager];
	
	exists = [fmgr fileExistsAtPath:inPath isDirectory:&directory];
	
	if (exists && !directory)
	{
		NSLog(@"Log setup: expected %@ to be a folder, but it is a file.", inPath);
		return NO;
	}
	if (!exists)
	{
		if (!inCreate) return NO;
		if (![fmgr createDirectoryAtPath:inPath attributes:nil])
		{
			NSLog(@"Log setup: could not create folder %@.", inPath);
			return NO;
		}
	}
	
	return YES;
}

@end


/*	LoadLogCStringFunctions()
	
	We wish to make NSLogv() call our custom function OONSLogCStringFunction()
	rather than printing to stdout, by calling _NSSetLogCStringFunction().
	Additionally, in order to close the logger cleanly, we wish to be able to
	restore the standard logger, which requires us to call
	_NSLogCStringFunction(). These functions are private.
	_NSLogCStringFunction() is undocumented. _NSSetLogCStringFunction() is
	documented at http://docs.info.apple.com/article.html?artnum=70081 ,
	with the warning:
	
		Be aware that this code references private APIs; this is an
		unsupported workaround and users should use these instructions at
		their own risk. Apple will not guarantee or provide support for
		this procedure.
	
	The approach taken here is to load the function sdynamically. This makes
	us safe in the case of Apple removing the functions. In the unlikely event
	that they change the functions' paramters without renaming them, we would
	have a problem.
	
	For future reference, the GNUstep equivalent is to set
	_NSLog_printf_handler after locking GSLogLock(), as documented in GNUstep
	Foundation's NSLog.m.
*/
static void LoadLogCStringFunctions(void)
{
	CFBundleRef						foundationBundle = nil;
	LogCStringFunctionGetterProc	getter = NULL;
	LogCStringFunctionSetterProc	setter = NULL;
	
	foundationBundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.Foundation"));
	if (foundationBundle != NULL)
	{
		getter = CFBundleGetFunctionPointerForName(foundationBundle, CFSTR("_NSLogCStringFunction"));
		setter = CFBundleGetFunctionPointerForName(foundationBundle, CFSTR("_NSSetLogCStringFunction"));
		
		if (getter != NULL && setter != NULL)
		{
			_NSLogCStringFunction = getter;
			_NSSetLogCStringFunction = setter;
		}
	}
}


static void OONSLogCStringFunction(const char *string, unsigned length, BOOL withSyslogBanner)
{
	if (OOLogWillDisplayMessagesInClass(@"system"))
	{
		OOLogWithFunctionFileAndLine(@"system", NULL, NULL, 0, @"%s", string);
	}
}
