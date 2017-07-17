#ifndef gnustep_NSPasteboardItem
#define gnustep_NSPasteboardItem

#import <Foundation/NSArray.h>
#import <AppKit/AppKitDefines.h>
#import <AppKit/NSPasteboard.h>
#import <CoreFoundation/CFBase.h>

@class NSPasteboard;
@protocol NSPasteboardItemDataProvider;

@interface NSPasteboardItem : NSObject <NSPasteboardWriting, NSPasteboardReading>
@property (readonly, copy) NSArray *types;

- ( NSString *)availableTypeFromArray:(NSArray *)types;
- (BOOL)setDataProvider:(id <NSPasteboardItemDataProvider>)dataProvider forTypes:(NSArray *)types;
- (BOOL)setData:( NSData *)data forType:(NSString *)type;
- (BOOL)setString:( NSString *)string forType:(NSString *)type;
- (BOOL)setPropertyList:( id)propertyList forType:(NSString *)type;

- ( NSData *)dataForType:(NSString *)type;
- ( NSString *)stringForType:(NSString *)type;
- ( id)propertyListForType:(NSString *)type;
@end

@protocol NSPasteboardItemDataProvider <NSObject>
@required
- (void)pasteboard:( NSPasteboard *)pasteboard item:(NSPasteboardItem *)item provideDataForType:(NSString *)type;

@optional
- (void)pasteboardFinishedWithDataProvider:(NSPasteboard *)pasteboard;
@end

#endif
