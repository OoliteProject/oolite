/*

OOLogOutputHandler.m
By Jens Ayton


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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


#define OOLOG_POISON_NSLOG 0

#import "OOLogOutputHandler.h"
#import "OOLogging.h"
#import <CoreFoundation/CoreFoundation.h>
#import "OOAsyncQueue.h"
#import <stdlib.h>
#import <stdio.h>
#import <sys/sysctl.h>
#import <mach/machine.h>
#import "NSThreadOOExtensions.h"

#undef NSLog		// We need to be able to call the real NSLog.


// Define CPU_TYPE_STRING for log preamble. Must be a C string literal.
#if defined (__ppc__)
		#define CPU_TYPE_STRING_BASE "PPC-32"
#elif defined (__ppc64__)
		#define CPU_TYPE_STRING_BASE "PPC-64"
#elif defined (__i386__)
		#define CPU_TYPE_STRING_BASE "x86-32"
#elif defined (__x86_64__)
		#define CPU_TYPE_STRING_BASE "x86-64"
#else
		#define CPU_TYPE_STRING_BASE "Unknown architecture!"
#endif

#ifdef OO_DEBUG
	#define CPU_TYPE_STRING CPU_TYPE_STRING_BASE " debug"
#elif !defined (NDEBUG)
	#define CPU_TYPE_STRING CPU_TYPE_STRING_BASE " test release"
#else
	#define CPU_TYPE_STRING CPU_TYPE_STRING_BASE
#endif


typedef void (*LogCStringFunctionProc)(const char *string, unsigned length, BOOL withSyslogBanner);
typedef LogCStringFunctionProc (*LogCStringFunctionGetterProc)(void);
typedef void (*LogCStringFunctionSetterProc)(LogCStringFunctionProc);

static LogCStringFunctionGetterProc _NSLogCStringFunction = NULL;
static LogCStringFunctionSetterProc _NSSetLogCStringFunction = NULL;

static void LoadLogCStringFunctions(void);

static void OONSLogCStringFunction(const char *string, unsigned length, BOOL withSyslogBanner);

static BOOL DirectoryExistCreatingIfNecessary(NSString *path);
static NSString *GetLogBasePath(void);
static NSString *GetAppName(void);


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

- (void)changeFile;

// Internal
- (BOOL)startLogging;
- (void)loggerThread;

@end


static BOOL						sInited = NO;
static BOOL						sWriteToStderr = YES;
static OOAsyncLogger			*sLogger = nil;
static LogCStringFunctionProc	sDefaultLogCStringFunction = NULL;
static NSString					*sLogFileName = @"Latest.log";


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
		sWriteToStderr = YES;
		sInited = NO;
		
		[sLogger endLogging];
		[sLogger release];
		sLogger = nil;
		
		if (sDefaultLogCStringFunction != NULL && _NSSetLogCStringFunction != NULL)
		{
			_NSSetLogCStringFunction(sDefaultLogCStringFunction);
			sDefaultLogCStringFunction = NULL;
		}
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


NSString *OOLogHandlerGetLogPath(void)
{
	return [GetLogBasePath() stringByAppendingPathComponent:sLogFileName];	
}


void OOLogOutputHandlerChangeLogFile(NSString *newLogName)
{
	if (![sLogFileName isEqual:newLogName])
	{
		sLogFileName = [newLogName copy];
		[sLogger changeFile];
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
	NSString			*logPath = nil;
	NSString			*oldPath = nil;
	NSFileManager		*fmgr = nil;
	
	// We'll need these for a couple of things.
	fmgr = [NSFileManager defaultManager];
	
	logPath = OOLogHandlerGetLogPath();
	// If there is an existing file, move it to Previous.log.
	if ([fmgr fileExistsAtPath:logPath])
	{
		oldPath = [GetLogBasePath() stringByAppendingPathComponent:@"Previous.log"];
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
	
	if (OK)  OK = [self startLogging];
	
	if (!OK)
	{
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


- (BOOL)startLogging
{
	BOOL				OK = YES;
	NSString			*logPath = nil;
	NSFileManager		*fmgr = nil;
	
	// We'll need these for a couple of things.
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
		[threadStateMonitor ooSetName:@"OOLogOutputHandler thread state monitor"];
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
		logPath = OOLogHandlerGetLogPath();
		OK = (logPath != nil);
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
	
	return OK;
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


- (void)changeFile
{
	[self endLogging];
	if (![self startLogging])  sWriteToStderr = YES;
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
	[NSThread ooSetCurrentThreadName:@"OOLogOutputHandler logging thread"];
	
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
	CFBundleRef						foundationBundle = NULL;
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


static BOOL DirectoryExistCreatingIfNecessary(NSString *path)
{
	BOOL				exists, directory;
	NSFileManager		*fmgr =  [NSFileManager defaultManager];
	
	exists = [fmgr fileExistsAtPath:path isDirectory:&directory];
	
	if (exists && !directory)
	{
		NSLog(@"Log setup: expected %@ to be a folder, but it is a file.", path);
		return NO;
	}
	if (!exists)
	{
		if (![fmgr createDirectoryAtPath:path attributes:nil])
		{
			NSLog(@"Log setup: could not create folder %@.", path);
			return NO;
		}
	}
	
	return YES;
}


static NSString *GetLogBasePath(void)
{
	static NSString		*basePath = nil;
	
	if (basePath == nil)
	{
		// ~/Library
		basePath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
		
		// ~/Library/Logs
		basePath = [basePath stringByAppendingPathComponent:@"Logs"];
		if (!DirectoryExistCreatingIfNecessary(basePath))  return nil;
		
		// ~/Library/Logs/Oolite
		basePath = [basePath stringByAppendingPathComponent:GetAppName()];
		if (!DirectoryExistCreatingIfNecessary(basePath))  return nil;
		
		[basePath retain];
	}
	
	return basePath;
}


static NSString *GetAppName(void)
{
	static NSString		*appName = nil;
	NSBundle			*bundle = nil;
	
	if (appName == nil)
	{
		bundle = [NSBundle mainBundle];
		appName = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
		if (appName == nil)  appName = [bundle bundleIdentifier];
		if (appName == nil)  appName = @"<unknown application>";
		[appName retain];
	}
	
	return appName;
}
