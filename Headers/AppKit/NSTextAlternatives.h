#ifndef __GNUSTEP_NSTextAlternatives
#define __GNUSTEP_NSTextAlternatives

@class NSString, NSArray;

@interface NSTextAlternatives : NSObject
- (id)initWithPrimaryString:(NSString *)primaryString alternativeStrings:(NSArray *)alternativeStrings;

@property (readonly, copy) NSString *primaryString;
@property (readonly, copy) NSArray *alternativeStrings;

- (void)noteSelectedAlternativeString:(NSString *)alternativeString;
@end

APPKIT_EXTERN NSString * NSTextAlternativesSelectedAlternativeStringNotification;
#endif
