/*
 * OverlayWindow.h
 *
 * Copyright 2009 SwiftRing. All rights reserved.
 *
 * Description: 
 *    - Traps hotkeys and mouse events.
 *    - Brings up / down the main window.
 *    - Creates / destroys Ring objects.
 *    - Deals with application-wide configuration stuff.
 */              

#import <Cocoa/Cocoa.h>

@class RingView;
@class RecordingPanel;
@class RingFactory;

@interface OverlayWindow : NSWindow
{
	IBOutlet RingView *ringView;
	BOOL               inQuasimode;
	BOOL               didSomething;
	BOOL               didSomethingCount;
	BOOL               validKey;
	BOOL               isDisabled;
	int                ignoreKeyEvents;
	NSTimer           *pDisplayTimer;
	NSTimer           *pDismissTimer;

	IBOutlet NSMenu   *statusBarMenu;
	NSStatusItem      *statusBarItem;
	NSImage           *statusBarImage;
	NSImage           *statusBarHiImage;

	IBOutlet NSPanel        *preferencesPanel;
	IBOutlet RecordingPanel *recordingPanel;
	IBOutlet NSWindow       *aboutWindow;
	IBOutlet NSMenuItem     *runOnStartupMenuItem;
}

- (void) detectHit: (NSPoint) location: (BOOL) scrollUp: (BOOL) scrollDown: (unsigned int) arrowBitfield;
- (void) enterRingQuasimode;
- (void) exitRingQuasimode;
- (void) centerWindowOnMouse;
- (void) restartDisplayTimer: (bool) clearDisplay;
- (void) displayRing: (NSTimer*) timer;
- (void) fadeIn;
- (void) fadeOut;
- (void) trueCenter; 
- (bool) inQuasimode;
- (bool) didSomething;
- (void) setIgnoreKeyEvents: (int) value;
- (int)  getIgnoreKeyEvents;
- (bool) isDisabled;
- (bool) isRunOnStartup;
- (void) setLaunchKey: (int) newKey;
- (void) setAllowArrows: (BOOL) newAllowArrows;
- (void) setMenuDelay: (float) newDelay;
- (void) setEnableMenuBar: (BOOL) enable;
- (void) setValidKey: (BOOL) valid;

- (bool) isRecording;
- (void) processRecordingKeys: (CGEventRef) event ofType: (CGEventType) type;

- (void) toggleDisabled;
- (void) displayMessage: (NSString *) pMessageString;

- (IBAction) about:        (id)sender;
- (IBAction) aboutWebpage: (id)sender;
- (IBAction) help:         (id)sender;
- (IBAction) preferences:  (id)sender;
- (IBAction) disable:      (id)sender;
- (IBAction) runOnStartup: (id)sender;

@end
