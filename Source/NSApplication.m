/** <title>NSApplication</title>

   <abstract>The one and only application class</abstract>

   Copyright (C) 1996,1999 Free Software Foundation, Inc.

   Author: Scott Christley <scottc@net-community.com>
   Date: 1996
   Author: Felipe A. Rodriguez <far@ix.netcom.com>
   Date: August 1998
   Author: Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date: December 1998

   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/

#include "config.h"
#include <stdio.h>

#include <Foundation/NSArray.h>
#include <Foundation/NSSet.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSException.h>
#include <Foundation/NSNotification.h>
#include <Foundation/NSObject.h>
#include <Foundation/NSRunLoop.h>
#include <Foundation/NSAutoreleasePool.h>
#include <Foundation/NSTimer.h>
#include <Foundation/NSProcessInfo.h>
#include <Foundation/NSFileManager.h>
#include <Foundation/NSUserDefaults.h>
#include <Foundation/NSBundle.h>

#ifndef LIB_FOUNDATION_LIBRARY
# include <Foundation/NSConnection.h>
#endif

#include "AppKit/AppKitExceptions.h"
#include "AppKit/NSApplication.h"
#include "AppKit/NSDocumentController.h"
#include "AppKit/NSPasteboard.h"
#include "AppKit/NSFontManager.h"
#include "AppKit/NSPanel.h"
#include "AppKit/NSEvent.h"
#include "AppKit/NSImage.h"
#include "AppKit/NSMenu.h"
#include "AppKit/NSMenuItem.h"
#include "AppKit/NSMenuItemCell.h"
#include "AppKit/NSMenuView.h"
#include "AppKit/NSCursor.h"
#include "AppKit/NSWorkspace.h"
#include "AppKit/NSNibLoading.h"
#include "AppKit/NSPageLayout.h"

#include "GNUstepGUI/GSDisplayServer.h"
#include "GNUstepGUI/GSServicesManager.h"
#include "GSGuiPrivate.h"
#include "GNUstepGUI/GSInfoPanel.h"

/* The -gui thread. See the comment in initialize_gnustep_backend. */
NSThread *GSAppKitThread;

/*
 * Base library exception handler
 */
static NSUncaughtExceptionHandler *defaultUncaughtExceptionHandler;

/*
 * Gui library user friendly exception handler 
 */
static void
_NSAppKitUncaughtExceptionHandler (NSException *exception)
{
  int retVal;

  /* Reset the exception handler to the Base library's one, to prevent
     recursive calls to the gui one. */
  NSSetUncaughtExceptionHandler (defaultUncaughtExceptionHandler);  

  /*
   * If there is no graphics context to run the alert panel in or
   * its a sever error, use a non-graphical exception handler
   */
  if (GSCurrentContext() == nil
    || [[exception name] isEqual: NSWindowServerCommunicationException]
    || [[exception name] isEqual: GSWindowServerInternalException])
    {
      /* The following will raise again the exception using the base 
	 library exception handler */
      [exception raise];
    }

  retVal = NSRunCriticalAlertPanel 
    ([NSString stringWithFormat: _(@"Critical Error in %@"),
	       [[NSProcessInfo processInfo] processName]],
     @"%@: %@", 
     _(@"Abort"), 
     _(@"Ignore"),
#ifdef DEBUG
     _(@"Debug"),
#else
     nil,
#endif
     [exception name], 
     [exception reason]);

  /* The user wants to abort */
  if (retVal == NSAlertDefault)
    {
      /* The following will raise again the exception using the base 
	 library exception handler */
      [exception raise];
    }
  else if (retVal == NSAlertOther)
    {
      /* Debug button: abort so we can trace the error in gdb */
      abort();
    }

  /* The user said to go on - more fun I guess - turn the AppKit
     exception handler on again */
  NSSetUncaughtExceptionHandler (_NSAppKitUncaughtExceptionHandler);
}

/* This is the bundle from where we load localization of messages.  */
static NSBundle *guiBundle = nil;

/* Get the bundle.  */
NSBundle *GSGuiBundle ()
{
  return guiBundle;
}

@interface GSBackend : NSObject
{}
+ (void) initializeBackend;
@end

BOOL
initialize_gnustep_backend(void)
{
  static int first = 1;

  if (first)
    {
      Class backend;

      /*
      Remember which thread we are running in. This thread will be the
      -gui thread, ie. the only thread that may do any rendering. With
      the exception of a few methods explicitly marked as thread-safe,
      other threads should not call any methods in -gui.
      */
      GSAppKitThread = [NSThread currentThread];

      first = 0;
#ifdef BACKEND_BUNDLE
      {      
	NSBundle *theBundle;
	NSEnumerator *benum;
	NSString *path, *bundleName;
	NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];

	/* What backend ? */
	bundleName = [defs stringForKey: @"GSBackend"];
	if ( bundleName == nil )
	  bundleName = @"libgnustep-back.bundle";
	else
	  bundleName = [bundleName stringByAppendingString: @".bundle"];
	NSDebugFLLog(@"BackendBundle", @"Looking for %@", bundleName);

	/* Find the backend bundle */
	benum = [NSStandardLibraryPaths() objectEnumerator];
	while ((path = [benum nextObject]))
	  {
	    path = [path stringByAppendingPathComponent: @"Bundles"];
	    path = [path stringByAppendingPathComponent: bundleName];
	    if ([[NSFileManager defaultManager] fileExistsAtPath: path])
	      {
		break;
	      }
	  }

	/* FIXME/TODO - update localized error messages.  */

	/* Backend found ? */
	NSCAssert1(path != nil, _(@"Unable to find backend %@"), bundleName);
	NSDebugLog(@"Loading Backend from %@", path);
	NSDebugFLLog(@"BackendBundle", @"Loading Backend from %@", path);

	/* Create a bundle object.  (Should normally succeed).  */
	theBundle = [NSBundle bundleWithPath: path];
	NSCAssert1(theBundle != nil, 
		   _(@"Can't create NSBundle object for backend at path %@"),
		   path);

	/* Now load the object file from the bundle.  */
	NSCAssert1 ([theBundle load],
		    _(@"Can't load object file from backend at path %@"),
		    path);
	
	/* Now get the GSBackend class, which should have just been loaded
	 * from the bundle.  */
	backend = NSClassFromString (@"GSBackend");
	NSCAssert1 (backend != Nil, 
	  _(@"Backend at path %@ doesn't contain the GSBackend class"), path);
	[backend initializeBackend];
      }

#else
      /* GSBackend will be in a separate library, so use the runtime
	 to find the class and avoid an unresolved reference problem */
      backend = [[NSBundle gnustepBundle] classNamed: @"GSBackend"];
      NSCAssert (backend, _(@"Can't find backend context"));
      [backend initializeBackend];
#endif
    }
  return YES;
}

void
gsapp_user_bundles()
{
  NSUserDefaults *defs=[NSUserDefaults standardUserDefaults];
  NSArray *a=[defs arrayForKey: @"GSAppKitUserBundles"];
  int i, c;
  c = [a count];
  if (a == nil || c == 0)
    return;
  NSLog(@"Loading %d user defined AppKit bundles", c);
  for (i = 0; i < c; i++)
    {
      NSBundle *b = [NSBundle bundleWithPath: [a objectAtIndex: i]];
      if (!b)
	{
	  NSLog(@"* Unable to load '%@'", [a objectAtIndex: i]);
	  continue;
	}
      NSLog(@"Loaded '%@'\n", [a objectAtIndex: i]);
      [[[b principalClass] alloc] init];
    }
}

/*
 * Types
 */
struct _NSModalSession {
  int			runState;
  int			entryLevel;
  NSWindow		*window;
  NSModalSession	previous;
};
 
@interface NSDocumentController (ApplicationPrivate)
+ (BOOL) isDocumentBasedApplication;
@end

@interface NSApplication (Private)
- _appIconInit;
- (void) _openDocument: (NSString*)name;
- (void) _windowDidBecomeKey: (NSNotification*) notification;
- (void) _windowDidBecomeMain: (NSNotification*) notification;
- (void) _windowDidResignKey: (NSNotification*) notification;
- (void) _windowWillClose: (NSNotification*) notification;
@end

@interface NSIconWindow : NSWindow
@end

@interface NSAppIconView : NSView
- (void) setImage: (NSImage *)anImage;
@end

/*
 * Class variables
 */
static NSEvent *null_event;
static Class arpClass;
static NSNotificationCenter *nc;

NSApplication	*NSApp = nil;

@implementation	NSIconWindow

- (BOOL) canBecomeMainWindow
{
  return NO;
}

- (BOOL) canBecomeKeyWindow
{
  return NO;
}

- (BOOL) worksWhenModal
{
  return YES;
}

- (void) orderWindow: (NSWindowOrderingMode)place relativeTo: (int)otherWin
{
  if ((place == NSWindowOut) && [NSApp isRunning])
    {
      NSLog (@"Argh - icon window ordered out");
    }
  else
    {
      [super orderWindow: place relativeTo: otherWin];
    }
}

- (void) _initDefaults
{
  [super _initDefaults];
  /* Set the title of the window to the process name. Even as the
     window shows no title bar, the window manager may show it.  */
  [self setTitle: [[NSProcessInfo processInfo] processName]];
  [self setExcludedFromWindowsMenu: YES];
  [self setReleasedWhenClosed: NO];
  _windowLevel = NSDockWindowLevel;
}

@end

@implementation NSAppIconView

// Class variables
static NSCell* dragCell = nil;
static NSCell* tileCell = nil;

+ (void) initialize
{
  NSImage	*defImage = [NSImage imageNamed: @"GNUstep"];
  NSImage	*tileImage = [NSImage imageNamed: @"common_Tile"];

  dragCell = [[NSCell alloc] initImageCell: defImage];
  [dragCell setBordered: NO];
  tileCell = [[NSCell alloc] initImageCell: tileImage];
  [tileCell setBordered: NO];
}

- (BOOL) acceptsFirstMouse: (NSEvent*)theEvent
{
  return YES;
}

- (void) concludeDragOperation: (id<NSDraggingInfo>)sender
{
}

- (unsigned) draggingEntered: (id<NSDraggingInfo>)sender
{
  return NSDragOperationGeneric;
}

- (void) draggingExited: (id<NSDraggingInfo>)sender
{
}

- (unsigned) draggingUpdated: (id<NSDraggingInfo>)sender
{
  return NSDragOperationGeneric;
}

- (void) drawRect: (NSRect)rect
{
  [tileCell drawWithFrame: NSMakeRect(0,0,64,64) inView: self];
  [dragCell drawWithFrame: NSMakeRect(8,8,48,48) inView: self];
}

- (id) initWithFrame: (NSRect)frame
{
  self = [super initWithFrame: frame];
  [self registerForDraggedTypes: [NSArray arrayWithObjects:
    NSFilenamesPboardType, nil]];
  return self;
}

- (void) mouseDown: (NSEvent*)theEvent
{
  if ([theEvent clickCount] >= 2)
    {
      [NSApp unhide: self];
    }
  else
    {
      NSPoint	lastLocation;
      NSPoint	location;
      unsigned	eventMask = NSLeftMouseDownMask | NSLeftMouseUpMask
	| NSPeriodicMask | NSOtherMouseUpMask | NSRightMouseUpMask;
      NSDate	*theDistantFuture = [NSDate distantFuture];
      BOOL	done = NO;

      lastLocation = [theEvent locationInWindow];
      [NSEvent startPeriodicEventsAfterDelay: 0.02 withPeriod: 0.02];

      while (!done)
	{
	  theEvent = [NSApp nextEventMatchingMask: eventMask
					 untilDate: theDistantFuture
					    inMode: NSEventTrackingRunLoopMode
					   dequeue: YES];
	
	  switch ([theEvent type])
	    {
	      case NSRightMouseUp:
	      case NSOtherMouseUp:
	      case NSLeftMouseUp:
	      /* any mouse up means we're done */
		done = YES;
		break;
	      case NSPeriodic:
		location = [_window mouseLocationOutsideOfEventStream];
		if (NSEqualPoints(location, lastLocation) == NO)
		  {
		    NSPoint	origin = [_window frame].origin;

		    origin.x += (location.x - lastLocation.x);
		    origin.y += (location.y - lastLocation.y);
		    [_window setFrameOrigin: origin];
		  }
		break;

	      default:
		break;
	    }
	}
      [NSEvent stopPeriodicEvents];
    }
}                                                        

- (BOOL) prepareForDragOperation: (id<NSDraggingInfo>)sender
{
  return YES;
}

- (BOOL) performDragOperation: (id<NSDraggingInfo>)sender
{
  NSArray	*types;
  NSPasteboard	*dragPb;

  dragPb = [sender draggingPasteboard];
  types = [dragPb types];
  if ([types containsObject: NSFilenamesPboardType] == YES)
    {
      NSArray	*names = [dragPb propertyListForType: NSFilenamesPboardType];
      unsigned	index;

      [NSApp activateIgnoringOtherApps: YES];
      for (index = 0; index < [names count]; index++)
	{
	  [NSApp _openDocument: [names objectAtIndex: index]];
	}
      return YES;
    }
  return NO;
}

- (void) setImage: (NSImage *)anImage
{
  [dragCell setImage: anImage];

  if ([self lockFocusIfCanDraw])
    {
      [tileCell drawWithFrame: NSMakeRect(0,0,64,64) inView: self];
      [dragCell drawWithFrame: NSMakeRect(8,8,48,48) inView: self];
      [self unlockFocus];
      [_window flushWindow];
    }
}

@end

@implementation NSApplication

/*
 * Class methods
 */
+ (void) initialize
{
  if (self == [NSApplication class])
    {
      CREATE_AUTORELEASE_POOL(pool);
      /*
       * Dummy functions to fool linker into linking files that contain
       * only catagories - static libraries seem to have problems here.
       */
      extern void	GSStringDrawingDummyFunction();

      GSStringDrawingDummyFunction();

      [self setVersion: 1];
      
      /* Create the gui bundle we use to localize messages.  */
      guiBundle = [NSBundle bundleForLibrary: @"gnustep-gui"];
      RETAIN(guiBundle);

      /* Save the base library exception handler */
      defaultUncaughtExceptionHandler = NSGetUncaughtExceptionHandler ();
      
      /* Cache the NSAutoreleasePool class */
      arpClass = [NSAutoreleasePool class];
      nc = [NSNotificationCenter defaultCenter];
      RELEASE(pool);
    }
}

// Helper method
+ (void) _invokeWithAutoreleasePool: (NSInvocation*) inv
{
  CREATE_AUTORELEASE_POOL(pool);

  [inv invoke];
  RELEASE(pool);
}

+ (void) detachDrawingThread: (SEL)selector
		    toTarget: (id)target
		  withObject: (id)argument
{
  NSInvocation *inv;

  // This uses a GNUstep extension on NSInvocation
  inv = [[NSInvocation alloc] initWithTarget: target 
			      selector: selector, argument];
  [NSThread detachNewThreadSelector: @selector(_invokeWithAutoreleasePool:) 
	    toTarget: self 
	    withObject: inv];
  RELEASE(inv);
}

/* 
 * Return the shared application instance, creating one (of the
 * receiver class) if needed.  There is (and must always be) only a
 * single shared application instance for each application.  After the
 * shared application instance has been created, you can access it
 * directly via the global variable NSApp (but not before!).  When the
 * shared application instance is created, it is also automatically
 * initialized (that is, its -init method is called), which connects
 * to the window server and prepares the gui library for actual
 * operation.  For this reason, you must always call [NSApplication
 * sharedApplication] before using any functionality of the gui
 * library - so, normally, this should be one of the first commands in
 * your program (if you use NSApplicationMain(), this is automatically
 * done).
 *
 * The shared application instance is normally an instance of
 * NSApplication; but you can subclass NSApplication, and have an
 * instance of your own subclass be created and used as the shared
 * application instance.  If you want to get this result, you need to
 * make sure the first time you call +sharedApplication is on your
 * custom NSApplication subclass (rather than on NSApplication).
 * Putting [MyApplicationClass sharedApplication]; as the first
 * command in your program is the recommended way. :-) If you use
 * NSApplicationMain(), it automatically creates the appropriate
 * instance (which you can control by editing the info dictionary of
 * the application).
 *
 * It is not safe to call this method from multiple threads - it would
 * be useless anyway since the whole library is not thread safe: there
 * must always be at most one thread using the gui library at a time.
 * (If you absolutely need to have multiple threads in your
 * application, make sure only one of them uses the gui [the 'drawing'
 * thread], and the other ones do not).
 */
+ (NSApplication *) sharedApplication
{
  /* If the global application does not yet exist then create it.  */
  if (NSApp == nil)
    {
      /* -init sets NSApp.  */
      [[self alloc] init];
    }
  return NSApp;
}

/*
 * Instance methods
 */

/**
 * The real gui initialisation ... called from -init
 */
- (void) _init
{
  GSDisplayServer *srv;
  /* Initialization must be enclosed in an autorelease pool.  */
  CREATE_AUTORELEASE_POOL (_app_init_pool);
  
  /* 
   * Set NSApp as soon as possible, since other gui classes (which
   * we refer or use in this method) might be calling [NSApplication
   * sharedApplication] during their initialization, and we want
   * those calls to succeed.  
   */
  NSApp = self;
  
  /* Initialize the backend here.  */
  initialize_gnustep_backend();

  /* Load user-defined bundles */
  gsapp_user_bundles();
  
  /* Connect to our window server.  */
  srv = [GSDisplayServer serverWithAttributes: nil];
  RETAIN(srv);
  [GSDisplayServer setCurrentServer: srv];
  
  /* Create a default context.  */
  _default_context = [NSGraphicsContext graphicsContextWithAttributes: nil];
  RETAIN(_default_context);
  [NSGraphicsContext setCurrentContext: _default_context];
  
  /* Initialize font manager.  */
  [NSFontManager sharedFontManager];
  
  _hidden = [[NSMutableArray alloc] init];
  _inactive = [[NSMutableArray alloc] init];
  _unhide_on_activation = YES;
  _app_is_hidden = YES;
  /* Ivar already automatically initialized to NO when the app is
     created.  */
  //_app_is_active = NO;
  //_main_menu = nil;
  _windows_need_update = YES;
  
  /* Set a new exception handler for the gui library.  */
  NSSetUncaughtExceptionHandler (_NSAppKitUncaughtExceptionHandler);
  
  _listener = [GSServicesManager newWithApplication: self];
  
  /* NSEvent doesn't use -init so we use +alloc instead of +new.  */
  _current_event = [NSEvent alloc]; // no current event
  null_event = [NSEvent alloc];    // create dummy event
  
  /* We are the end of responder chain.  */
  [self setNextResponder: nil];
  
  RELEASE (_app_init_pool);
}


/* 
 * This method initializes an NSApplication instance.  It sets the
 * shared application instance to be the receiver, and then connects
 * to the window server and performs the actual gui library
 * initialization.
 *
 * If there is a already a shared application instance, calling this
 * method results in an assertion (and normally program abortion/crash).
 *
 * It is recommended that you /never/ call this method directly from
 * your code!  It's called automatically (and only once) by
 * [NSApplication sharedApplication].  You might override this method
 * in subclasses (make sure to call super's :-), then your overridden
 * method will automatically be called (guaranteed once in the
 * lifetime of the application) when you call [MyApplicationClass
 * sharedApplication].
 *
 * If you call this method from your code (which we discourage you
 * from doing), it is /your/ responsibility to make sure it is called
 * only once (this is according to the openstep specification).  Since
 * +sharedApplication automatically calls this method, making also
 * sure it calls it only once, you definitely want to use
 * +sharedApplication instead of calling -init directly.  
 */
- (id) init
{
  /*
   * As per openstep specification, calling -init twice is a bug in
   * the program.  +sharedApplication automatically makes sure it
   * never calls -init more than once, and programmers should normally
   * use +sharedApplication in programs.
   *
   * Please refrain from trying to have this method work with multiple
   * calls (such as returning NSApp instead of raising an assertion).
   * No matter what you do, you can't protect subclass -init custom
   * code from multiple executions by changing the implementation here
   * - so it's just simpler and cleaner that multiple -init executions
   * are always forbidden, and subclasses inherit exactly the same
   * kind of multiple execution protection as the superclass has, and
   * initialization code behaves always in the same way for this class
   * and for subclasses.
   */
  NSAssert (NSApp == nil, _(@"[NSApplication -init] called more than once"));

  /*
   * The appkit should run in the main thread ... so to be sure we perform
   * all the initialisation there.
   */
  [self performSelectorOnMainThread: @selector(_init)
			 withObject: self
		      waitUntilDone: YES];
  return NSApp;
}

- (void) finishLaunching
{
  NSBundle		*mainBundle = [NSBundle mainBundle];
  NSDictionary		*infoDict = [mainBundle infoDictionary];
  NSString		*mainModelFile;
  NSString		*appIconFile;
  NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  NSString		*filePath;
  NSArray		*windows_list;
  unsigned		count;
  unsigned		i;
  BOOL			hadDuplicates = NO;

  appIconFile = [infoDict objectForKey: @"NSIcon"];
  if (appIconFile && ![appIconFile isEqual: @""])
    {
      NSImage	*image = [NSImage imageNamed: appIconFile];

      if (image != nil)
	{
	  [self setApplicationIconImage: image];
	}
    }
  [self _appIconInit];

  mainModelFile = [infoDict objectForKey: @"NSMainNibFile"];
  if (mainModelFile != nil && [mainModelFile isEqual: @""] == NO)
    {
      if ([NSBundle loadNibNamed: mainModelFile owner: self] == NO)
	{
	  NSLog (_(@"Cannot load the main model file '%@'"), mainModelFile);
	}
    }

  /* post notification that launch will finish */
  [nc postNotificationName: NSApplicationWillFinishLaunchingNotification
      object: self];

  /* Register our listener to incoming services requests etc. */
  [_listener registerAsServiceProvider];

  /*
   * Establish the current key and main windows.  We need to do this in case
   * the windows were created and set to be key/main earlier - before the
   * app was active.
   */
  windows_list = [self windows];
  count = [windows_list count];
  for (i = 0; i < count; i++)
    {
      NSWindow	*win = [windows_list objectAtIndex: i];

      if ([win isKeyWindow] == YES)
	{
	  if (_key_window == nil)
	    {
	      _key_window = win;
	    }
	  else
	    {
	      hadDuplicates = YES;
	      NSDebugLog(@"Duplicate keyWindow ignored");
	      [win resignKeyWindow];
	    }
	}
      if ([win isMainWindow] == YES)
	{
	  if (_main_window == nil)
	    {
	      _main_window = win;
	    }
	  else
	    {
	      hadDuplicates = YES;
	      NSDebugLog(@"Duplicate mainWindow ignored");
	      [win resignMainWindow];
	    }
	}
    }

  /*
   * If there was more than one window set as key or main, we must make sure
   * that the one we have recorded is the real one by making it become key/main
   * again.
   */
  if (hadDuplicates)
    {
      [_main_window resignMainWindow];
      [_main_window becomeMainWindow];
      [_main_window orderFrontRegardless];
      [_key_window resignKeyWindow];
      [_key_window becomeKeyWindow];
      [_key_window orderFrontRegardless];
    }

  /* Register self as observer to window events. */
  [nc addObserver: self selector: @selector(_windowWillClose:)
      name: NSWindowWillCloseNotification object: nil];
  [nc addObserver: self selector: @selector(_windowDidBecomeKey:)
      name: NSWindowDidBecomeKeyNotification object: nil];
  [nc addObserver: self selector: @selector(_windowDidBecomeMain:)
      name: NSWindowDidBecomeMainNotification object: nil];
  [nc addObserver: self selector: @selector(_windowDidResignKey:)
      name: NSWindowDidResignKeyNotification object: nil];
  [nc addObserver: self selector: @selector(_windowDidResignMain:)
      name: NSWindowDidResignMainNotification object: nil];

  [self activateIgnoringOtherApps: YES];

  /* Instantiate the NSDocumentController if we are a doc-based app */
  if ([NSDocumentController isDocumentBasedApplication])
    [NSDocumentController sharedDocumentController];

  /*
   *	Now check to see if we were launched with arguments asking to
   *	open a file.  We permit some variations on the default name.
   */
  if ((filePath = [defs stringForKey: @"GSFilePath"]) != nil
    || (filePath = [defs stringForKey: @"NSOpen"]) != nil)
    {
      [_listener application: self openFile: filePath];
    }
  else if ((filePath = [defs stringForKey: @"GSTempPath"]) != nil)
    {
      [_listener application: self openTempFile: filePath];
    }
  else if ((filePath = [defs stringForKey: @"NSPrint"]) != nil)
    {
      [_listener application: self printFile: filePath];
      [self terminate: self];
    }
  else if ([_delegate respondsToSelector:
    @selector(applicationShouldOpenUntitledFile:)]
    && ([_delegate applicationShouldOpenUntitledFile: self] == YES)
    && [_delegate respondsToSelector: @selector(applicationOpenUntitledFile:)])
    {
      [_delegate applicationOpenUntitledFile: self];
    }
  
  /* finish the launching post notification that launching has finished */
  [nc postNotificationName: NSApplicationDidFinishLaunchingNotification
		    object: self];

  NS_DURING
    [[workspace notificationCenter]
      postNotificationName: NSWorkspaceDidLaunchApplicationNotification
      object: workspace
      userInfo: [workspace activeApplication]];
  NS_HANDLER
    NSLog (_(@"Problem during launch app notification: %@"),
	   [localException reason]);
    [localException raise];
  NS_ENDHANDLER
}

- (void) dealloc
{
  GSDisplayServer *srv = GSServerForWindow(_app_icon_window);

  [nc removeObserver: self];

  RELEASE(_hidden);
  RELEASE(_inactive);
  RELEASE(_listener);
  RELEASE(null_event);
  RELEASE(_current_event);

  /* We may need to tidy up nested modal session structures. */
  while (_session != 0)
    {
      NSModalSession tmp = _session;

      _session = tmp->previous;
      NSZoneFree(NSDefaultMallocZone(), tmp);
    }

  /* Release the menus, then set them to nil so we don't try updating
     them after they have been deallocated.  */
  DESTROY(_main_menu);
  DESTROY(_windows_menu);

  TEST_RELEASE(_app_icon);
  TEST_RELEASE(_app_icon_window);
  TEST_RELEASE(_infoPanel);

  /* Destroy the default context */
  [NSGraphicsContext setCurrentContext: nil];
  DESTROY(_default_context);

  /* Close the server */
  [srv closeServer];
  DESTROY(srv);

  [super dealloc];
}

/*
 * Changing the active application
 */
- (void) activateIgnoringOtherApps: (BOOL)flag
{
  // TODO: Currently the flag is ignored
  if (_app_is_active == NO)
    {
      unsigned			count = [_inactive count];
      unsigned			i;

     /*
       * Menus should observe this notification in order to make themselves
       * visible when the application is active.
       */
      [nc postNotificationName: NSApplicationWillBecomeActiveNotification
			object: self];

      _app_is_active = YES;

      for (i = 0; i < count; i++)
	{
	  [[_inactive objectAtIndex: i] orderFrontRegardless];
	}
      [_inactive removeAllObjects];
      if (_hidden_key != nil
	&& [[self windows] indexOfObjectIdenticalTo: _hidden_key] != NSNotFound)
	{
	  [_hidden_key makeKeyWindow];
	  _hidden_key = nil;
	}

      if (_unhide_on_activation)
	{
	  [self unhide: nil];
	}

      if ([self keyWindow] != nil)
	{
	  [[self keyWindow] orderFront: self];
	}
      else if ([self mainWindow] != nil)
	{
	  [[self mainWindow] orderFront: self];
	}

      [nc postNotificationName: NSApplicationDidBecomeActiveNotification
			object: self];
    }
}

- (void) deactivate
{
  if (_app_is_active == YES)
    {
      NSArray			*windows_list = [self windows]; 
      unsigned			count = [windows_list count];
      unsigned			i;

      [nc postNotificationName: NSApplicationWillResignActiveNotification
			object: self];

      _app_is_active = NO;

      if ([self keyWindow] != nil)
	{
	  _hidden_key = [self keyWindow];
	  [_hidden_key resignKeyWindow];
	}
      for (i = 0; i < count; i++)
	{
	  NSModalSession theSession;
	  NSWindow	*win = [windows_list objectAtIndex: i];

	  if ([win isVisible] == NO)
	    {
	      continue;		/* Already invisible	*/
	    }
	  if (win == _app_icon_window)
	    {
	      continue;		/* can't hide the app icon.	*/
	    }
	  /* Don't order out modal windows */
	  theSession = _session;
	  while (theSession != 0)
	    {
	      if (win == theSession->window)
		break;
	      theSession = theSession->previous;
	    }
	  if (theSession)
	    continue;

	  if ([win hidesOnDeactivate] == YES)
	    {
	      [_inactive addObject: win];
	      [win orderOut: self];
	    }
	}

      [nc postNotificationName: NSApplicationDidResignActiveNotification
			object: self];
    }
}

- (BOOL) isActive
{
  return _app_is_active;
}

- (void) hideOtherApplications: (id)sender
{
  // FIXME Currently does nothing
}

- (void) unhideAllApplications: (id)sender
{
  // FIXME Currently does nothing
}

/*
 * Running the main event loop
 */
- (void) run
{
  NSEvent *e;
  id distantFuture = [NSDate distantFuture];     /* Cache this, safe */
  
  if (_runLoopPool != nil)
    {
      [NSException raise: NSInternalInconsistencyException
		   format: @"NSApp's run called recursively"];
    }

  IF_NO_GC(_runLoopPool = [arpClass new]);
  /*
   *  Set this flag here in case the application is actually terminated
   *  inside -finishLaunching.
   */
  _app_is_running = YES;

  [self finishLaunching];

  [_listener updateServicesMenu];
  [_main_menu update];
  DESTROY(_runLoopPool);
 
  while (_app_is_running)
    {
      IF_NO_GC(_runLoopPool = [arpClass new]);

      e = [self nextEventMatchingMask: NSAnyEventMask
			    untilDate: distantFuture
			       inMode: NSDefaultRunLoopMode
			      dequeue: YES];

      if (e != nil &&  e != null_event)
	{
	  NSEventType	type = [e type];

	  [self sendEvent: e];

	  // update (en/disable) the services menu's items
	  if (type != NSPeriodic && type != NSMouseMoved)
	    {
	      [_listener updateServicesMenu];
	      [_main_menu update];
	    }
	}

      // send an update message to all visible windows
      if (_windows_need_update)
	{
	  [self updateWindows];
	}

      DESTROY (_runLoopPool);
    }

  /* Every single non trivial line of code must be enclosed into an
     autorelease pool.  Create an autorelease pool here to wrap
     synchronize and the NSDebugLog.  */
  IF_NO_GC(_runLoopPool = [arpClass new]);

  [[NSUserDefaults standardUserDefaults] synchronize];
  DESTROY (_runLoopPool);
}

- (BOOL) isRunning
{
  return _app_is_running;
}

/*
 * Running modal event loops
 */
- (void) abortModal
{
  if (_session == 0)
    {
      [NSException raise: NSAbortModalException
		  format: @"abortModal called while not in a modal session"];
    }
  [NSException raise: NSAbortModalException format: @"abortModal"];
}

- (NSModalSession) beginModalSessionForWindow: (NSWindow*)theWindow
{
  NSModalSession theSession;

  theSession = (NSModalSession)NSZoneMalloc(NSDefaultMallocZone(),
		    sizeof(struct _NSModalSession));
  theSession->runState = NSRunContinuesResponse;
  theSession->entryLevel = [theWindow level];
  theSession->window = theWindow;
  theSession->previous = _session;
  _session = theSession;

  /*
   * The NSWindow documentation says runModalForWindow centers panels.
   * Here would seem the best place to do it.
   */
  if ([theWindow isKindOfClass: [NSPanel class]])
    {
      [theWindow center];
      [theWindow setLevel: NSModalPanelWindowLevel];
    }
  [theWindow orderFrontRegardless];
  if ([self isActive] == YES)
    {
      if ([theWindow canBecomeKeyWindow] == YES)
	{
	  [theWindow makeKeyWindow];
	}
      else if ([theWindow canBecomeMainWindow] == YES)
	{
	  [theWindow makeMainWindow];
	}
    }

  return theSession;
}

- (void) endModalSession: (NSModalSession)theSession
{
  NSModalSession	tmp = _session;
  NSArray		*windows = [self windows];

  if (theSession == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"null pointer passed to endModalSession:"];
    }
  /* Remove this session from linked list of sessions. */
  while (tmp != 0 && tmp != theSession)
    {
      tmp = tmp->previous;
    }
  if (tmp == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"unknown session passed to endModalSession:"];
    }
  while (_session != theSession)
    {
      tmp = _session;
      _session = tmp->previous;
      if ([windows indexOfObjectIdenticalTo: tmp->window] != NSNotFound)
	{
	  [tmp->window setLevel: tmp->entryLevel];
	}
      NSZoneFree(NSDefaultMallocZone(), tmp);
    }
  _session = _session->previous;
  if ([windows indexOfObjectIdenticalTo: theSession->window] != NSNotFound)
    {
      [theSession->window setLevel: theSession->entryLevel];
    }
  NSZoneFree(NSDefaultMallocZone(), theSession);
}

- (int) runModalForWindow: (NSWindow*)theWindow
{
  NSModalSession theSession = 0;
  int code = NSRunContinuesResponse;

  NS_DURING
    {
      theSession = [self beginModalSessionForWindow: theWindow];
      while (code == NSRunContinuesResponse)
	{
	  code = [self runModalSession: theSession];
	}
      [self endModalSession: theSession];
    }
  NS_HANDLER
    {
      if (theSession != 0)
	{
	  NSWindow *win_to_close = theSession->window;
	  
	  [self endModalSession: theSession];
	  [win_to_close close];
	}
      if ([[localException name] isEqual: NSAbortModalException] == NO)
	{
	  [localException raise];
     	} 
      code = NSRunAbortedResponse;
    }
  NS_ENDHANDLER

  return code;
}

/** 
<p>
Processes one event for a modal session described by the theSession
variable. Before processing the event, it makes the session window key
and orders the window front, so there is no need to do this
separately. When finished, it returns the state of the session (i.e.
whether it is still running or has been stopped, etc) 
</p>
<p>
See Also: -runModalForWindow:
</p>
*/
- (int) runModalSession: (NSModalSession)theSession
{
  NSAutoreleasePool	*pool;
  GSDisplayServer	*srv;
  BOOL		found = NO;
  NSEvent	*event;
  NSDate	*limit;
  
  if (theSession != _session)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"runModalSession: with wrong session"];
    }

  IF_NO_GC(pool = [arpClass new]);

  [theSession->window orderFrontRegardless];
  if ([theSession->window canBecomeKeyWindow] == YES)
    {
      [theSession->window makeKeyWindow];
    }
  else if ([theSession->window canBecomeMainWindow] == YES)
    {
      [theSession->window makeMainWindow];
    }

  // Use the default context for all events.
  srv = GSCurrentServer();

  /*
   * Set a limit date in the distant future so we wait until we get an
   * event.  We discard events that are not for this window.  When we
   * find one for this window, we push it back at the start of the queue.
   */
  limit = [NSDate distantFuture];
  do
    {
      event = DPSGetEvent(srv, NSAnyEventMask, limit, NSDefaultRunLoopMode);
      if (event != nil)
	{
	  NSWindow	*eventWindow = [event window];

	  if (eventWindow == theSession->window || [eventWindow worksWhenModal])
	    {
	      DPSPostEvent(srv, event, YES);
	      found = YES;
	    }
	  else if ([event type] == NSAppKitDefined)
	    {
	      /* Handle resize and other window manager events now */
	      [self sendEvent: event];
	    }
	}
    }
  while (found == NO && theSession->runState == NSRunContinuesResponse);

  RELEASE (pool);
  /*
   *	Deal with the events in the queue.
   */
  
  while (found == YES && theSession->runState == NSRunContinuesResponse)
    {
      IF_NO_GC(pool = [arpClass new]);

      event = DPSGetEvent(srv, NSAnyEventMask, limit, NSDefaultRunLoopMode);
      if (event != nil)
	{
	  NSWindow	*eventWindow = [event window];

	  if (eventWindow == theSession->window || [eventWindow worksWhenModal])
	    {
	      ASSIGN(_current_event, event);
	    }
	  else
	    {
	      found = NO;
	    }
	}
      else
	{
	  found = NO;
	}

      if (found == YES)
	{
	  NSEventType	type = [_current_event type];

	  [self sendEvent: _current_event];

	  // update (en/disable) the services menu's items
	  if (type != NSPeriodic && type != NSMouseMoved)
	    {
	      [_listener updateServicesMenu];
	      [_main_menu update];
	    }

	  /*
	   *	Check to see if the window has gone away - if so, end session.
	   */
	  if ([[self windows] indexOfObjectIdenticalTo: _session->window] ==
	    NSNotFound)
	    {
	      [self stopModal];
	    }
	  if (_windows_need_update)
	    {
	      [self updateWindows];
	    }
	}
      RELEASE (pool);
    }

  NSAssert(_session == theSession, @"Session was changed while running");

  return theSession->runState;
}

/**
<p>
   Returns the window that is part of the current modal session, if any.
</p>
<p>
See -runModalForWindow:
</p>
*/
- (NSWindow *) modalWindow
{
  if (_session != 0) 
    return (_session->window);
  else
    return nil;
}

- (void) stop: (id)sender
{
  if (_session != 0)
    [self stopModal];
  else
    {
      _app_is_running = NO;
      /*
       * add dummy event to queue to assure loop cycles
       * at least one more time
       */
      DPSPostEvent(GSCurrentServer(), null_event, NO);
    }
}

- (void) stopModal
{
  [self stopModalWithCode: NSRunStoppedResponse];
}

- (void) stopModalWithCode: (int)returnCode
{
  if (_session == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"stopModalWithCode: when not in a modal session"];
    }
  else if (returnCode == NSRunContinuesResponse)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"stopModalWithCode: with NSRunContinuesResponse"];
    }
  _session->runState = returnCode;
}

- (int) runModalForWindow: (NSWindow *)theWindow
	relativeToWindow: (NSWindow *)docWindow
{
  // FIXME
  return [self runModalForWindow: theWindow];
}

- (void) beginSheet: (NSWindow *)sheet
     modalForWindow: (NSWindow *)docWindow
      modalDelegate: (id)modalDelegate
     didEndSelector: (SEL)didEndSelector
	contextInfo: (void *)contextInfo
{
  // FIXME
  int ret;

  ret = [self runModalForWindow: sheet 
	      relativeToWindow: docWindow];

  if ([modalDelegate respondsToSelector: didEndSelector])
    {
      void (*didEnd)(id, SEL, int, void*);

      didEnd = (void (*)(id, SEL, int, void*))[modalDelegate methodForSelector: 
								 didEndSelector];
      didEnd(modalDelegate, didEndSelector, ret, contextInfo);
    }
}

- (void) endSheet: (NSWindow *)sheet
{
  // FIXME
  [self stopModal];
}

- (void) endSheet: (NSWindow *)sheet
       returnCode: (int)returnCode
{
  // FIXME
  [self stopModalWithCode: returnCode];
}


/*
 * Getting, removing, and posting events
 */
- (void) sendEvent: (NSEvent *)theEvent
{
  NSEventType type;
  
  type = [theEvent type];
  switch (type)
    {
      case NSPeriodic:	/* NSApplication traps the periodic events	*/
	break;

      case NSKeyDown:
	{
	  NSDebugLLog(@"NSEvent", @"send key down event\n");
	  if ([theEvent modifierFlags] & NSCommandKeyMask)
	    {
	      NSArray	*window_list = [self windows];
	      unsigned	i;
	      unsigned	count = [window_list count];

	      for (i = 0; i < count; i++)
		{
		  NSWindow	*window = [window_list objectAtIndex: i];

		  if ([window performKeyEquivalent: theEvent] == YES)
		    break;
		}
	    }
	  else
	    [[theEvent window] sendEvent: theEvent];
	  break;
	}

      case NSKeyUp:
	{
	  NSDebugLLog(@"NSEvent", @"send key up event\n");
	  [[theEvent window] sendEvent: theEvent];
	  break;
	}

      default:	/* pass all other events to the event's window	*/
	{
	  NSWindow	*window = [theEvent window];

	  if (!theEvent)
	    NSDebugLLog(@"NSEvent", @"NSEvent is nil!\n");
	  if (type == NSMouseMoved)
	    NSDebugLLog(@"NSMotionEvent", @"Send move (%d) to window %@", 
			type, ((window != nil) ? [window description] 
			       : @"No window"));
	  else
	    NSDebugLLog(@"NSEvent", @"Send NSEvent type: %d to window %@", 
			type, ((window != nil) ? [window description] 
			       : @"No window"));
	  if (window)
	    [window sendEvent: theEvent];
	  else if (type == NSRightMouseDown)
	    [self rightMouseDown: theEvent];
	}
    }
}

- (NSEvent*) currentEvent
{
  return _current_event;
}

- (void) discardEventsMatchingMask: (unsigned int)mask
		       beforeEvent: (NSEvent *)lastEvent
{
  DPSDiscardEvents(GSCurrentServer(), mask, lastEvent);
}

- (NSEvent*) nextEventMatchingMask: (unsigned int)mask
			 untilDate: (NSDate*)expiration
			    inMode: (NSString*)mode
			   dequeue: (BOOL)flag
{
  NSEvent	*event;

  if (!expiration)
    expiration = [NSDate distantFuture];

  if (flag)
    event = DPSGetEvent(GSCurrentServer(), mask, expiration, mode);
  else
    event = DPSPeekEvent(GSCurrentServer(), mask, expiration, mode);

  if (event)
    {
IF_NO_GC(NSAssert([event retainCount] > 0, NSInternalInconsistencyException));
      /*
       * If we are not in a tracking loop, we may want to unhide a hidden
       * because the mouse has been moved.
       */
      if (mode != NSEventTrackingRunLoopMode)
	{
	  if ([NSCursor isHiddenUntilMouseMoves])
	    {
	      NSEventType type = [event type];

	      if ((type == NSLeftMouseDown) || (type == NSLeftMouseUp)
		|| (type == NSOtherMouseDown) || (type == NSOtherMouseUp)
		|| (type == NSRightMouseDown) || (type == NSRightMouseUp)
		|| (type == NSMouseMoved))
		{
		  [NSCursor unhide];
		}
	    }
	}

      ASSIGN(_current_event, event);
    }
  return event;
}

- (void) postEvent: (NSEvent *)event atStart: (BOOL)flag
{
  DPSPostEvent(GSCurrentServer(), event, flag);
}

/**
 * Sends the aSelector message to the receiver returned by the
 * -targetForAction:to:from: method (to which the aTarget and sender
 * arguments are passed).<br />
 * The method in the receiver must expect a single argument ...
 * the sender.<br />
 * Any value returned by the method in the receiver is ignored.<br />
 * This method returns YES on success, NO on failure (when no receiver
 * can be found for aSelector).
 */
- (BOOL) sendAction: (SEL)aSelector to: (id)aTarget from: (id)sender
{
  id resp = [self targetForAction: aSelector to: aTarget from: sender];

  if (resp != nil)
    {
      NSInvocation	*inv;
      NSMethodSignature	*sig;

      sig = [resp methodSignatureForSelector: aSelector];
      inv = [NSInvocation invocationWithMethodSignature: sig];
      [inv setSelector: aSelector];
      if ([sig numberOfArguments] > 2)
	{
	  [inv setArgument: &sender atIndex: 2];
	}
      [inv invokeWithTarget: resp];
      return YES;
    }

  return NO;
}

/**
 * If theTarget responds to theAction it is returned, otherwise
 * the application searches for an object which will handle
 * theAction and returns the first object found.<br />
 * Returns nil on failure.
 */
- (id) targetForAction: (SEL)theAction to: (id)theTarget from: (id)sender
{
  /*
   * If target responds to the selector then have it perform it.
   */
  if (theTarget && [theTarget respondsToSelector: theAction])
    {
      return theTarget;
    }
  else
    {
      return [self targetForAction: theAction];
    }
}

/** 
 * <p>
 *   Returns the target object that will respond to aSelector, if any. The
 *   method first checks if any of the key window's first responders, the
 *   key window or its delegate responds. Next it checks the main window in
 *   the same way. Finally it checks the receiver (NSApplication) and it's
 *   delegate.
 * </p>
 */
- (id) targetForAction: (SEL)aSelector
{
  NSWindow	*keyWindow;
  NSWindow	*mainWindow;
  id	resp;

  keyWindow = [self keyWindow];
  if (keyWindow != nil)
    {
      resp = [keyWindow firstResponder];
      while (resp != nil && resp != keyWindow)
	{
	  if ([resp respondsToSelector: aSelector])
	    {
	      return resp;
	    }
	  resp = [resp nextResponder];
	}
      if ([keyWindow respondsToSelector: aSelector])
	{
	  return keyWindow;
	}

      resp = [keyWindow delegate];
      if (resp != nil && [resp respondsToSelector: aSelector])
	{
	  return resp;
	}

      if ([NSDocumentController isDocumentBasedApplication])
	{
	  resp = [[NSDocumentController sharedDocumentController]
		   documentForWindow: keyWindow];
	  
	  if (resp != nil  && [resp respondsToSelector: aSelector])
	    {
	      return resp;
	    }
	}
    }

  if (_session != 0)
    return nil;

  mainWindow = [self mainWindow];
  if (keyWindow != mainWindow && mainWindow != nil)
    {
      resp = [mainWindow firstResponder];
      while (resp != nil && resp != mainWindow)
	{
	  if ([resp respondsToSelector: aSelector])
	    {
	      return resp;
	    }
	  resp = [resp nextResponder];
	}
      if ([mainWindow respondsToSelector: aSelector])
	{
	  return mainWindow;
	}
      resp = [mainWindow delegate];
      if (resp != nil && [resp respondsToSelector: aSelector])
	{
	  return resp;
	}
    }

  if ([self respondsToSelector: aSelector])
    {
      return self;
    }
  if (_delegate != nil && [_delegate respondsToSelector: aSelector])
    {
      return _delegate;
    }
  if ([NSDocumentController isDocumentBasedApplication]
    && [[NSDocumentController sharedDocumentController]
	   respondsToSelector: aSelector])
     {
      return [NSDocumentController sharedDocumentController];
    }
   
  return nil;
}

/**
 * Attempts to perform aSelector using [NSResponder-tryToPerform:with:]
 * and if that is not possible, attempts to get the application
 * delegate to perform the aSelector.<br />
 * Returns YES if an object was found to perform aSelector, NO otherwise.
 */
- (BOOL) tryToPerform: (SEL)aSelector with: (id)anObject
{
  if ([super tryToPerform: aSelector with: anObject] == YES)
    {
      return YES;
    }
  if (_delegate != nil && [_delegate respondsToSelector: aSelector])
    {
      NSInvocation	*inv;
      NSMethodSignature	*sig;

      sig = [_delegate methodSignatureForSelector: aSelector];
      inv = [NSInvocation invocationWithMethodSignature: sig];
      [inv setSelector: aSelector];
      if ([sig numberOfArguments] > 2)
	{
	  [inv setArgument: &anObject atIndex: 2];
	}
      [inv invokeWithTarget: _delegate];
      return YES;
    }
  return NO;
}

/*
Sets the application's icon. Any windows that use the old application
icon image as their mini window image will be updated to use the new
image.
*/
- (void) setApplicationIconImage: (NSImage*)anImage
{
  NSEnumerator	*iterator = [[self windows] objectEnumerator];
  NSWindow	*current;
  NSImage	*old_app_icon = _app_icon;

  RETAIN(old_app_icon);
  [_app_icon setName: nil];
  [anImage setName: @"NSApplicationIcon"];
  ASSIGN(_app_icon, anImage);

  if (_app_icon_window != nil)
    {
      [[_app_icon_window contentView] setImage: anImage];
    }

  // Swap the old image for the new one wherever it's used
  while ((current = [iterator nextObject]) != nil)
    {
      if ([current miniwindowImage] == old_app_icon)
	[current setMiniwindowImage: anImage];
    }

  DESTROY(old_app_icon);
}

- (NSImage*) applicationIconImage
{
  return _app_icon;
}

- (NSWindow*) iconWindow
{
  return _app_icon_window;
}

/*
 * Hiding and arranging windows
 */
- (void) hide: (id)sender
{
  if (_app_is_hidden == NO)
    {
      NSArray			*windows_list = [self windows]; 
      unsigned			count = [windows_list count];
      unsigned			i;

      [nc postNotificationName: NSApplicationWillHideNotification
			object: self];

      if ([self keyWindow] != nil)
	{
	  _hidden_key = [self keyWindow];
	  [_hidden_key resignKeyWindow];
	}
      for (i = 0; i < count; i++)
	{
	  NSWindow	*win = [windows_list objectAtIndex: i];

	  if ([win isVisible] == NO)
	    {
	      continue;		/* Already invisible	*/
	    }
	  if (win == _app_icon_window)
	    {
	      continue;		/* can't hide the app icon.	*/
	    }
	  if (_app_is_active == YES && [win hidesOnDeactivate] == YES)
	    {
	      continue;		/* Will be hidden by deactivation	*/
	    }
	  [_hidden addObject: win];
	  [win orderOut: self];
	}
      _app_is_hidden = YES;

      /*
       * On hiding we also deactivate the application which will make the menus
       * go away too.
       */
      [self deactivate];
      _unhide_on_activation = YES;

      [nc postNotificationName: NSApplicationDidHideNotification
			object: self];
    }
}

- (BOOL) isHidden
{
  return _app_is_hidden;
}

- (void) unhide: (id)sender
{
  if (_app_is_hidden)
    {
      [self unhideWithoutActivation];
      _unhide_on_activation = NO;
    }
  if (_app_is_active == NO)
    {
      /*
       * Activation should make the applications menus visible.
       */
      [self activateIgnoringOtherApps: YES];
    }
}

- (void) unhideWithoutActivation
{
  if (_app_is_hidden == YES)
    {
      unsigned			count;
      unsigned			i;

      [nc postNotificationName: NSApplicationWillUnhideNotification
			object: self];

      count = [_hidden count];
      for (i = 0; i < count; i++)
	{
	  [[_hidden objectAtIndex: i] orderFrontRegardless];
	}
      [_hidden removeAllObjects];
      if (_hidden_key != nil
	&& [[self windows] indexOfObjectIdenticalTo: _hidden_key] != NSNotFound)
	{
	  [_hidden_key makeKeyAndOrderFront: self];
	  _hidden_key = nil;
	}

      _app_is_hidden = NO;

      [nc postNotificationName: NSApplicationDidUnhideNotification
			object: self];
    }
}

- (void) arrangeInFront: (id)sender
{
  NSMenu	*menu;

  menu = [self windowsMenu];
  if (menu)
    {
      NSArray	*itemArray;
      unsigned	count;
      unsigned	i;

      itemArray = [menu itemArray];
      count = [itemArray count];
      for (i = 0; i < count; i++)
	{
	  id	win = [(NSMenuItem*)[itemArray objectAtIndex: i] target];

	  if ([win isKindOfClass: [NSWindow class]])
	    {
	      [win orderFront: sender];
	    }
	}
    }
}

/*
 * Managing windows
 */
- (NSWindow*) keyWindow
{
  return _key_window;
}

- (NSWindow*) mainWindow
{
  return _main_window;
}

- (NSWindow*) makeWindowsPerform: (SEL)aSelector inOrder: (BOOL)flag
{
  NSArray	*window_list = [self windows];
  unsigned	i;

  if (flag)
    {
      // FIXME This is not the order specified in the MacOSX spec
      unsigned	count = [window_list count];

      for (i = 0; i < count; i++)
	{
	  NSWindow *window = [window_list objectAtIndex: i];

	  if ([window performSelector: aSelector] != nil)
	    {
	      return window;
	    }
	}
    }
  else
    {
      i = [window_list count];
      while (i-- > 0)
	{
	  NSWindow *window = [window_list objectAtIndex: i];

	  if ([window performSelector: aSelector] != nil)
	    {
	      return window;
	    }
	}
    }
  return nil;
}

- (void) miniaturizeAll: sender
{
  NSArray *window_list = [self windows];
  unsigned i, count;

  for (i = 0, count = [window_list count]; i < count; i++)
    [[window_list objectAtIndex: i] miniaturize: sender];
}

- (void) preventWindowOrdering
{
  //TODO
}

- (void) setWindowsNeedUpdate: (BOOL)flag
{
  _windows_need_update = flag;
}

- (void) updateWindows
{
  NSArray		*window_list = [self windows];
  unsigned		count = [window_list count];
  unsigned		i;

  _windows_need_update = NO;
  [nc postNotificationName: NSApplicationWillUpdateNotification object: self];

  for (i = 0; i < count; i++)
    {
      NSWindow *win = [window_list objectAtIndex: i];
      if ([win isVisible])
	[win update];
    }
  [nc postNotificationName: NSApplicationDidUpdateNotification object: self];
}

- (NSArray*) windows
{
  return GSAllWindows();
}

- (NSWindow *) windowWithWindowNumber: (int)windowNum
{
  return GSWindowWithNumber(windowNum);
}

/*
 * Showing Standard Panels
 */
/* infoPanel, macosx API */
- (void) orderFrontStandardAboutPanel: sender
{
  [self orderFrontStandardAboutPanelWithOptions: nil];
}

- (void) orderFrontStandardAboutPanelWithOptions: (NSDictionary *)dictionary
{
  [self orderFrontStandardInfoPanelWithOptions: dictionary];
}

/* infoPanel, GNUstep API */
- (void) orderFrontStandardInfoPanel: sender
{
  [self orderFrontStandardInfoPanelWithOptions: nil];
}

- (void) orderFrontStandardInfoPanelWithOptions: (NSDictionary *)dictionary
{
  if (_infoPanel == nil)
    _infoPanel = [[GSInfoPanel alloc] initWithDictionary: dictionary];
  
  [_infoPanel setTitle: NSLocalizedString (@"Info", 
					   @"Title of the Info Panel")];
  [_infoPanel orderFront: self];
}

/*
 * Getting the main menu
 */
- (NSMenu*) mainMenu
{
  return _main_menu;
}

- (void) setMainMenu: (NSMenu*)aMenu
{
  if (_main_menu != nil && _main_menu != aMenu)
    {
      [_main_menu close];
      [[_main_menu window] setLevel: NSSubmenuWindowLevel];
    }

  ASSIGN(_main_menu, aMenu);

  // Set the title of the window.
  // This wont be displayed, but the window manager may need it.
  [[_main_menu window] setTitle: [[NSProcessInfo processInfo] processName]];
  [[_main_menu window] setLevel: NSMainMenuWindowLevel];
  [_main_menu setGeometry];
}

- (void) rightMouseDown: (NSEvent*)theEvent
{
  // On right mouse down display the main menu transient
  if (_main_menu != nil)
    [NSMenu popUpContextMenu: _main_menu
	    withEvent: theEvent
	    forView: nil];
  else
    [super rightMouseDown: theEvent];
}

- (void) setAppleMenu: (NSMenu*)aMenu
{
    //TODO: Unclear, what this should do.
}

/*
 * Managing the Windows menu
 */
- (void) addWindowsItem: (NSWindow*)aWindow
		  title: (NSString*)aString
	       filename: (BOOL)isFilename
{
  [self changeWindowsItem: aWindow  title: aString  filename: isFilename];
}

- (void) removeWindowsItem: (NSWindow*)aWindow
{
  if (_windows_menu)
    {
      NSArray	*itemArray;
      unsigned	count;

      itemArray = [_windows_menu itemArray];
      count = [itemArray count];
      while (count-- > 0)
	{
	  NSMenuItem *item = [itemArray objectAtIndex: count];

	  if ([item target] == aWindow)
	    {
	      [_windows_menu removeItemAtIndex: count];
	      return;
	    }
	}
    }
}

- (void) setImageForWindowsItem: (NSMenuItem *)item
{
  NSImage *oldImage = [item image];
  NSImage *newImage;

  if (!([[item target] styleMask] & NSClosableWindowMask))
    return;

  if ([[item target] isDocumentEdited])
    {
      newImage = [NSImage imageNamed: @"common_WMCloseBroken"];
    }
  else
    {
      newImage = [NSImage imageNamed: @"common_WMClose"];
    }

  if (newImage != oldImage)
    {
      [item setImage: newImage];
    }
}

- (void) changeWindowsItem: (NSWindow*)aWindow
		     title: (NSString*)aString
		  filename: (BOOL)isFilename
{
  NSArray	*itemArray;
  unsigned	count;
  unsigned	i;
  id		item;

  if (![aWindow isKindOfClass: [NSWindow class]])
    [NSException raise: NSInvalidArgumentException
		 format: @"Object of bad type passed as window"];

  if (isFilename)
    {
      NSRange	r = [aString rangeOfString: @"  --  "];

      if (r.length > 0)
	{
	  aString = [aString substringToIndex: r.location];
	}
    }

  /*
   * If there is no menu and nowhere to put one, we can't do anything.
   */
  if (_windows_menu == nil)
    return;

  /*
   * Check if the window is already in the menu.  
   */
  itemArray = [_windows_menu itemArray];
  count = [itemArray count];
  for (i = 0; i < count; i++)
    {
      NSMenuItem *item = [itemArray objectAtIndex: i];
      
      if ([item target] == aWindow)
	{
	  /*
	   * If our menu item already exists and with the correct
	   * title, we need not continue.  
	   */
	  if ([[item title] isEqualToString: aString])
	    {
	      return;
	    }
	  else
	    {
	      /* 
	       * Else, we need to remove the old item and add it again
	       * with the new title.  Then new item might be located
	       * somewhere else in the menu than the old one (because
	       * items in the menu are sorted by title) ... this is
	       * why we remove the old one and then insert it again.
	       */
	      [_windows_menu removeItem: item];
	      break;
	    }
	}
    }

  /*
   * Can't permit an untitled window in the window menu ... so if the 
   * window has not title, we don't add it to the menu.
   */
  if (aString == nil || [aString isEqualToString: @""])
    return;
  
  /*
   * Now we insert a menu item for the window in the correct order.
   * Make special allowance for menu entries to 'arrangeInFront: '
   * 'performMiniaturize: ' and 'performClose: '.  If these exist the
   * window entries should stay after the first one and before the
   * other two.
   */
  itemArray = [_windows_menu itemArray];
  count = [itemArray count];

  i = 0;
  if (count > 0 && sel_eq([[itemArray objectAtIndex: 0] action],
		@selector(arrangeInFront:)))
    i++;
  if (count > i && sel_eq([[itemArray objectAtIndex: count-1] action],
		@selector(performClose:)))
    count--;
  if (count > i && sel_eq([[itemArray objectAtIndex: count-1] action],
		@selector(performMiniaturize:)))
    count--;

  while (i < count)
    {
      item = [itemArray objectAtIndex: i];

      if ([[item title] compare: aString] == NSOrderedDescending)
	break;
      i++;
    }
  item = [_windows_menu insertItemWithTitle: aString
			action: @selector(makeKeyAndOrderFront:)
			keyEquivalent: @""
			atIndex: i];
  [item setTarget: aWindow];

  // When changing for a window with a file, we should also set the image.
  [self setImageForWindowsItem: item];
}

- (void) updateWindowsItem: (NSWindow*)aWindow
{
  NSMenu *menu;

  menu = [self windowsMenu];
  if (menu != nil)
    {
      NSArray	*itemArray;
      unsigned	count;
      unsigned	i;
      BOOL	found = NO;

      itemArray = [menu itemArray];
      count = [itemArray count];
      for (i = 0; i < count; i++)
	{
	  NSMenuItem *item = [itemArray objectAtIndex: i];

	  if ([item target] == aWindow)
	    {
	      [self setImageForWindowsItem: item];
	      break;
	    }
	}

      if (found == NO)
	{
	  NSString	*t = [aWindow title];
	  NSString	*f = [aWindow representedFilename];

	  [self changeWindowsItem: aWindow
			    title: t
			 filename: [t isEqual: f]];
	}
    }
}

- (void) setWindowsMenu: (NSMenu*)aMenu
{
  if (_windows_menu == aMenu)
    {
      return;
    }

  /*
   * Remove all the windows from the old windows menu.
   */
  if (_windows_menu != nil)
    {
      NSArray *itemArray = [_windows_menu itemArray];
      unsigned i, count = [itemArray count];
      
      for (i = 0; i < count; i++)
	{
	  NSMenuItem *anItem = [itemArray objectAtIndex: i];
	  id win = [anItem target];

	  if ([win isKindOfClass: [NSWindow class]])
	    {
	      [_windows_menu removeItem: anItem];
	    }
	}
    }

  /* Set the new _windows_menu.  */
  ASSIGN (_windows_menu, aMenu);
  
  {
    /*
     * Now use [-changeWindowsItem:title:filename:] to build the new menu.
     */
    NSArray * windows = [self windows];
    unsigned i, count = [windows count];
    for (i = 0; i < count; i++)
      {
	NSWindow	*win = [windows objectAtIndex: i];
	
	if ([win isExcludedFromWindowsMenu] == NO)
	  {
	    NSString	*t = [win title];
	    NSString	*f = [win representedFilename];
	    
	    [self changeWindowsItem: win
		  title: t
		  filename: [t isEqual: f]];
	  }
      }
  }
}

- (NSMenu*) windowsMenu
{
  return _windows_menu;
}

/*
 * Managing the Service menu
 */
- (void) registerServicesMenuSendTypes: (NSArray *)sendTypes
			   returnTypes: (NSArray *)returnTypes
{
  [_listener registerSendTypes: sendTypes
		  returnTypes: returnTypes];
}

- (NSMenu *) servicesMenu
{
  return [_listener servicesMenu];
}

/**
 * Returns the services provided previously registered using the
 * -setServicesProvider: method.
 */
- (id) servicesProvider
{
  return [_listener servicesProvider];
}

- (void) setServicesMenu: (NSMenu *)aMenu
{
  [_listener setServicesMenu: aMenu];
}

/**
 * Sets the object which provides services to other applications.<br />
 * Passing a nil value for anObject will result in the provision of
 * services to other applications by this application being disabled.<br />
 * See [NSPasteboard] for information about providing services.
 */
- (void) setServicesProvider: (id)anObject
{
  [_listener setServicesProvider: anObject];
}

- (id) validRequestorForSendType: (NSString *)sendType
		      returnType: (NSString *)returnType
{
  if (_delegate != nil && ![_delegate isKindOfClass: [NSResponder class]]
    && [_delegate respondsToSelector:
    @selector(validRequestorForSendType:returnType:)])
    return [_delegate validRequestorForSendType: sendType
				     returnType: returnType];

  return nil;
}

- (NSGraphicsContext *) context
{
  return _default_context;
}

- (void) reportException: (NSException *)anException
{
  if (anException)
    NSLog (_(@"reported exception - %@"), anException);
}

/*
 * Terminating the application
 */
- (void) terminate: (id)sender
{
  int	shouldTerminate = YES;

  if ([_delegate respondsToSelector: @selector(applicationShouldTerminate:)])
    {
      shouldTerminate = [_delegate applicationShouldTerminate: self];
    }
  else
    {
      shouldTerminate = [[NSDocumentController sharedDocumentController] 
			  reviewUnsavedDocumentsWithAlertTitle: _(@"Quit")
			   cancellable:YES];
    }

  if (shouldTerminate == NSTerminateNow)
    {
      [self replyToApplicationShouldTerminate: YES];
    }
}

- (void) replyToApplicationShouldTerminate: (BOOL)shouldTerminate
{
  if (shouldTerminate)
    {
      NSWorkspace *workspace = [NSWorkspace sharedWorkspace];

      [nc postNotificationName: NSApplicationWillTerminateNotification
	  object: self];
      
      _app_is_running = NO;

      [[self windows] makeObjectsPerformSelector: @selector(close)];
      
      /* Store our user information.  */
      [[NSUserDefaults standardUserDefaults] synchronize];

      /* Tell the Workspace that we really did terminate.  */
      [[workspace notificationCenter]
        postNotificationName: NSWorkspaceDidTerminateApplicationNotification
		      object: workspace
		    userInfo: [workspace activeApplication]];

      /* Destroy the main run loop pool (this also destroys any nested
	 pools which might have been created inside this one).  */
      DESTROY (_runLoopPool);

      /* Now free the NSApplication object.  Enclose the operation
	 into an autorelease pool, in case some -dealloc method needs
	 to use any temporary object.  */
      {
	NSAutoreleasePool *pool;
	
	IF_NO_GC(pool = [arpClass new]);

	DESTROY(NSApp);

	DESTROY(pool);
      }

      /* And finally, stop the program.  */
      exit(0);
    }
}

/**
 * Returns the applications delegate, as set by the -setDelegate: method.<br />
 * <p>The application delegate will automatically be sent various
 * notifications (as long as it implements the appropriate methods)
 * when application events occur.  The method to handle each of these
 * notifications has name mirroring the notification name, so for instance
 * an <em>NSApplicationDidBecomeActiveNotification</em> is handled by an
 * <code>applicationDidBecomeActive:</code> method.
 * </p> 
 * <list>
 *   <item>NSApplicationDidBecomeActiveNotification</item>
 *   <item>NSApplicationDidFinishLaunchingNotification</item>
 *   <item>NSApplicationDidHideNotification</item>
 *   <item>NSApplicationDidResignActiveNotification</item>
 *   <item>NSApplicationDidUnhideNotification</item>
 *   <item>NSApplicationDidUpdateNotification</item>
 *   <item>NSApplicationWillBecomeActiveNotification</item>
 *   <item>NSApplicationWillFinishLaunchingNotification</item>
 *   <item>NSApplicationWillHideNotification</item>
 *   <item>NSApplicationWillResignActiveNotification</item>
 *   <item>NSApplicationWillTerminateNotification</item>
 *   <item>NSApplicationWillUnhideNotification</item>
 *   <item>NSApplicationWillUpdateNotification</item>
 * </list>
 * <p>The delegate is also sent various messages to ask for authorisation
 * to perform actions, or to ask it to perform actions (again, as long
 * as it implements the appropriate methods).
 * </p>
 * <list>
 *   <item>applicationShouldTerminateAfterLastWindowClosed:</item>
 *   <item>applicationShouldOpenUntitledFile:</item>
 *   <item>applicationOpenUntitledFile:</item>
 *   <item>applicationShouldTerminate:</item>
 * </list>
 * <p>The delegate is also called upon to respond to any actions which
 *   are not handled by a window, a window delgate, or by the application
 *   object itsself..  This is controlled by the -targetForAction: method. 
 * </p>
 * <p>Finally, the application delegate is responsible for handling
 *   messages sent to the application from remote processes (see the
 *   section documenting distributed objects for [NSPasteboard]).
 * </p>
 */
- (id) delegate
{
  return _delegate;
}

/**
 * Sets the delegate of the application to anObject.<br />
 * <p><em>Beware</em>, this does not retain anObject, so you must be sure
 * that, in the event of anObject being deallocated, you
 * stop it being the application delagate by calling this
 * method again with another object (or nil) as the argument.
 * </p>
 */
- (void) setDelegate: (id)anObject
{
  if (_delegate)
    [nc removeObserver: _delegate name: nil object: self];
  _delegate = anObject;

#define SET_DELEGATE_NOTIFICATION(notif_name) \
  if ([_delegate respondsToSelector: @selector(application##notif_name:)]) \
    [nc addObserver: _delegate \
      selector: @selector(application##notif_name:) \
      name: NSApplication##notif_name##Notification object: self]

  SET_DELEGATE_NOTIFICATION(DidBecomeActive);
  SET_DELEGATE_NOTIFICATION(DidFinishLaunching);
  SET_DELEGATE_NOTIFICATION(DidHide);
  SET_DELEGATE_NOTIFICATION(DidResignActive);
  SET_DELEGATE_NOTIFICATION(DidUnhide);
  SET_DELEGATE_NOTIFICATION(DidUpdate);
  SET_DELEGATE_NOTIFICATION(WillBecomeActive);
  SET_DELEGATE_NOTIFICATION(WillFinishLaunching);
  SET_DELEGATE_NOTIFICATION(WillHide);
  SET_DELEGATE_NOTIFICATION(WillResignActive);
  SET_DELEGATE_NOTIFICATION(WillTerminate);
  SET_DELEGATE_NOTIFICATION(WillUnhide);
  SET_DELEGATE_NOTIFICATION(WillUpdate);
}

/*
 * Methods for scripting
 */
- (NSArray *) orderedDocuments
{
  // FIXME
  return nil;
}

- (NSArray *) orderedWindows
{
  // FIXME
  return [self windows];
}

/*
 * Methods for user attention requests
 */
- (void) cancelUserAttentionRequest: (int)request
{
  // FIXME
}

- (int) requestUserAttention: (NSRequestUserAttentionType)requestType
{
  // FIXME
  return 0;
}

/*
 * NSCoding protocol
 */
- (void) encodeWithCoder: (NSCoder*)aCoder
{
  [super encodeWithCoder: aCoder];

  [aCoder encodeConditionalObject: _delegate];
  [aCoder encodeObject: _main_menu];
  [aCoder encodeConditionalObject: _windows_menu];
}

- (id) initWithCoder: (NSCoder*)aDecoder
{
  id	obj;

  [super initWithCoder: aDecoder];

  obj = [aDecoder decodeObject];
  [self setDelegate: obj];
  obj = [aDecoder decodeObject];
  [self setMainMenu: obj];
  obj = [aDecoder decodeObject];
  [self setWindowsMenu: obj];
  return self;
}

@end /* NSApplication */


@implementation	NSApplication (Private)

- _appIconInit
{
  NSAppIconView	*iv;

  if (_app_icon == nil)
    {
      [self setApplicationIconImage: [NSImage imageNamed: @"GNUstep"]];
    }

  _app_icon_window = [[NSIconWindow alloc] initWithContentRect: 
					    NSMakeRect(0,0,64,64)
				styleMask: NSIconWindowMask
				  backing: NSBackingStoreRetained
				    defer: NO
				   screen: nil];

  iv = [[NSAppIconView alloc] initWithFrame: NSMakeRect(0,0,64,64)];
  [iv setImage: _app_icon];
  [_app_icon_window setContentView: iv];
  RELEASE(iv);

  [_app_icon_window orderFrontRegardless];
  return self;
}

- (void) _openDocument: (NSString*)filePath
{
  [_listener application: self openFile: filePath];
}

- (void) _windowDidBecomeKey: (NSNotification*) notification
{
  id	obj = [notification object];

  if (_key_window == nil && [obj isKindOfClass: [NSWindow class]])
    {
      _key_window = obj;
    }
  else
    {
      NSLog(@"Bogus attempt to set key window");
    }
}

- (void) _windowDidBecomeMain: (NSNotification*) notification
{
  id	obj = [notification object];

  if (_main_window == nil && [obj isKindOfClass: [NSWindow class]])
    {
      _main_window = obj;
    }
  else
    {
      NSLog(@"Bogus attempt to set main window");
    }
}

- (void) _windowDidResignKey: (NSNotification*) notification
{
  id	obj = [notification object];

  if (_key_window == obj)
    {
      _key_window = nil;
    }
  else
    {
      NSLog(@"Bogus attempt to resign key window");
    }
}

- (void) _windowDidResignMain: (NSNotification*) notification
{
  id	obj = [notification object];

  if (_main_window == obj)
    {
      _main_window = nil;
    }
  else
    {
      NSLog(@"Bogus attempt to resign key window");
    }
}

- (void) _windowWillClose: (NSNotification*) notification
{
  NSWindow		*win = [notification object];
  NSArray		*windows_list = [self windows];
  unsigned		count = [windows_list count];
  unsigned		i;
  NSMutableArray	*list = [NSMutableArray arrayWithCapacity: count];
  BOOL			wasKey = [win isKeyWindow];
  BOOL			wasMain = [win isMainWindow];

  for (i = 0; i < count; i++)
    {
      NSWindow	*tmp = [windows_list objectAtIndex: i];

      if ([tmp canBecomeMainWindow] == YES && [tmp isVisible] == YES)
	{
	  [list addObject: tmp];
	}
    }
  [list removeObjectIdenticalTo: win];
  count = [list count];
  
  /* If there's only one window left, and that's the one being closed, 
     then we ask the delegate if the app is to be terminated. */
  if (wasMain && count == 0 && _app_is_running)
    {
      if ([_delegate respondsToSelector:
	@selector(applicationShouldTerminateAfterLastWindowClosed:)])
	{
	  if ([_delegate applicationShouldTerminateAfterLastWindowClosed: self])
	    {
	      [self terminate: self];
	    }
	}
    }

  if (wasMain == YES)
    {
      [win resignMainWindow];
    }
  if (wasKey == YES)
    {
      [win resignKeyWindow];
    }

  if (_app_is_running)
    {
      /*
       * If we are not quitting, we may need to find a new key/main window.
       */
      if (wasKey == YES && [self keyWindow] == nil)
	{
	  win = [self mainWindow];
	  if (win != nil && [win canBecomeKeyWindow] == YES)
	    {
	      /*
	       * We have a main window that can become key, so do it.
	       */
	      [win makeKeyAndOrderFront: self];
	    }
	  else if (win != nil)
	    {
	      /*
	       * We have a main window that can't become key, so we just
	       * find a new window to make into our key window.
	       */
	      for (i = 0; i < count; i++)
		{
		  win = [list objectAtIndex: i];

		  if ([win canBecomeKeyWindow] == YES)
		    {
		      [win makeKeyAndOrderFront: self];
		    }
		}
	    }
	  else
	    {
	      /*
	       * Find a window that can be made key and main - and do it.
	       */
	      for (i = 0; i < count; i++)
		{
		  win = [list objectAtIndex: i];
		  if ([win canBecomeKeyWindow] && [win canBecomeMainWindow])
		    {
		      break;
		    }
		}
	      if (i < count)
		{
		  [win makeMainWindow];
		  [win makeKeyAndOrderFront: self];
		}
	      else
		{
		  /*
		   * No window we can use, so just find any candidate to
		   * be main window and another to be key window.
		   */
		  for (i = 0; i < count; i++)
		    {
		      win = [list objectAtIndex: i];
		      if ([win canBecomeMainWindow] == YES)
			{
			  [win makeMainWindow];
			  break;
			}
		    }
		  for (i = 0; i < count; i++)
		    {
		      win = [list objectAtIndex: i];
		      if ([win canBecomeKeyWindow] == YES)
			{
			  [win makeKeyAndOrderFront: self];
			  break;
			}
		    }
		}
	    }
	}
      else if ([self mainWindow] == nil)
	{
	  win = [self keyWindow];
	  if ([win canBecomeMainWindow] == YES)
	    {
	      [win makeMainWindow];
	    }
	  else
	    {
	      for (i = 0; i < count; i++)
		{
		  win = [list objectAtIndex: i];
		  if ([win canBecomeMainWindow] == YES)
		    {
		      [win makeMainWindow];
		      break;
		    }
		}
	    }
	}
    }
}

@end // NSApplication (Private)
