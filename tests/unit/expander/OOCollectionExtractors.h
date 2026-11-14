// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#import "OOFoundation.h"
@interface NSArray (OOHarnessExtractors)
- (id) oo_objectAtIndex:(NSUInteger)i;
- (NSArray *) oo_arrayAtIndex:(NSUInteger)i;
- (NSString *) oo_stringAtIndex:(NSUInteger)i;
@end
@interface NSDictionary (OOHarnessExtractors)
- (NSArray *) oo_arrayForKey:(id)key;
- (NSDictionary *) oo_dictionaryForKey:(id)key;
- (NSString *) oo_stringForKey:(id)key;
@end
