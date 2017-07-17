#import <AppKit/NSView.h>

typedef NSInteger NSVisualEffectMaterial;
enum {
    NSVisualEffectMaterialAppearanceBased = 0,
    NSVisualEffectMaterialTitlebar = 3,
    NSVisualEffectMaterialMenu = 5,
    NSVisualEffectMaterialPopover = 6,
    NSVisualEffectMaterialSidebar = 7,
    
    NSVisualEffectMaterialLight = 1,
    NSVisualEffectMaterialDark = 2,
    NSVisualEffectMaterialMediumLight = 8,
    NSVisualEffectMaterialUltraDark = 9,
};
                
typedef NSInteger NSVisualEffectBlendingMode;
enum {
    NSVisualEffectBlendingModeBehindWindow,
    NSVisualEffectBlendingModeWithinWindow,
};

typedef NSInteger NSVisualEffectState;
enum {
    NSVisualEffectStateFollowsWindowActiveState,
    NSVisualEffectStateActive,
    NSVisualEffectStateInactive,
};

@interface NSVisualEffectView : NSView {
}

@property NSVisualEffectMaterial material;

@property(readonly) NSBackgroundStyle interiorBackgroundStyle;
@property NSVisualEffectBlendingMode blendingMode;

@property NSVisualEffectState state;
@property(nullable, retain) NSImage *maskImage;

- (void)viewDidMoveToWindow;
- (void)viewWillMoveToWindow:(NSWindow *)newWindow;
@end
