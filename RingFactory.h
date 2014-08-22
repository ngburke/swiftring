//
//  RingFactory.h
//
//  Copyright 2009 SwiftRing. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class OverlayWindow;
@class RingView;
@class Ring;
@class RecordingPanel;


@interface RingFactory : NSObject 
{ 
   NSMutableDictionary    *pConfigLookup;
   NSMutableDictionary    *pAppLookup;
   NSMutableDictionary    *pPrefs;

   NSString               *pSupportDirectory;
   NSString               *pPreferencesDirectory;
   NSString               *pBundleDirectory;
   NSMutableArray         *pFileDeleteList;

   bool isSavedRingSelected;

   IBOutlet OverlayWindow  *overlayWindow;
   IBOutlet RingView       *previewRingView;
   
   NSMutableDictionary     *pPreviewRing;
   NSMutableDictionary     *pPreviewRingParent;
   bool                     previewRingIsSubring;

   IBOutlet NSOutlineView  *pSavedRingsOutline;
   IBOutlet NSButton       *pSavedRingsRemove;

   IBOutlet NSPopUpButton  *pLaunchKey;
   IBOutlet NSButton       *pAllowArrows;
   IBOutlet NSTextField    *pMenuDelayText;
   IBOutlet NSStepper      *pMenuDelay;
   IBOutlet NSButton       *pEnableMenuBar;

   IBOutlet NSTextField    *pApplicationsLabel;
   IBOutlet NSOutlineView  *pApplicationsOutline;
   NSMutableArray          *pApplicationsOutlineData;
   NSMutableIndexSet       *pApplicationsOutlineDataPreSelected;
   IBOutlet NSButton       *pApplicationsRefresh;

   IBOutlet NSTextField    *pSegmentsLabel;
   IBOutlet NSSlider       *pSegmentsSlider;

   IBOutlet NSTextField    *pSegmentSetupLabel;
   IBOutlet NSTableView    *pSegmentSetupTable;
   IBOutlet NSButton       *pSegmentSetupRecord;

   IBOutlet RecordingPanel   *recordingPanel;
   IBOutlet NSPanel          *preferencesPanel;

   IBOutlet NSButton       *regButton;
   IBOutlet NSPanel        *regPanel;
   IBOutlet NSTextField    *regKeyEntry;
   IBOutlet NSTextField    *regKeyStatus;
	
}

+ (NSString *) prettyNameForKeycode:   (NSString *) pKeyCode;
+ (NSString *) prettyPrintKeySequence: (NSString *) pKeySequence;
+ (NSString *) stringForKeyCode:       (unsigned short) keyCode withModifierFlags: (NSUInteger) modifierFlags;


- (Ring *) createRing: (float) centerX: (float) centerY: (bool) isPreview;

// Outline data source methods
- (int)  outlineView: (NSOutlineView *) outlineView numberOfChildrenOfItem: (id)item;
- (bool) outlineView: (NSOutlineView *) outlineView isItemExpandable: (id)item;
- (id)   outlineView: (NSOutlineView *) outlineView child: (int)index ofItem: (id)item;
- (id)   outlineView: (NSOutlineView *) outlineView objectValueForTableColumn: (NSTableColumn *)tableColumn byItem: (id)item;
- (void) outlineView: (NSOutlineView *) outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item;

// Outline delegate methods
- (void) outlineViewSelectionDidChange: (NSNotification *) aNotification;

// Table data source methods
- (NSInteger) numberOfRowsInTableView: (NSTableView *) aTableView;
- (id)   tableView: (NSTableView *) aTableView objectValueForTableColumn: (NSTableColumn *) aTableColumn 
                                                                     row: (NSInteger) rowIndex;
- (void) tableView: (NSTableView *) aTableView setObjectValue: (id) anObject
                                               forTableColumn: (NSTableColumn *) aTableColumn 
                                                          row: (NSInteger)rowIndex;


// Table delegate methods
- (void) tableViewSelectionDidChange: (NSNotification *) aNotification;

// Button actions
- (IBAction) addSavedRings:         (id) pSender;
- (IBAction) removeSavedRings:      (id) pSender;
- (IBAction) refreshApplications:   (id) pSender;
- (IBAction) movedSegmentsSlider:   (id) pSender;
- (IBAction) recordKeySequence:     (id) pSender;
- (IBAction) save:                  (id) pSender;
- (IBAction) cancel:                (id) pSender;
- (IBAction) setLaunchKey:          (id) pSender;
- (IBAction) setAllowArrows:        (id) pSender;
- (IBAction) setMenuDelay:          (id) pSender;
- (IBAction) setEnableMenuBar:      (id) pSender;

- (IBAction) regKeyEntryStart:      (id) pSender;
- (IBAction) regKeyEntryDone:       (id) pSender;

- (void)     recordKeySequenceDone: (NSString *) pRecordedKeys;

// Private helper methods
- (void)      reloadConfigs;
- (int)       numberOfSubrings: (id) item;
- (NSInteger) indexForKey: (NSString *) searchKey inDictionary: (NSDictionary *) dictionary;
- (void)      updateRingSettingsControls;
- (void)      disableRingSettingsControls;
- (bool)      updateApplicationsOutlineData;
- (NSMutableDictionary *) ringSettingsRowInfo: (NSInteger) rowIndex: (NSInteger *) pRowType;
- (bool)      isDefault;
- (void)      saveConfigs;
@end 
