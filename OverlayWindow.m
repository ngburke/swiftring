/*
 * OverlayWindow.m
 *
 * Copyright 2009 SwiftRing. All rights reserved.
 *
 * Description: 
 *    - Traps hotkeys and mouse events.
 *    - Brings up / down the main window.
 *    - Creates / destroys Ring objects.
 *    - Deals with application-wide configuration stuff.
 */              

#import "OverlayWindow.h"
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#import "RingView.h"
#import "Debug.h"
#import "RecordingPanel.h"
#import "RingFactory.h"
#import "Ring.h"

#define FADE_IN_TIMER  0.6
#define DISMISS_TIMER  0.01
#define SCROLL_QUIESCE 300

// A bunch of defines to handle hotkeys 
const UInt32 kMyHotKeyIdentifier = 'ring';
const UInt32 kMyHotKey = 50; //the ` key

EventHotKeyRef  gMyHotKeyRef;
EventHotKeyID   gMyHotKeyID;
EventHandlerUPP gAppHotKeyFunction;

// Event tap variables
CFRunLoopSourceRef gRunLoopSource;
CFMachPortRef      gEventTap;

// Global for use in the event tap callback (not a method of OverlayWindow)
OverlayWindow *gpOverlayWin;
BOOL           sentFake            = NO;
int            launchMethod        = 0;
BOOL           allowArrows         = NO;
float          menuDelay           = FADE_IN_TIMER;
unsigned int   arrowStickyBitfield = 0;
NSTimeInterval timeSinceLastScroll = 0;


// This routine is called when the command-return hotkey is pressed.
pascal OSStatus HotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData)
{
   [gpOverlayWin toggleDisabled];

   if ([gpOverlayWin isDisabled])
   {
      [gpOverlayWin displayMessage: @"SwiftRing is disabled."];
   }
   else
   {
      [gpOverlayWin displayMessage: @"SwiftRing is enabled."];
   }

   return noErr;
}

BOOL TapDidLaunchMenu(CGEventType type, CGEventRef event)
{
   switch (launchMethod)
   {
      case 0:
         return (kCGEventFlagsChanged == type) && 
                (kCGEventFlagMaskAlternate & CGEventGetFlags(event));
         break;
         
      case 1:
         return (kCGEventFlagsChanged == type) && 
                (kCGEventFlagMaskCommand & CGEventGetFlags(event));
         break;
         
      case 2:
         return (kCGEventFlagsChanged == type) && 
                (kCGEventFlagMaskControl & CGEventGetFlags(event));
         break;
         
      case 3:
         return (kCGEventFlagsChanged == type) && 
                (kCGEventFlagMaskSecondaryFn & CGEventGetFlags(event));         
         break;

      case 4:
         return (kCGEventOtherMouseDown == type);         
         break;
         
      case 5:
         return (kCGEventFlagsChanged == type) && 
                (kCGEventFlagMaskAlternate & CGEventGetFlags(event)) &&
                (kCGEventFlagMaskShift     & CGEventGetFlags(event));
         break;

      case 6:
         return (kCGEventFlagsChanged == type) && 
                (kCGEventFlagMaskCommand   & CGEventGetFlags(event)) &&
                (kCGEventFlagMaskShift     & CGEventGetFlags(event));
         break;

      case 7:
         return (kCGEventFlagsChanged == type) && 
                (kCGEventFlagMaskSecondaryFn & CGEventGetFlags(event)) &&
                (kCGEventFlagMaskShift       & CGEventGetFlags(event));
         break;

      case 8:
         return (kCGEventFlagsChanged == type) && 
                (kCGEventFlagMaskAlternate & CGEventGetFlags(event)) &&
                (kCGEventFlagMaskCommand   & CGEventGetFlags(event));
         break;

	   case 9:
		   return (kCGEventFlagsChanged == type) && 
				  (kCGEventFlagMaskControl   & CGEventGetFlags(event)) &&
		          (kCGEventFlagMaskAlternate & CGEventGetFlags(event));
		   break;
		   
   }
   
   return NO;
}


BOOL TapDidCloseMenu(CGEventType type, CGEventRef event)
{  
   switch (launchMethod)
   {
      case 0:
         return (kCGEventFlagsChanged == type) && 
                ((kCGEventFlagMaskAlternate & CGEventGetFlags(event)) == 0);
         break;
         
      case 1:
         return (kCGEventFlagsChanged == type) && 
                ((kCGEventFlagMaskCommand & CGEventGetFlags(event)) == 0);
         break;
         
      case 2:
         return (kCGEventFlagsChanged == type) && 
                ((kCGEventFlagMaskControl & CGEventGetFlags(event)) == 0);
         break;
         
      case 3:
         return (kCGEventFlagsChanged == type) && 
                ((kCGEventFlagMaskSecondaryFn & CGEventGetFlags(event)) == 0);
         break;
         
      case 4:
         return (kCGEventOtherMouseUp == type);         
         break;
         
      case 5:
         return (kCGEventFlagsChanged == type) && 
                (((kCGEventFlagMaskAlternate & CGEventGetFlags(event)) == 0 ) ||
                 ((kCGEventFlagMaskShift     & CGEventGetFlags(event)) == 0 ));
         break;

      case 6:
         return (kCGEventFlagsChanged == type) && 
                (((kCGEventFlagMaskCommand   & CGEventGetFlags(event)) == 0 ) ||
                 ((kCGEventFlagMaskShift     & CGEventGetFlags(event)) == 0 ));
         break;

      case 7:
         return (kCGEventFlagsChanged == type) && 
                (((kCGEventFlagMaskSecondaryFn & CGEventGetFlags(event)) == 0 ) ||
                 ((kCGEventFlagMaskShift       & CGEventGetFlags(event)) == 0 ));
         break;

      case 8:
         return (kCGEventFlagsChanged == type) && 
                (((kCGEventFlagMaskAlternate & CGEventGetFlags(event)) == 0 ) ||
                 ((kCGEventFlagMaskCommand   & CGEventGetFlags(event)) == 0 ));
         break;

	   case 9:
		   return (kCGEventFlagsChanged == type) && 
		          (((kCGEventFlagMaskControl  & CGEventGetFlags(event)) == 0 ) ||
			      ((kCGEventFlagMaskAlternate & CGEventGetFlags(event)) == 0 ));
		   break;
		   
   }     
   
   return NO;
}


CGEventRef TapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
   NSPoint    mouseLocation;
   //CGEventRef simMouseRef;
   BOOL       eatEvent = NO;
	
   DebugLog(@"Type = %i, Flags = %x ignore = %i", type, CGEventGetFlags(event), [gpOverlayWin getIgnoreKeyEvents]);
   
   // Check first for any disable events
   if (kCGEventTapDisabledByTimeout == type || 
       kCGEventTapDisabledByUserInput == type)
   {
		
      if (kCGEventTapDisabledByTimeout == type)
      {
         DebugLog(@"Got kCGEventTapDisabledByTimeout");
      }
      else
      {
         DebugLog(@"Got kCGEventTapDisabledByUserInput");
      }

      if (gEventTap)
      {
			if (!CGEventTapIsEnabled(gEventTap))
         {
				DebugLog(@"Re-enabling event tap");
				CGEventTapEnable(gEventTap, true);
			}
		}
	}

   // Disabled - do nothing, skip all handling
   if ([gpOverlayWin isDisabled])
   {

      DebugLog(@"Disabled, skipped processing");
   }
   // Need to ignore this event if it is a keyboard one
   else if ([gpOverlayWin getIgnoreKeyEvents])
   {
      if (kCGEventKeyUp        == type ||
          kCGEventKeyDown      == type ||
          kCGEventFlagsChanged == type)
      {         
         [gpOverlayWin setIgnoreKeyEvents: [gpOverlayWin getIgnoreKeyEvents] - 1];
         DebugLog(@"Ignored an action");
      }
   }
   /*
   else if (sentFake && (kCGEventRightMouseDown == type))
   {
      DebugLog(@"Skipping processing the fake mouse down event");
      sentFake = NO;
   }
   */
   // Not in Quasimode handling
   else if (![gpOverlayWin inQuasimode])
   {  
      if ([gpOverlayWin isRecording])
      {
         // Trying to record keystrokes from the recording panel
         if (kCGEventKeyUp        == type ||
             kCGEventKeyDown      == type ||
             kCGEventFlagsChanged == type)
         {
             // Ok, these are actual keys - pass them to the recording panel, but eat them so they aren't passed thru
            [gpOverlayWin processRecordingKeys: event ofType: type];
            eatEvent = YES;
         }
      }
      else if (TapDidLaunchMenu(type, event))
      {
         // If key goes down, enter quasimode and eat the event 
         //DebugLog(@"Right Mouse down, not in quasimode! sentFake = %i didSomething = %i", sentFake, [gpOverlayWin didSomething]);
         DebugLog(@"Key down, not in quasimode! ignoreEvents = %i didSomething = %i", [gpOverlayWin getIgnoreKeyEvents], 
                                                                                      [gpOverlayWin didSomething]);

         [gpOverlayWin enterRingQuasimode];
         arrowStickyBitfield = 0;
         timeSinceLastScroll = 0;
         
         //eatEvent = YES;
      }
   }
   // In Quasimode handling
   else
   {

      // Localize mouse location to this window
      mouseLocation = NSPointFromCGPoint(CGEventGetUnflippedLocation(event));
      mouseLocation.x -= [gpOverlayWin frame].origin.x;
      mouseLocation.y -= [gpOverlayWin frame].origin.y;

      if (TapDidCloseMenu(type, event))
      {
         DebugLog(@"Key up, in quasimode! ignoreEvents = %i didSomething = %i", [gpOverlayWin getIgnoreKeyEvents],
                                                                                [gpOverlayWin didSomething]);
         
         /*
         // If the user didn't do anything, simulate a normal right click and release
         if (![gpOverlayWin didSomething])
         {
            DebugLog(@"Sending Fake mouse down!");
            simMouseRef = CGEventCreateMouseEvent(NULL, kCGEventRightMouseDown, CGEventGetLocation(event), kCGMouseButtonRight);
            CGEventPost(kCGSessionEventTap, simMouseRef);
            CFRelease(simMouseRef);

            simMouseRef = CGEventCreateMouseEvent(NULL, kCGEventRightMouseUp, CGEventGetLocation(event), kCGMouseButtonRight);
            CGEventPost(kCGSessionEventTap, simMouseRef);
            CFRelease(simMouseRef);
            
            sentFake = YES;
            eatEvent = YES;
         }
         */
         
         [gpOverlayWin exitRingQuasimode];
      }
      else if (kCGEventKeyUp == type || kCGEventKeyDown == type)
      {
         unsigned short keyCode;

         keyCode = (unsigned short) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
         DebugLog(@"Key pressed: %i", keyCode);
         
         // Check for arrow keys
         if (allowArrows && (keyCode >= 123) && (keyCode <= 126))
         {
            if (kCGEventKeyUp == type)
            {
               // Send the sticky arrow bitfield off to detect for hits
               DebugLog(@"Sending the arrow bitfield: %x", arrowStickyBitfield);
               [gpOverlayWin detectHit: mouseLocation: NO: NO: arrowStickyBitfield];
               
               arrowStickyBitfield = 0;
            }
            else if (kCGEventKeyDown)
            {
               // Accumulate arrow combos into the bitfield
               arrowStickyBitfield |= 1 << (keyCode - 123);
            }
            
            eatEvent = YES;
         }
         else 
         {
            // If non-arrow keys are pressed while in quasi-mode, stall the menu display
            [gpOverlayWin restartDisplayTimer: YES];
         }
         
         
      }
      else if (kCGEventMouseMoved == type || kCGEventOtherMouseDragged == type)
      {
         [gpOverlayWin detectHit: mouseLocation: NO: NO: 0];

      }
      else if (kCGEventScrollWheel == type)
      {
         DebugLog(@"Scroll detected");
         
         if ((([NSDate timeIntervalSinceReferenceDate] * 1000) - timeSinceLastScroll) > SCROLL_QUIESCE)
         {
            timeSinceLastScroll = [NSDate timeIntervalSinceReferenceDate] * 1000;
            
            if (CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1) > 0)
            {
               // Mouse wheel scrolled up
               [gpOverlayWin detectHit: mouseLocation: YES: NO: 0];
            }
            else
            {
               // Mouse wheel scrolled down
               [gpOverlayWin detectHit: mouseLocation: NO: YES: 0];
            }
         }
         
         // Eat scroll wheel operations
         eatEvent = YES;
         
         //
         // All flags are normally cleared when executing actions - this would exit us
         // out of quasimode - we dont want this behavior for scroll operations!
         // 59 is the code for 'option' / 'alternate'
         //
         // CGEventRef event = CGEventCreateKeyboardEvent(0, 59, TRUE);
         // CGEventSetFlags(event, kCGEventFlagMaskAlternate);
         // CGEventPost(kCGSessionEventTap, event);
         // CFRelease(event);
      }
   }
   
   if (eatEvent)
   {
      return NULL;
   }
   
   return event;
}


@implementation OverlayWindow

// We override this initializer so we can set the NSBorderlessWindowMask styleMask, and set a few other important settings
- (id)initWithContentRect:(NSRect)contentRect styleMask:(unsigned int)styleMask backing:(NSBackingStoreType)backingType defer:(BOOL)flag
{

   if (self = [super initWithContentRect:contentRect styleMask:NSBorderlessWindowMask backing:backingType defer:flag]) 
   {
      [self setOpaque:NO]; // Needed so we can see through it when we have clear stuff on top
      [self setHasShadow: YES];
      [self setLevel:NSScreenSaverWindowLevel];          // Let's make it sit on top of everything else
      [self setBackgroundColor:[NSColor clearColor]]; // Only show the stuff on top, not the window itself
      [self setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
      [self setAlphaValue:0.0];
   }

   gpOverlayWin = self;

   return self;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
   // Show preferences if the app is run twice
	[self preferences: nil];
	
	DebugLog(@"Relaunch Detected!");
   return NO;
}

- (void)awakeFromNib
{
   CGEventMask eventMask;

   inQuasimode       = NO;
   isDisabled        = NO;
   ignoreKeyEvents   = 0;
   didSomethingCount = 0;

   //
   // Setup the hotkey handler, using Carbon APIs (there is no ObjC Cocoa HotKey API as of 10.2.x)
   //
   
   /*
   EventTypeSpec eventType;

   gAppHotKeyFunction   = NewEventHandlerUPP(HotKeyHandler);
   eventType.eventClass = kEventClassKeyboard;
   eventType.eventKind  = kEventHotKeyPressed;

   InstallApplicationEventHandler(gAppHotKeyFunction,1,&eventType,NULL,NULL);

   gMyHotKeyID.signature = kMyHotKeyIdentifier;
   gMyHotKeyID.id        = 1;

   RegisterEventHotKey(kMyHotKey, cmdKey, gMyHotKeyID, GetApplicationEventTarget(), 0, &gMyHotKeyRef);
   */
   
   //
   // Tap into mouse events.
   //

   // Create an event tap.
   eventMask = CGEventMaskBit(kCGEventOtherMouseDown)    |
               CGEventMaskBit(kCGEventOtherMouseUp)      |
               CGEventMaskBit(kCGEventOtherMouseDragged) |                     
               CGEventMaskBit(kCGEventMouseMoved)        |
               CGEventMaskBit(kCGEventScrollWheel)       |
               CGEventMaskBit(kCGEventFlagsChanged)      |
               CGEventMaskBit(kCGEventKeyDown)           |
               CGEventMaskBit(kCGEventKeyUp);
   
   DebugLog(@"Event before: %x", eventMask);
 
   gEventTap = CGEventTapCreate(/*kCGHIDEventTap*/kCGSessionEventTap, 
                                kCGHeadInsertEventTap, kCGEventTapOptionDefault, eventMask, TapCallback, self);

   DebugLog(@"Event after: %x", eventMask);
   
   if (!gEventTap) {
      fprintf(stderr, "Failed to create event tap\n");
      exit(1);
   }

   // Create a run loop source.
   gRunLoopSource = CFMachPortCreateRunLoopSource(/*kCFAllocatorDefault*/NULL, gEventTap, 0);

   //CFRelease(eventTap);

   // Add to the current run loop.
   CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], gRunLoopSource, kCFRunLoopCommonModes);

   // Enable the event tap.
   CGEventTapEnable(gEventTap, true);
   
   //CFRelease(runLoopSource);
}

// Windows created with NSBorderlessWindowMask normally can't be key, but we want ours to be
- (BOOL) canBecomeKeyWindow
{
   return YES;
}


- (void) dealloc
{
   [super dealloc];
}


- (void) detectHit:(NSPoint) location: (BOOL) scrollUp: (BOOL) scrollDown: (unsigned int) arrowBitfield
{
   RingActionStatus status;

   // Tell the Ring to do hit detection.
   status = [ringView detectHit: location: scrollUp: scrollDown: arrowBitfield: [self alphaValue] > 0];

   // If the hit was detected we want to mark didSomething true (sticky) and move the
   // window to the mouse location just in case this is a sub-menu
   if (status > RING_ACTION_NONE)
   {
      didSomething = YES;
	   
	   // If we're done, get out of quasimode
      if (RING_ACTION_DONE == status)
      {
         [self exitRingQuasimode];
      }
      // If we're not done, refresh the view and reset the display timer
      else if (RING_ACTION_REFRESH == status)
      {
         [self restartDisplayTimer: YES];
      }
      else if (RING_ACTION_STAY == status)
      {
         if (0 == [self alphaValue])
         {
            // Window is not visible, keep it that way
            [self restartDisplayTimer: YES];            
         }
      }

      [self centerWindowOnMouse];
   }
   else if ([self alphaValue] == 0)
   {
      // If not currently displaying anything, restart the display timer
      [self restartDisplayTimer: NO];
   }

   DebugLog(@"detectHit %f %f", location.x, location.y); 
}


// Need to pull up the Ring and make the window visible.
- (void)enterRingQuasimode
{
	if (didSomething)
	{
		didSomethingCount++;
		
		if ((NO == validKey) && (didSomethingCount >= 6))
		{
			[self displayMessage:@"Buy SwiftRing for only $5!"];
			didSomethingCount = 0;
			return;
		}
	}

   didSomething = NO;
   inQuasimode  = YES; 

   // Create a new ring
   [ringView createRing: NO];

   [self centerWindowOnMouse];

   // Invalidate any outstanding timers
   [pDisplayTimer invalidate];
   pDisplayTimer = nil;
   
   [pDismissTimer invalidate];
   pDismissTimer = nil;

   DebugLog(@"Making timer in enterRingQuasimode");

   pDisplayTimer = [NSTimer scheduledTimerWithTimeInterval:menuDelay
                                                    target:self
                                                  selector:@selector(displayRing:)
                                                  userInfo:nil
                                                   repeats:NO];
   
   // This is also done in dismissRing in case there was a display timer thread running already.
   [self setAlphaValue:0.0];
   
   DebugLog(@"enteredRingQuasimode %i", [self acceptsMouseMovedEvents]);
}


// Need to execute any outstanding actions, destroy the Ring and make the window invisible
- (void) exitRingQuasimode
{
   inQuasimode  = NO; 

   // Invalidate any outstanding timers
   [pDisplayTimer invalidate];
   pDisplayTimer = nil;

   [pDismissTimer invalidate];
   pDismissTimer = nil;
   
   DebugLog(@"Making timer in exitRingQuasimode");

   pDismissTimer = [NSTimer scheduledTimerWithTimeInterval:DISMISS_TIMER
                                                    target:self
                                                  selector:@selector(dismissRing:)
                                                  userInfo:nil
                                                   repeats:NO];
      
   // This is also done in dismissRing in case there was a display timer thread running already.
   [self setAlphaValue:0.0];

   DebugLog(@"exitRingQuasiMode %i", [self acceptsMouseMovedEvents]);
}


- (void) centerWindowOnMouse
{
   NSPoint windowLoc = [NSEvent mouseLocation];

   // Put the main window at the center of the mouse
   windowLoc.x -= [self frame].size.width / 2;
   windowLoc.y -= [self frame].size.height / 2;

   [self setFrameOrigin:windowLoc];
}


- (void) restartDisplayTimer: (bool) clearDisplay
{
   if (clearDisplay)
   {
      // First stop displaying
      [self setAlphaValue:0.0];
   }
   
   // Invalidate any outstanding timer
   [pDisplayTimer invalidate];
   pDisplayTimer = nil;
   
   DebugLog(@"Making timer in restartDisplayTimer");

   pDisplayTimer = [NSTimer scheduledTimerWithTimeInterval:menuDelay
                                                    target:self
                                                  selector:@selector(displayRing:)
                                                  userInfo:nil
                                                   repeats:NO];
}


- (void) displayRing: (NSTimer*) timer
{
   DebugLog(@"displayRing called");

   // Window is faded in after some time, start out invisible
   [self setAlphaValue:0.0];

   // Reset the timer pointer as it is no longer valid 
   pDisplayTimer = nil;

   [self fadeIn];

}


- (void) dismissRing: (NSTimer *) time
{
   DebugLog(@"dismissRing called");

   // Make the window invisible while the ring is destroyed to avoid artifacts
   [self setAlphaValue:0.0];
   
   // Reset the timer pointer as it is no longer valid 
   pDismissTimer = nil;
   
   // Destroy the ring
   [ringView destroyRing];
}


- (void) fadeIn
{
   // If user waited long enough for the window to pop up, they 'did something' 
   didSomething = YES;
   
   // Reset any segmet hits that may have happened before the ring became visible
   [ringView resetHits];
   
   [[self animator] setAlphaValue:1.0];
   [self centerWindowOnMouse];
}


- (void) fadeOut
{
   [[self animator] setAlphaValue:0.0];
}


- (void) trueCenter 
{
   NSRect frame   = [self frame];
   NSRect screen  = [[self screen] frame];
   frame.origin.x = (screen.size.width - frame.size. width) / 2;
   frame.origin.y = (screen.size.height - frame.size.height) / 2;
   [self setFrameOrigin: frame.origin];
}


- (bool) isRunOnStartup
{
   UInt32   seedValue;
   bool     isRunOnStartup = NO;
   CFURLRef            thePath    = (CFURLRef)[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
   LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
   
   // We're going to grab the contents of the shared file list (LSSharedFileListItemRef objects)
   // and pop it in an array so we can iterate through it to find our item.
   NSArray  *loginItemsArray = (NSArray *) LSSharedFileListCopySnapshot(loginItems, &seedValue);
   
   for (id item in loginItemsArray)
   {		
      LSSharedFileListItemRef itemRef = (LSSharedFileListItemRef)item;
      
      if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &thePath, NULL) == noErr)
      {
         if ([[(NSURL *)thePath path] hasPrefix:[[NSBundle mainBundle] bundlePath]])
         {
            isRunOnStartup = YES;
         }
      }
   }
   
   [loginItemsArray release];
   
   // Update the menuitem state
   if (isRunOnStartup)
   {
      [runOnStartupMenuItem setState: NSOnState];
   }
   else 
   {
      [runOnStartupMenuItem setState: NSOffState];
   }

   return isRunOnStartup;
}

- (void) setLaunchKey: (int) newKey
{
   static BOOL  startup   = YES;
   NSString    *keyString = NULL;
   
   launchMethod = newKey;
   
   switch (newKey)
   {
      case 0:
         keyString = [NSString stringWithFormat:@"         the 'Option' key."];
         break;
         
      case 1:
         keyString = [NSString stringWithFormat:@"       the 'Command' key."];
         break;
         
      case 2:
         keyString = [NSString stringWithFormat:@"        the 'Control' key."];
         break;
         
      case 3:
         keyString = [NSString stringWithFormat:@"        the 'Function' key."];
         break;
         
      case 4:
         keyString = [NSString stringWithFormat:@"   the 'other' Mouse button."];  
         break;

      case 5:
         keyString = [NSString stringWithFormat:@"   the 'Shift + Option' keys."];  
         break;
         
      case 6:
         keyString = [NSString stringWithFormat:@" the 'Shift + Command' keys."];  
         break;
         
      case 7:
         keyString = [NSString stringWithFormat:@"  the 'Shift + Function' keys."];  
         break;

      case 8:
         keyString = [NSString stringWithFormat:@"the 'Option + Command' keys."];  
         break;

	   case 9:
		   keyString = [NSString stringWithFormat:@" the 'Control + Option' keys."];  
		   break;
		   
   }
   
   //
   // Check if SwiftRing is launching automatically on startup
   //
   if (startup && ![self isRunOnStartup])
   {
      startup = NO;
      
      if (AXAPIEnabled()) 
      {
         // Not running on startup, show the welcome message
         [self displayMessage: [NSString stringWithFormat: @"To start SwiftRing hold down\n%@", keyString]];
      }
      else
      {
         [self displayMessage: @"               Welcome to SwiftRing!\nYou must enable access for assistive devices\n in System Preferences -> Universal Access."];
      }
   }   
}

- (void) setAllowArrows: (BOOL) newAllowArrows
{
   allowArrows = newAllowArrows;
}

- (void) setMenuDelay: (float) newDelay
{
	
	DebugLog(@"Menu Delay = %f", newDelay);
	
	menuDelay = newDelay;
}

- (void) setEnableMenuBar: (BOOL) enable
{
	DebugLog(@"Before: Enable %i, statusBarItem %i", enable, statusBarItem);

   if (enable)
   {
	   if (nil == statusBarItem)
	   {
		   //Create the NSStatusBar and set its length
		   statusBarItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
		   [statusBarItem retain];
		   
		   //Used to detect where our files are
		   NSBundle *bundle = [NSBundle mainBundle];

		   //Allocates and loads the images into the application which will be used for our NSStatusItem
		   statusBarImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"SwiftRingStatusIcon" ofType:@"png"]];
		   statusBarHiImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"SwiftRingStatusIcon" ofType:@"png"]];

		   //Sets the images in our NSStatusItem
		   [statusBarItem setImage:statusBarImage];
		   [statusBarItem setAlternateImage:statusBarHiImage];

		   //Tells the NSStatusItem what menu to load
		   [statusBarItem setMenu:statusBarMenu];

		   //Sets the tooptip for our item
		   [statusBarItem setToolTip:@"SwiftRing"];

		   //Enables highlighting
		   [statusBarItem setHighlightMode:YES];
	   }
   }
   else
   {
	   if (nil != statusBarItem)
	   {
		   // Nuke the menu icon
		   [[NSStatusBar systemStatusBar] removeStatusItem: statusBarItem];
	   
		   [statusBarItem release];
		   [statusBarImage release];
		   [statusBarHiImage release];

		   statusBarItem = nil;
		   statusBarImage = nil;
		   statusBarHiImage = nil;
	   }
   }

	DebugLog(@"After: Enable %i, statusBarItem %i", enable, statusBarItem);
}

- (void) setValidKey: (BOOL) valid
{
	DebugLog(@"Valid Key = %i", valid);
	
	validKey = valid;
}

// Returns value of inQuasimode
- (bool) inQuasimode
{
   return inQuasimode;
}


// Returns value of didSomething
- (bool) didSomething
{
   return didSomething;
}

// Sets ignoreEvents
- (void) setIgnoreKeyEvents: (int) value
{
   //DebugLog(@"Ignore: %i", value);
   ignoreKeyEvents = value;
}

// Returns value of ignoreEvents
- (int) getIgnoreKeyEvents
{
   return ignoreKeyEvents;
}

// Returns value of isDisabled
- (bool) isDisabled
{
   return isDisabled;
}


// Returns the recording panel's isRecording
- (bool) isRecording
{
   return [recordingPanel isRecording];
}


- (void) processRecordingKeys: (CGEventRef) event ofType: (CGEventType) type
{
   [recordingPanel processRecordingKeys: event ofType: type];
}


- (void) toggleDisabled
{
   isDisabled = ~isDisabled;
}


- (void) displayMessage: (NSString *) pMessageString
{
   [ringView displayMessage: pMessageString];
}


- (IBAction) about: (id)sender
{
   [NSApp activateIgnoringOtherApps:YES];
   [aboutWindow center];
   [aboutWindow makeKeyAndOrderFront: nil];
}


- (IBAction) aboutWebpage: (id)sender
{
   [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.swiftringapp.com"]];
}


- (IBAction) help: (id) sender
{
   [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.swiftringapp.com"]];
}


- (IBAction) preferences: (id)sender
{
   [NSApp activateIgnoringOtherApps:YES];
   [preferencesPanel center];
   [preferencesPanel makeKeyAndOrderFront: nil];
}

- (IBAction) disable: (id) sender
{
   [self toggleDisabled];
   
   if ([self isDisabled])
   {
      [sender setState: NSOnState];
      [gpOverlayWin displayMessage: @"SwiftRing is disabled."];
   }
   else
   {
      [sender setState: NSOffState];
      [gpOverlayWin displayMessage: @"SwiftRing is enabled."];
   }
   
}

- (IBAction) runOnStartup: (id) sender
{
   // Grab the bundle path
   CFURLRef thePath = (CFURLRef)[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
   
   // Create a reference to the shared file list.
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	
	if (loginItems)
   {
		if ([sender state] == NSOffState)
      {
         // Make the application run at startup.
         // We call LSSharedFileListInsertItemURL to insert the item at the bottom of Login Items list.
         LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemLast, 
                                                                      NULL, NULL, thePath, NULL, NULL);
         
         if (item)
         {
            CFRelease(item);
         }
         
         // Update the menuitem state
         [sender setState: NSOnState];
      }
		else
      {
         // Don't make the application run at startup.
        	UInt32 seedValue;
			
         // We're going to grab the contents of the shared file list (LSSharedFileListItemRef objects)
         // and pop it in an array so we can iterate through it to find our item.
         NSArray  *loginItemsArray = (NSArray *) LSSharedFileListCopySnapshot(loginItems, &seedValue);
         
         for (id item in loginItemsArray)
         {		
            LSSharedFileListItemRef itemRef = (LSSharedFileListItemRef)item;
            
            if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &thePath, NULL) == noErr)
            {
               if ([[(NSURL *)thePath path] hasPrefix:[[NSBundle mainBundle] bundlePath]])
               {
                  LSSharedFileListItemRemove(loginItems, itemRef); // Deleting the item
               }
            }
         }
         
         [loginItemsArray release];
         
         // Update the menuitem state
         [sender setState: NSOffState];
      }
	}
   
	CFRelease(loginItems);
}
@end
