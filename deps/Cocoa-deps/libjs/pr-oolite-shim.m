#import "prlog.h"
#import "primpl.h"
#import <Foundation/Foundation.h>


void OOLogWithPrefix(NSString *messageClass, const char *function, const char *file, unsigned long line, NSString *prefix, NSString *format, ...);

PRBool nspr_use_zone_allocator __attribute__((used)) = NO;


#pragma mark prinit.c

PRBool _pr_initialized = PR_FALSE;
PRLogModuleInfo *_pr_thread_lm;
extern PRLock *_pr_sleeplock;
PRLock *_pr_sleeplock;  /* used in PR_Sleep(), classic and pthreads */


void _PR_ImplicitInitialization(void)
{
	if (_pr_initialized) return;
	_pr_initialized = PR_TRUE;
	
#ifdef _PR_ZONE_ALLOCATOR
	_PR_InitZones();
#endif
	
	
//	(void) PR_GetPageSize();
	
//	_pr_clock_lm = PR_NewLogModule("clock");
//	_pr_cmon_lm = PR_NewLogModule("cmon");
//	_pr_io_lm = PR_NewLogModule("io");
//	_pr_mon_lm = PR_NewLogModule("mon");
//	_pr_linker_lm = PR_NewLogModule("linker");
//	_pr_cvar_lm = PR_NewLogModule("cvar");
//	_pr_sched_lm = PR_NewLogModule("sched");
	_pr_thread_lm = PR_NewLogModule("thread");
//	_pr_gc_lm = PR_NewLogModule("gc");
//	_pr_shm_lm = PR_NewLogModule("shm");
//	_pr_shma_lm = PR_NewLogModule("shma");
	  
	/* NOTE: These init's cannot depend on _PR_MD_CURRENT_THREAD() */ 
//	_PR_MD_EARLY_INIT();

	_PR_InitLocks();
	_PR_InitAtomic();
//	_PR_InitSegs();
//	_PR_InitStacks();
	_PR_InitTPD();
//	_PR_InitEnv();
//	_PR_InitLayerCache();
	_PR_InitClock();

	_pr_sleeplock = PR_NewLock();
	PR_ASSERT(NULL != _pr_sleeplock);

	_PR_InitThreads(PR_USER_THREAD, PR_PRIORITY_NORMAL, 0);

#ifndef _PR_GLOBAL_THREADS_ONLY
	_PR_InitCPUs();
#endif
	
//	_PR_InitCMon();
	_PR_InitIO();
//	_PR_InitNet();
//	_PR_InitTime();
//	_PR_InitLog();
//	_PR_InitLinker();
//	_PR_InitCallOnce();
//	_PR_InitDtoa();
//	_PR_InitMW();
//	_PR_InitRWLocks();

//	nspr_InitializePRErrorTable();

	_PR_MD_FINAL_INIT();
}


#pragma mark ptio.c

#ifdef DEBUG
PTDebug pt_debug;
#endif

void _PR_InitIO(void)
{
#ifdef DEBUG
	memset(&pt_debug, 0, sizeof(PTDebug));
	pt_debug.timeStarted = PR_Now();
#endif
}


#pragma mark prlog.c

void PR_LogPrint(const char *fmt, ...)
{
	// PR_snprintf() is a subset of NSString formatting capabilities, so this is OK.
	va_list args;
	va_start(args, fmt);
	NSString *message = [[NSString alloc] initWithFormat:fmt arguments:args];
	va_end(args);
	
	OOLogWithPrefix(@"nspr", NULL, NULL, 0, @"", @"%@", message);
	
	[message release];
}


#ifdef DEBUG
void PR_Assert(const char *s, const char *file, PRIntn ln)
{
	OOLogWithPrefix(@"nspr.assertion", NULL, file, ln, @"", @"ASSERTION FAILURE at %s:%lu: %s", file, (long)ln, s);
	__builtin_trap();
	abort();
}
#endif


PRLogModuleInfo *PR_NewLogModule(const char *name)
{
	PRLogModuleInfo *result = calloc(1, sizeof(PRLogModuleInfo));
	result->name = strdup(name);
	result->level = PR_LOG_ALWAYS;
	return result;
}
