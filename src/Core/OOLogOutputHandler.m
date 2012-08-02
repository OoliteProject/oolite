/*

OOLogOutputHandler.m
By Jens Ayton


Copyright (C) 2007-2012 Jens Ayton and contributors

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


#define OOLOG_POISON_NSLOG 0
#define DLOPEN_NO_WARN

#import "OOLogOutputHandler.h"
#import "OOLogging.h"
#import "OOAsyncQueue.h"
#include <stdlib.h>
#include <stdio.h>
#import "NSThreadOOExtensions.h"
#import "NSFileManagerOOExtensions.h"


#undef NSLog		// We need to be able to call the real NSLog.


#if OOLITE_MAC_OS_X

#include <dlfcn.h>

#ifndef NDEBUG

#define SET_CRASH_REPORTER_INFO 1

// Function to set "Application Specific Information" field in crash reporter log in Leopard.
// Extremely unsupported, so not used in release builds.
static void InitCrashReporterInfo(void);
static void SetCrashReporterInfo(const char *info);
static BOOL sCrashReporterInfoAvailable = NO;

#endif


typedef void (*LogCStringFunctionProc)(const char *string, unsigned length, BOOL withSyslogBanner);
typedef LogCStringFunctionProc (*LogCStringFunctionGetterProc)(void);
typedef void (*LogCStringFunctionSetterProc)(LogCStringFunctionProc);

static LogCStringFunctionGetterProc _NSLogCStringFunction = NULL;
static LogCStringFunctionSetterProc _NSSetLogCStringFunction = NULL;

static void LoadLogCStringFunctions(void);
static void OONSLogCStringFunction(const char *string, unsigned length, BOOL withSyslogBanner);

static NSString *GetAppName(void);

static LogCStringFunctionProc	sDefaultLogCStringFunction = NULL;

#elif OOLITE_GNUSTEP

static void OONSLogPrintfHandler(NSString *message);

#else
#error Unknown platform!
#endif

static BOOL DirectoryExistCreatingIfNecessary(NSString *path);


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
- (void)flushLog;

@end


static BOOL						sInited = NO;
static BOOL						sWriteToStderr = YES;
static BOOL						sWriteToStdout = NO;
static BOOL						sSaturated = NO;
static OOAsyncLogger			*sLogger = nil;
static NSString					*sLogFileName = @"Latest.log";


void OOLogOutputHandlerInit(void)
{
	if (sInited)  return;
	
#if SET_CRASH_REPORTER_INFO
	InitCrashReporterInfo();
#endif
	
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
	
#if OOLITE_MAC_OS_X
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
#elif GNUSTEP
	NSRecursiveLock *lock = GSLogLock();
	[lock lock];
	_NSLog_printf_handler = OONSLogPrintfHandler;
	[lock unlock];
#endif
	
	atexit(OOLogOutputHandlerClose);
}


void OOLogOutputHandlerClose(void)
{
	if (sInited)
	{
		sWriteToStderr = YES;
		sInited = NO;
		
		[sLogger endLogging];
		DESTROY(sLogger);
		
#if OOLITE_MAC_OS_X
		if (sDefaultLogCStringFunction != NULL && _NSSetLogCStringFunction != NULL)
		{
			_NSSetLogCStringFunction(sDefaultLogCStringFunction);
			sDefaultLogCStringFunction = NULL;
		}
#elif GNUSTEP
		NSRecursiveLock *lock = GSLogLock();
		[lock lock];
		_NSLog_printf_handler = NULL;
		[lock unlock];
#endif
	}
}

void OOLogOutputHandlerStartLoggingToStdout()
{
	sWriteToStdout = true;
}
void OOLogOutputHandlerStopLoggingToStdout()
{
	sWriteToStdout = false;
}

void OOLogOutputHandlerPrint(NSString *string)
{
	if (sInited && sLogger != nil && !sWriteToStdout)  [sLogger asyncLogMessage:string];
	
	BOOL doCStringStuff = sWriteToStderr || sWriteToStdout;
#if SET_CRASH_REPORTER_INFO
	doCStringStuff = doCStringStuff || sCrashReporterInfoAvailable;
#endif
	
	if (doCStringStuff)
	{
		const char *cStr = [[string stringByAppendingString:@"\n"] UTF8String];
		if (sWriteToStdout)
			fputs(cStr, stdout);
		else if (sWriteToStderr)
			fputs(cStr, stderr);
		
#if SET_CRASH_REPORTER_INFO
		if (sCrashReporterInfoAvailable)  SetCrashReporterInfo(cStr);
#endif
	}
	
}


NSString *OOLogHandlerGetLogPath(void)
{
	return [OOLogHandlerGetLogBasePath() stringByAppendingPathComponent:sLogFileName];	
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
	
	self = [super init];
	if (self == nil)  OK = NO;
	
	if (OK)
	{
		fmgr = [NSFileManager defaultManager];
		logPath = OOLogHandlerGetLogPath();
		
		// If there is an existing file, move it to Previous.log.
		if ([fmgr fileExistsAtPath:logPath])
		{
			oldPath = [OOLogHandlerGetLogBasePath() stringByAppendingPathComponent:@"Previous.log"];
			[fmgr oo_removeItemAtPath:oldPath];
			if (![fmgr oo_moveItemAtPath:logPath toPath:oldPath])
			{
				if (![fmgr oo_removeItemAtPath:logPath])
				{
					NSLog(@"Log setup: could not move or delete existing log at %@, will log to stdout instead.", logPath);
					OK = NO;
				}
			}
		}
	}
	
	if (OK)  OK = [self startLogging];
	
	if (!OK)  DESTROY(self);
	
	return self;
}


- (void)dealloc
{
	DESTROY(messageQueue);
	DESTROY(threadStateMonitor);
	DESTROY(logFile);
	// We don't own a reference to flushTimer.
	
	[super dealloc];
}


- (BOOL)startLogging
{
	BOOL				OK = YES;
	NSString			*logPath = nil;
	NSFileManager		*fmgr = nil;
	
	fmgr = [NSFileManager defaultManager];
	
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
		[threadStateMonitor setName:@"OOLogOutputHandler thread state monitor"];
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
	// Don't log of saturated flag is set.
	if (sSaturated)  return;
	
	if (message != nil)
	{
		message = [message stringByAppendingString:@"\n"];
		
#if OOLITE_WINDOWS
		// Convert Unix line endings to Windows ones.
		NSArray *messageComponents = [message componentsSeparatedByString:@"\n"];
		message = [messageComponents componentsJoinedByString:@"\r\n"];
#endif
		
		[messageQueue enqueue:[message dataUsingEncoding:NSUTF8StringEncoding]];
		
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
	OOUInteger			size = 0;
	
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
			
			if (!sSaturated && [message isKindOfClass:[NSData class]])
			{
				size += [message length];
				if (size > 1 << 30)	// 1 GiB
				{
					sSaturated = YES;
#if OOLITE_WINDOWS
					message = @"\r\n\r\n\r\n***** LOG TRUNCATED DUE TO EXCESSIVE LENGTH *****\r\n";
#else
					message = @"\n\n\n***** LOG TRUNCATED DUE TO EXCESSIVE LENGTH *****\n";
#endif
					message = [message dataUsingEncoding:NSUTF8StringEncoding];
				}
				
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


#if OOLITE_MAC_OS_X

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
	
	The approach taken here is to load the functions dynamically. This makes
	us safe in the case of Apple removing the functions. In the unlikely event
	that they change the functions' paramters without renaming them, we would
	have a problem.
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

#elif OOLITE_GNUSTEP

static void OONSLogPrintfHandler(NSString *message)
{
	if (OOLogWillDisplayMessagesInClass(@"gnustep"))
	{
		OOLogWithFunctionFileAndLine(@"gnustep", NULL, NULL, 0, @"%@", message);
	}
}

#endif


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
		if (![fmgr oo_createDirectoryAtPath:path attributes:nil])
		{
			NSLog(@"Log setup: could not create folder %@.", path);
			return NO;
		}
	}
	
	return YES;
}


#if OOLITE_MAC_OS_X

static void ExcludeFromTimeMachine(NSString *path);


NSString *OOLogHandlerGetLogBasePath(void)
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
		ExcludeFromTimeMachine(basePath);
		
		[basePath retain];
	}
	
	return basePath;
}


static void ExcludeFromTimeMachine(NSString *path)
{
	OSStatus (*CSBackupSetItemExcluded)(NSURL *item, Boolean exclude, Boolean excludeByPath) = NULL;
	CFBundleRef carbonCoreBundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.CoreServices.CarbonCore"));
	if (carbonCoreBundle)
	{
		CSBackupSetItemExcluded = CFBundleGetFunctionPointerForName(carbonCoreBundle, CFSTR("CSBackupSetItemExcluded"));
		if (CSBackupSetItemExcluded != NULL)
		{
			(void)CSBackupSetItemExcluded([NSURL fileURLWithPath:path], YES, NO);
		}
	}
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

#elif OOLITE_LINUX

NSString *OOLogHandlerGetLogBasePath(void)
{
	static NSString		*basePath = nil;
	
	if (basePath == nil)
	{
		// ~
		basePath = NSHomeDirectory();
		
		// ~/.Oolite
		basePath = [basePath stringByAppendingPathComponent:@".Oolite"];
		if (!DirectoryExistCreatingIfNecessary(basePath))  return nil;
		
		// ~/.Oolite/Logs
		basePath = [basePath stringByAppendingPathComponent:@"Logs"];
		if (!DirectoryExistCreatingIfNecessary(basePath))  return nil;
		
		[basePath retain];
	}
	
	return basePath;
}

#elif OOLITE_WINDOWS

NSString *OOLogHandlerGetLogBasePath(void)
{
	static NSString		*basePath = nil;
	
	if (basePath == nil)
	{
		// <Install path>\Oolite
		basePath = NSHomeDirectory();
		
		// <Install path>\Oolite\Logs
		basePath = [basePath stringByAppendingPathComponent:@"Logs"];
		if (!DirectoryExistCreatingIfNecessary(basePath))  return nil;
		
		[basePath retain];
	}
	
	return basePath;
}

#endif


#if SET_CRASH_REPORTER_INFO

static char **sCrashReporterInfo = NULL;
static char *sOldCrashReporterInfo = NULL;
static NSLock *sCrashReporterInfoLock = nil;

// Evil hackery based on http://www.allocinit.net/blog/2008/01/04/application-specific-information-in-leopard-crash-reports/
static void InitCrashReporterInfo(void)
{
	sCrashReporterInfo = dlsym(RTLD_DEFAULT, "__crashreporter_info__");
	if (sCrashReporterInfo != NULL)
	{
		sCrashReporterInfoLock = [[NSLock alloc] init];
		if (sCrashReporterInfoLock != nil)
		{
			sCrashReporterInfoAvailable = YES;
		}
		else
		{
			sCrashReporterInfo = NULL;
		}
	}
}

static void SetCrashReporterInfo(const char *info)
{
	char					*copy = NULL, *old = NULL;
	
	/*	Don't do anything if setup failed or the string is NULL or empty.
		(The NULL and empty checks may not be desirable in other uses.)
	*/
	if (!sCrashReporterInfoAvailable || info == NULL || *info == '\0')  return;
	
	// Copy the string, which we assume to be dynamic...
	copy = strdup(info);
	if (copy == NULL)  return;
	
	/*	...and swap it in.
		Note that we keep a separate pointer to the old value, in case
		something else overwrites __crashreporter_info__.
	*/
	[sCrashReporterInfoLock lock];
	*sCrashReporterInfo = copy;
	old = sOldCrashReporterInfo;
	sOldCrashReporterInfo = copy;
	[sCrashReporterInfoLock unlock];
	
	// Delete our old string.
	if (old != NULL)  free(old);
}

#endif
