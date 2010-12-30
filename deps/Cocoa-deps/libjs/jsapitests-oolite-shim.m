#import <Foundation/Foundation.h>


void OOLogWithPrefix(NSString *messageClass, const char *function, const char *file, unsigned long line, NSString *prefix, NSString *format, ...)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	
	printf("%s\n", [message UTF8String]);
	
	[message release];
	[pool drain];
}


NSString *OOLogAbbreviatedFileName(const char *inName)
{
	return @"";
}
