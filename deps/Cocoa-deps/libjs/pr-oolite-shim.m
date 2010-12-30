#import "prlog.h"
#import "primpl.h"
#import <Foundation/Foundation.h>


void OOLogWithPrefix(NSString *messageClass, const char *function, const char *file, unsigned long line, NSString *prefix, NSString *format, ...);

PRBool nspr_use_zone_allocator __attribute__((used)) = NO;


#pragma mark prlog.c

void _PR_InitLog(void)
{
}


void _PR_LogCleanup(void)
{
}


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
