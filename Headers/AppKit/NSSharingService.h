#ifndef __GNUstep_NSSharingService
#define __GNUstep_NSSharingService

#import <AppKit/AppKitDefines.h>
#import <AppKit/NSPasteboard.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>

@class NSString, NSImage, NSView, NSError, NSWindow;

APPKIT_EXTERN NSString * const NSSharingServiceNamePostOnFacebook ;
APPKIT_EXTERN NSString * const NSSharingServiceNamePostOnTwitter ;
APPKIT_EXTERN NSString * const NSSharingServiceNamePostOnSinaWeibo ;
APPKIT_EXTERN NSString * const NSSharingServiceNamePostOnTencentWeibo ;
APPKIT_EXTERN NSString * const NSSharingServiceNamePostOnLinkedIn ;
APPKIT_EXTERN NSString * const NSSharingServiceNameComposeEmail ;
APPKIT_EXTERN NSString * const NSSharingServiceNameComposeMessage ;
APPKIT_EXTERN NSString * const NSSharingServiceNameSendViaAirDrop ;
APPKIT_EXTERN NSString * const NSSharingServiceNameAddToSafariReadingList ;
APPKIT_EXTERN NSString * const NSSharingServiceNameAddToIPhoto ;
APPKIT_EXTERN NSString * const NSSharingServiceNameAddToAperture ;
APPKIT_EXTERN NSString * const NSSharingServiceNameUseAsTwitterProfileImage ;
APPKIT_EXTERN NSString * const NSSharingServiceNameUseAsFacebookProfileImage ;
APPKIT_EXTERN NSString * const NSSharingServiceNameUseAsLinkedInProfileImage ;
APPKIT_EXTERN NSString * const NSSharingServiceNameUseAsDesktopPicture ;
APPKIT_EXTERN NSString * const NSSharingServiceNamePostImageOnFlickr ;
APPKIT_EXTERN NSString * const NSSharingServiceNamePostVideoOnVimeo ;
APPKIT_EXTERN NSString * const NSSharingServiceNamePostVideoOnYouku ;
APPKIT_EXTERN NSString * const NSSharingServiceNamePostVideoOnTudou ;

@protocol NSSharingServiceDelegate;

@interface NSSharingService : NSObject
@property (assign) id <NSSharingServiceDelegate> delegate;
@property (readonly, copy) NSString *title;
@property (readonly, strong) NSImage *image;
@property (readonly, strong) NSImage *alternateImage;

@property (copy) NSString *menuItemTitle ;
@property (copy) NSArray<NSString *> *recipients ;
@property (copy) NSString *subject ;

@property (readonly, copy) NSString *messageBody ;
@property (readonly, copy) NSURL *permanentLink ;
@property (readonly, copy) NSString *accountName ;
@property (readonly, copy) NSArray<NSURL *> *attachmentFileURLs ;

+ (NSArray<NSSharingService *> *)sharingServicesForItems:(NSArray *)items;
+ ( NSSharingService *)sharingServiceNamed:(NSString *)serviceName;
- (instancetype)initWithTitle:(NSString *)title image:(NSImage *)image alternateImage:( NSImage *)alternateImage handler:(void (^)(void))block;
- (instancetype)init;
- (BOOL)canPerformWithItems:( NSArray *)items;
- (void)performWithItems:(NSArray *)items;
@end

typedef NSInteger NSSharingContentScope;
enum {
    NSSharingContentScopeItem,
    NSSharingContentScopePartial,
    NSSharingContentScopeFull
};

@protocol NSSharingServiceDelegate <NSObject>
@optional
- (void)sharingService:(NSSharingService *)sharingService willShareItems:(NSArray *)items;
- (void)sharingService:(NSSharingService *)sharingService didFailToShareItems:(NSArray *)items error:(NSError *)error;
- (void)sharingService:(NSSharingService *)sharingService didShareItems:(NSArray *)items;

- (NSRect)sharingService:(NSSharingService *)sharingService sourceFrameOnScreenForShareItem:(id)item;
- (NSImage *)sharingService:(NSSharingService *)sharingService transitionImageForShareItem:(id)item contentRect:(NSRect *)contentRect;
- ( NSWindow *)sharingService:(NSSharingService *)sharingService sourceWindowForShareItems:(NSArray *)items sharingContentScope:(NSSharingContentScope *)sharingContentScope;
@end

@protocol NSSharingServicePickerDelegate;

@interface NSSharingServicePicker : NSObject 
@property (assign) id <NSSharingServicePickerDelegate> delegate;

- (instancetype)initWithItems:(NSArray *)items;
- (instancetype)init;
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)preferredEdge;
@end

@protocol NSSharingServicePickerDelegate <NSObject>
@optional
- (NSArray<NSSharingService *> *)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker sharingServicesForItems:(NSArray *)items proposedSharingServices:(NSArray<NSSharingService *> *)proposedServices;
- (id <NSSharingServiceDelegate>)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker delegateForSharingService:(NSSharingService *)sharingService;
- (void)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker didChooseSharingService:(NSSharingService *)service;

@end

#endif
