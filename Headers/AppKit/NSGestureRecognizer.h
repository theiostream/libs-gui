#import <Foundation/Foundation.h>

@protocol NSGestureRecognizerDelegate;
@class NSView, NSEvent, NSPressureConfiguration;

typedef enum {
    NSGestureRecognizerStatePossible,
    
    NSGestureRecognizerStateBegan,
    NSGestureRecognizerStateChanged,
    NSGestureRecognizerStateEnded,
    NSGestureRecognizerStateCancelled,
    NSGestureRecognizerStateFailed,
    NSGestureRecognizerStateRecognized = NSGestureRecognizerStateEnded
} NSGestureRecognizerState;

@interface NSGestureRecognizer : NSObject <NSCoding>
- (id)initWithTarget:(id)target action:(nullable SEL)action;
- (id)initWithCoder:(NSCoder *)coder; 

@property (nullable, weak) id target;
@property (nullable) SEL action;

@property (readonly) NSGestureRecognizerState state;

@property (nullable, weak) id <NSGestureRecognizerDelegate> delegate;

@property (getter=isEnabled) BOOL enabled;
@property (nullable, readonly) NSView *view;

@property (strong) NSPressureConfiguration *pressureConfiguration;

@property BOOL delaysPrimaryMouseButtonEvents;      // default is NO.
@property BOOL delaysSecondaryMouseButtonEvents;    // default is NO.
@property BOOL delaysOtherMouseButtonEvents;        // default is NO.
@property BOOL delaysKeyEvents;                     // default is NO.
@property BOOL delaysMagnificationEvents;           // default is NO.
@property BOOL delaysRotationEvents;                // default is NO.

- (NSPoint)locationInView:(nullable NSView*)view;
@end

@protocol NSGestureRecognizerDelegate <NSObject>
@optional
- (BOOL)gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer shouldAttemptToRecognizeWithEvent:(NSEvent *)event;
- (BOOL)gestureRecognizerShouldBegin:(NSGestureRecognizer *)gestureRecognizer;
- (BOOL)gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(NSGestureRecognizer *)otherGestureRecognizer;
- (BOOL)gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(NSGestureRecognizer *)otherGestureRecognizer;
- (BOOL)gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(NSGestureRecognizer *)otherGestureRecognizer;
@end

@interface NSGestureRecognizer (NSSubclassUse)
@property NSGestureRecognizerState state;

- (void)reset;
- (BOOL)canPreventGestureRecognizer:(NSGestureRecognizer *)preventedGestureRecognizer;
- (BOOL)canBePreventedByGestureRecognizer:(NSGestureRecognizer *)preventingGestureRecognizer;
- (BOOL)shouldRequireFailureOfGestureRecognizer:(NSGestureRecognizer *)otherGestureRecognizer;
- (BOOL)shouldBeRequiredToFailByGestureRecognizer:(NSGestureRecognizer *)otherGestureRecognizer;

- (void)mouseDown:(NSEvent *)event;
- (void)rightMouseDown:(NSEvent *)event;
- (void)otherMouseDown:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)rightMouseUp:(NSEvent *)event;
- (void)otherMouseUp:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
- (void)rightMouseDragged:(NSEvent *)event;
- (void)otherMouseDragged:(NSEvent *)event;
- (void)keyDown:(NSEvent *)event;
- (void)keyUp:(NSEvent *)event;
- (void)flagsChanged:(NSEvent *)event;
- (void)tabletPoint:(NSEvent *)event;
- (void)magnifyWithEvent:(NSEvent *)event;
- (void)rotateWithEvent:(NSEvent *)event;
- (void)pressureChangeWithEvent:(NSEvent *)event;
@end
