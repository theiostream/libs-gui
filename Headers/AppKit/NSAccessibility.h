#import <AppKit/NSAccessibilityConstants.h>

APPKIT_EXTERN void NSAccessibilityPostNotification(id element, NSString *notification);
APPKIT_EXTERN void NSAccessibilityPostNotificationWithUserInfo(id element, NSString *notification, NSDictionary *userInfo);

APPKIT_EXTERN  id NSAccessibilityUnignoredAncestor(id element);
APPKIT_EXTERN  id NSAccessibilityUnignoredDescendant(id element);
APPKIT_EXTERN NSArray *NSAccessibilityUnignoredChildren(NSArray *originalChildren);
APPKIT_EXTERN NSArray *NSAccessibilityUnignoredChildrenForOnlyChild(id originalChild);

APPKIT_EXTERN NSString *  NSAccessibilityRoleDescription(NSString *role, NSString *  subrole);
APPKIT_EXTERN NSString *  NSAccessibilityRoleDescriptionForUIElement(id element);
APPKIT_EXTERN NSString *  NSAccessibilityActionDescription(NSString *action);
