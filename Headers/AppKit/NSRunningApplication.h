#ifndef __GNUSTEP_NSRunningApplication
#define __GNUSTEP_NSRunningApplication

#import <AppKit/NSWorkspace.h>

typedef enum {
    NSApplicationActivateAllWindows = 1 << 0,
    NSApplicationActivateIgnoringOtherApps = 1 << 1
} NSApplicationActivationOptions;

typedef enum {
    NSApplicationActivationPolicyRegular, 
    NSApplicationActivationPolicyAccessory,
    NSApplicationActivationPolicyProhibited
} NSApplicationActivationPolicy;

@class NSLock, NSDate, NSImage, NSURL;

@interface NSRunningApplication : NSObject
@property (readonly, getter=isTerminated) BOOL terminated;
@property (readonly, getter=isFinishedLaunching) BOOL finishedLaunching;
@property (readonly, getter=isHidden) BOOL hidden;
@property (readonly, getter=isActive) BOOL active;
@property (readonly) BOOL ownsMenuBar;
@property (readonly) NSApplicationActivationPolicy activationPolicy;
@property (nullable, readonly, copy) NSString *localizedName;
@property (nullable, readonly, copy) NSString *bundleIdentifier;
@property (nullable, readonly, copy) NSURL *bundleURL;
@property (nullable, readonly, copy) NSURL *executableURL;
@property (readonly) pid_t processIdentifier;
@property (nullable, readonly, copy) NSDate *launchDate;
@property (nullable, readonly, strong) NSImage *icon;
@property (readonly) NSInteger executableArchitecture;

- (BOOL)hide;
- (BOOL)unhide;
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options;
- (BOOL)terminate;
- (BOOL)forceTerminate;
+ (NSArray<NSRunningApplication *> *)runningApplicationsWithBundleIdentifier:(NSString *)bundleIdentifier;
+ (nullable instancetype)runningApplicationWithProcessIdentifier:(pid_t)pid;
+ (instancetype)currentApplication;
+ (void) terminateAutomaticallyTerminableApplications;
@end

@interface NSWorkspace (NSWorkspaceRunningApplications)
@property (readonly, copy) NSArray<NSRunningApplication *> *runningApplications;
@end

#endif
