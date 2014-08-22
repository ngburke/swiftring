//
//  RingFactory.m
//
//  Copyright 2009 SwiftRing. All rights reserved.
//

#import <Carbon/Carbon.h>
#import "RingFactory.h"
#import "RingView.h"
#import "Ring.h"
#import "Debug.h"
#import "RecordingPanel.h"
#import "OverlayWindow.h"

#define TAG_OUTLINE_SAVED_RINGS  0
#define TAG_OUTLINE_APPLICATIONS 1

#define SEGMENT_NORMAL      0
#define SEGMENT_SCROLL_UP   1
#define SEGMENT_SCROLL_DOWN 2
#define SEGMENT_INVALID     3

#define COLUMN_SEGMENT      0
#define COLUMN_LABEL        1
#define COLUMN_SUBRING      2
#define COLUMN_KEY_SEQUENCE 3

static NSDictionary *pPrettyNameLookup = nil;

// Utility functions

NSDecimalNumber* bigMod(NSDecimalNumber *dividend, NSDecimalNumber *divisor)
{
	NSDecimalNumber *quotient = [dividend decimalNumberByDividingBy: divisor withBehavior:
																[NSDecimalNumberHandler 
																decimalNumberHandlerWithRoundingMode:NSRoundDown 
																scale:0 
																raiseOnExactness:NO 
																raiseOnOverflow:NO 
																raiseOnUnderflow:NO 
																raiseOnDivideByZero:NO]];
	NSDecimalNumber *subtractAmount = [quotient decimalNumberByMultiplyingBy:divisor];
	NSDecimalNumber *remainder = [dividend decimalNumberBySubtracting:subtractAmount];

	return remainder;
}

BOOL validateKey(NSNumber *pMessage)
{
	unsigned long long exponent = 17;

	NSDecimalNumber *message  = [NSDecimalNumber decimalNumberWithDecimal: [pMessage decimalValue]];
	NSDecimalNumber *modulus  = [NSDecimalNumber decimalNumberWithString: @"191601096808489"];
	NSDecimalNumber *result   = [NSDecimalNumber decimalNumberWithString: @"1"];

	while (exponent > 0)
	{
		if (exponent & 1)
		{
			result = bigMod([result decimalNumberByMultiplyingBy: message], modulus);
		}
	
		exponent = exponent >> 1;
		
		message = bigMod([message decimalNumberByMultiplyingBy: message], modulus);
	}
	
	NSString *appVerString = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	NSNumber *appVer       = [NSNumber numberWithFloat:[appVerString floatValue]];
	unsigned int ver       = [appVer unsignedIntValue];
	
	unsigned long long plainKey = [[result stringValue] longLongValue];
	
	DebugLog(@"App Major Version: %i, PlainKey %llu", ver, plainKey);
	
	if (((plainKey >> 28) & 0xFF) == 0x5F)
	{
		// Passed the 0x5F prefix check
		
		if (((plainKey >> 20) & 0xFF) >= ver)
		{
			// Passed the version check, we have ourselves a valid key!	
			return YES;
		}
		else
		{
			DebugLog(@"Key version too old | key = v%i, version = v%i", ((plainKey >> 20) & 0xFF), ver);
		}
	}
	else
	{
		DebugLog(@"Invalid key");
	}
		
	return NO;
}

@implementation RingFactory

- (void)awakeFromNib
{
   BOOL isDir;
   
   pSupportDirectory = [[NSString alloc] initWithString:[[[NSHomeDirectory() 
                                                           stringByAppendingPathComponent:@"Library"]
                                                           stringByAppendingPathComponent:@"Application Support"]
                                                           stringByAppendingPathComponent:@"SwiftRing"]];
   pPreferencesDirectory = [[NSString alloc] initWithString:[[[[NSHomeDirectory() 
                                                               stringByAppendingPathComponent:@"Library"]
                                                               stringByAppendingPathComponent:@"Application Support"]
                                                               stringByAppendingPathComponent:@"SwiftRing"]
                                                               stringByAppendingPathComponent:@"Preferences"]];
   
   pBundleDirectory  = [[NSString alloc] initWithString:[[[NSBundle mainBundle] resourcePath] 
                                                           stringByAppendingPathComponent:@"Config Files"]];
   
   if (![[NSFileManager defaultManager] fileExistsAtPath: pSupportDirectory isDirectory: &isDir] || !isDir)
   {
      // The Application Support directory does not exist, create it and 
      // copy everything from the bundle into the Application Support directory first
      [[NSFileManager defaultManager] copyItemAtPath: pBundleDirectory 
                                              toPath: pSupportDirectory 
                                               error: NULL];
      
      DebugLog(@"Copied stuff into the support directory - Bundle: %@ Support: %@", pBundleDirectory, pSupportDirectory);
   }
      
   //
   // Initialize the config/application lookup tables, start w/ 100 entries 
   // (mutable dictionary adds more if needed)
   //
   pConfigLookup   = [[NSMutableDictionary alloc] initWithCapacity: 100];
   pAppLookup      = [[NSMutableDictionary alloc] initWithCapacity: 100];
   pPrefs          = [[NSMutableDictionary alloc] initWithCapacity: 10];
   pFileDeleteList          = [[NSMutableArray alloc] initWithCapacity: 10];
   pApplicationsOutlineData = [[NSMutableArray alloc] initWithCapacity: 20];
   pApplicationsOutlineDataPreSelected = [[NSMutableIndexSet alloc] init];
   
   // Load the config data from the XML files
   [self reloadConfigs];
}


- (void) reloadConfigs
{
   NSArray              *pConfigFiles;
   NSUInteger            numConfigFiles;
   NSUInteger            i;
   NSData               *pXml;
   NSMutableDictionary  *pDict;
   NSString             *pErrorDesc;
   NSPropertyListFormat  format;
   NSArray              *pApps;
   NSEnumerator         *pAppsEnum;
   NSString             *pAppName;
   BOOL                  isDir;
   BOOL					 validRegKey = NO;
   
   [pConfigLookup removeAllObjects];
   [pAppLookup removeAllObjects];   
   [pFileDeleteList removeAllObjects];

   pPreviewRingParent       = nil;
   pPreviewRing             = nil;
   previewRingIsSubring     = NO;
   isSavedRingSelected      = NO;
   
   // Grab the program wide preferences
   pDict       = NULL;
   pXml        = NULL;
   pErrorDesc  = NULL;
   
   
   // Grab the XML file into a data object
   pXml = [[NSFileManager defaultManager] contentsAtPath:[pPreferencesDirectory stringByAppendingPathComponent: 
                                                          @"Preferences.plist"]];
   
   // Convert it into a dictionary
   pDict = (NSMutableDictionary *)[NSPropertyListSerialization
                                   propertyListFromData:pXml
                                   mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                   format:&format
                                   errorDescription:&pErrorDesc];
   
   [pPrefs addEntriesFromDictionary: pDict];
   
   // Make sure everything went ok with the conversion
   if (NULL == pPrefs) 
   {
      DebugLog(@"%@", pErrorDesc);
      [pErrorDesc release];
   }
   else
   {
      NSNumber *launchKey     = [pPrefs objectForKey: @"LaunchKey"];
      NSNumber *menuDelay     = [pPrefs objectForKey: @"Delay"];
      NSNumber *allowArrows   = [pPrefs objectForKey: @"Arrows"];
      NSNumber *enableMenuBar = [pPrefs objectForKey: @"MenuBar"];
	  NSNumber *regKey        = [pPrefs objectForKey: @"RegKey"];
      
      if (allowArrows == nil)
      {
         allowArrows = [NSNumber numberWithInt:0];
      }

      if (enableMenuBar == nil)
      {
         enableMenuBar = [NSNumber numberWithInt:1];
      }
	   
	  if (regKey != nil)
	  {
	     // Validate the registration key
		 if (validateKey(regKey))
		 {
			 DebugLog(@"Valid registration key at boot!");
			 [regKeyStatus setStringValue: @"Full Version"];
             [regButton setEnabled: NO];
			 validRegKey = YES;
		 }
	  }
            
      DebugLog(@"LaunchKey = %i, Delay = %f, Arrows = %i, Menu Bar = %i", 
                                                           [launchKey intValue],
                                                           [menuDelay floatValue],
                                                           [allowArrows intValue],
                                                           [enableMenuBar intValue]);
      
      //DebugLog(@"%@",NSStringFromClass([[pPrefs objectForKey: @"Delay"] class]));
      
      [pLaunchKey selectItemWithTag:[launchKey integerValue]];
      [pAllowArrows setState: [allowArrows intValue] > 0 ? NSOnState:NSOffState];
      [pMenuDelay setFloatValue:[menuDelay floatValue]];
      [pMenuDelayText setFloatValue:[menuDelay floatValue]];
      [pEnableMenuBar setState:[enableMenuBar intValue] > 0 ? NSOnState:NSOffState];
      
      [overlayWindow setLaunchKey:[launchKey intValue]];
      [overlayWindow setAllowArrows:[allowArrows intValue] > 0 ? YES : NO];
      [overlayWindow setMenuDelay:[menuDelay floatValue]];
      [overlayWindow setEnableMenuBar:[enableMenuBar intValue] > 0 ? YES : NO];
	  [overlayWindow setValidKey: validRegKey];
   }
   
   // Enumerate all the items in the support directory
   pConfigFiles   = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: pSupportDirectory
                                                                        error: NULL];
   numConfigFiles = [pConfigFiles count];
   
   for (i = 0; i < numConfigFiles; i++)
   {
      DebugLog(@"%@", [pConfigFiles objectAtIndex: i]);
  
      [[NSFileManager defaultManager] fileExistsAtPath:[pSupportDirectory stringByAppendingPathComponent: 
                                                        [pConfigFiles objectAtIndex: i]] 
                                           isDirectory:&isDir];
      
      if (isDir)
      {
         // The file is a directory, skip it
         continue;
      }
      
      pDict       = NULL;
      pXml        = NULL;
      pErrorDesc  = NULL;
      
      // Grab the XML file into a data object
      pXml = [[NSFileManager defaultManager] contentsAtPath:[pSupportDirectory stringByAppendingPathComponent: 
                                                             [pConfigFiles objectAtIndex: i]]];
      
      // Convert it into a dictionary
      pDict = (NSMutableDictionary *)[NSPropertyListSerialization
                                      propertyListFromData:pXml
                                      mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                      format:&format
                                      errorDescription:&pErrorDesc];
      
      // Make sure everything went ok with the conversion
      if (NULL == pDict) 
      {
         DebugLog(@"%@", pErrorDesc);
         [pErrorDesc release];
         continue;
      }
      
      // Add an entry to the config lookup table, indexed by the 'Name' field
      [pConfigLookup setObject: pDict forKey: [pDict objectForKey: @"Name"]];
        
      // Add entries to the app lookup table, indexed by the 'Apps' field
      pApps = [[pDict objectForKey: @"Apps"] componentsSeparatedByString:@","];

      if (NULL == pApps)
      {
         DebugLog(@"awakeFromNib: Apps key not found!");
         continue;
      }
      
      pAppsEnum = [pApps objectEnumerator];
      
      // Loop through all the app names, adding them to the app lookup table
      while (pAppName = [pAppsEnum nextObject])
      {
         if ([pAppName localizedCaseInsensitiveCompare: @""] != NSOrderedSame)
         {      
            [pAppLookup setObject: pDict forKey: pAppName];
         }
      }
   }   
   
   // Print out the config lookup
   for (id key in pConfigLookup)
   {
      DebugLog(@"reload key: '%@' value: '%@'", key, [pConfigLookup objectForKey:key]);
   }
   
   // Print out the app lookup
   for (id key in pAppLookup)
   {
      DebugLog(@"reload key: '%@' value: '%@'", key, [pAppLookup objectForKey:key]);
   }

}


+ (void) initialize
{
   //
   // Create the keycode to pretty name lookup dictionary
   //

   pPrettyNameLookup = [[NSDictionary alloc] 
             initWithObjects: [NSArray arrayWithObjects:
                               @"return",
                               @"tab",
                               @"space",
                               @"delete",
                               @"esc",
                               @"command",  // right
                               @"command",
                               @"shift",
                               @"capsLock",
                               @"option",
                               @"control",
                               @"shift",    // right
                               @"option",   // right
                               @"control",  // right
                               @"fn",
                               @"F17",
                               @"volumeUp",
                               @"volumeDown",
                               @"mute",
                               @"F18",
                               @"F19",
                               @"F20",
                               @"F5",
                               @"F6",
                               @"F7",
                               @"F3",
                               @"F8",
                               @"F9",
                               @"F11",
                               @"F13",
                               @"F16",
                               @"F14",
                               @"F10",
                               @"F12",
                               @"F15",
                               @"help",
                               @"home",
                               @"pageUp",
                               @"forwardDelete",
                               @"F4",
                               @"end",
                               @"F2",
                               @"pageDown",
                               @"F1",
                               @"left",
                               @"right",
                               @"down",
                               @"up",
							   @"dim",
							   @"bright",
							   @"expose",
							   @"dashboard",
                               nil]
                     
                     forKeys: [NSArray arrayWithObjects:
                               @"36",
                               @"48",
                               @"49",
                               @"51",
                               @"53",
                               @"54",
                               @"55",
                               @"56",
                               @"57",
                               @"58",
                               @"59",
                               @"60",
                               @"61",
                               @"62",
                               @"63",
                               @"64",
                               @"72",
                               @"73",
                               @"74",
                               @"79",
                               @"80",
                               @"90",
                               @"96",
                               @"97",
                               @"98",
                               @"99",
                               @"100",
                               @"101",
                               @"103",
                               @"105",
                               @"106",
                               @"107",
                               @"109",
                               @"111",
                               @"113",
                               @"114",
                               @"115",
                               @"116",
                               @"117",
                               @"118",
                               @"119",
                               @"120",
                               @"121",
                               @"122",
                               @"123",
                               @"124",
                               @"125",
                               @"126",
							   @"145",
							   @"144",
							   @"160",
							   @"130",
                               nil] 
                     ];
   
}


+ (NSString *) prettyNameForKeycode: (NSString *) pKeyCode
{
   return (nil == pPrettyNameLookup) ? nil : [pPrettyNameLookup objectForKey: pKeyCode];
}


+ (NSString *) prettyPrintKeySequence: (NSString *) pKeySequence
{
   NSString        *pKeyCode;
   NSMutableString *pPrettyString = [[NSMutableString alloc] initWithCapacity: 30];
   NSEnumerator    *pKeyCodeEnum  = [[pKeySequence componentsSeparatedByString: @" "] objectEnumerator];
   
   // Loop through all the keycodes
   while ((pKeyCode = [pKeyCodeEnum nextObject]) && (NSOrderedSame != [pKeyCode compare: @""]))
   {
      
      // Keycodes and up/down indication are seperated by underscores
      NSArray *pKeyUpDownArray = [pKeyCode componentsSeparatedByString:@"_"];
      
      if ([[pKeyUpDownArray objectAtIndex: 1] boolValue])
      {
         // Only add the key downs to the pretty string
         [pPrettyString appendFormat: @"%@ ", [RingFactory stringForKeyCode: [[pKeyUpDownArray objectAtIndex: 0] integerValue] 
                                                          withModifierFlags: 0]];
      }
   }
   
   return pPrettyString;
}


+ (NSString *) stringForKeyCode: (unsigned short) keyCode withModifierFlags: (NSUInteger) modifierFlags
{
  	
	// Try to get a pretty name for special characters
	NSString *pPrettyName = nil;
   
	pPrettyName = [RingFactory prettyNameForKeycode:[NSString stringWithFormat:@"%i", keyCode]];
   
	if (pPrettyName != nil)
	{
		return NSLocalizedString(([NSString stringWithFormat:@"%@", pPrettyName, nil]), @"Friendly Key Name");
	}

	// Get the name the hard way now
	TISInputSourceRef currentKeyboard = TISCopyCurrentKeyboardInputSource();
	
	if (!currentKeyboard)
	{
		return NSLocalizedString(([NSString stringWithFormat:@"?", nil]), @"Friendly Key Name");
	}
	
	CFDataRef uchr = (CFDataRef)TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData);
	CFRelease(currentKeyboard);	
	
	// For non-unicode layouts such as Chinese, Japanese, and Korean, get the ASCII capable layout	
	if (!uchr) 
	{
		currentKeyboard = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
		uchr = (CFDataRef)TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData);
		CFRelease(currentKeyboard);
	}	
	
	if (!uchr)
	{
		return NSLocalizedString(([NSString stringWithFormat:@"?", nil]), @"Friendly Key Name");
	}		
	
	const UCKeyboardLayout *keyboardLayout = (const UCKeyboardLayout*)CFDataGetBytePtr(uchr);
	
	if (keyboardLayout)
	{
		UInt32 deadKeyState = 0;
		UniCharCount maxStringLength = 255;
		UniCharCount actualStringLength = 0;
		UniChar unicodeString[maxStringLength];
		
		OSStatus status = UCKeyTranslate(keyboardLayout,
										 keyCode, kUCKeyActionDown, modifierFlags,
										 LMGetKbdType(), 0,
										 &deadKeyState,
										 maxStringLength,
										 &actualStringLength, unicodeString);
		
		if (actualStringLength == 0 && deadKeyState)
		{
			status = UCKeyTranslate(keyboardLayout,
									kVK_Space, kUCKeyActionDown, 0,
									LMGetKbdType(), 0,
									&deadKeyState,
									maxStringLength,
									&actualStringLength, unicodeString);   
		}
		if (actualStringLength > 0 && status == noErr)
		{
			return [NSString stringWithCharacters:unicodeString length:(NSUInteger)actualStringLength];
		}
	}
	
	/*
	TISInputSourceRef       currentKeyboard = TISCopyCurrentKeyboardInputSource();
	CFDataRef               uchr = (CFDataRef)TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData);
	const UCKeyboardLayout *keyboardLayout = (const UCKeyboardLayout*) CFDataGetBytePtr(uchr);
	
	else if (keyboardLayout)
	{
		UInt32       deadKeyState;
		UniCharCount maxStringLength = 255;
		UniCharCount actualStringLength;
		UniChar      unicodeString[maxStringLength];
		
		OSStatus status = UCKeyTranslate(keyboardLayout,
										 keyCode, kUCKeyActionDown, modifierFlags,
										 CGEventSourceGetKeyboardType((CGEventSourceRef)currentKeyboard), 0,
										 &deadKeyState,
										 maxStringLength,
										 &actualStringLength, unicodeString);
		
		if(status != noErr)
		{
			DebugLog(@"There was an %s error translating from the '%d' key code to a human readable string: %s",
					 GetMacOSStatusErrorString(status), status, GetMacOSStatusCommentString(status));
		}
		else if(actualStringLength > 0)
		{
			return [NSString stringWithCharacters: unicodeString length: (NSInteger) actualStringLength];
		} 
		else
		{
			DebugLog(@"Couldn't find a translation for the '%d' key code", keyCode);
		}
	} 
	else
	{
		DebugLog(@"Couldn't find a suitable keyboard layout from which to translate");
	}
	*/
	
	
	// Default name is just a question mark
    return NSLocalizedString(([NSString stringWithFormat:@"?", nil]), @"Friendly Key Name");
}


- (Ring *) createRing: (float) centerX: (float) centerY: (bool) isPreview
{
   NSDictionary *pActiveApp = nil;
   NSDictionary *pRingInfo  = nil;

   if (isPreview)
   {
      pRingInfo = pPreviewRing; 
   }
   else
   {
      // Figure out what the currently focused app is, and create a ring for that app
      pActiveApp = [[NSWorkspace sharedWorkspace] activeApplication];
   
      for (id key in pActiveApp)
      {
         DebugLog(@"key: '%@' value: '%@'", key, [pActiveApp objectForKey:key]);
      }

      pRingInfo = [pAppLookup objectForKey: [pActiveApp objectForKey:@"NSApplicationName"]];

      // Use the default if no app was found
      if (nil == pRingInfo)
      {
         pRingInfo = [pAppLookup objectForKey:@"Default"];
      }
   }

   if (pRingInfo == nil)
   {
      return nil;
   }

   return [[Ring alloc] init: pRingInfo: centerX: centerY];
}


// Outline data source methods

- (int) outlineView: (NSOutlineView *) outlineView numberOfChildrenOfItem: (id) item
{
   DebugLog(@"numberOfChildrenOfItem");

   switch ([outlineView tag])
   {
      // Saved Rings outline data
      case TAG_OUTLINE_SAVED_RINGS:
         if (nil == item)
         {
            return [pConfigLookup count];
         }

         return [self numberOfSubrings: item];

         break;

      // Applications outline data
      case TAG_OUTLINE_APPLICATIONS:
         if (nil == item && isSavedRingSelected)
         {
            return [pApplicationsOutlineData count]; 
         }

         return 0;

         break;

      default:
         return 0;
         break;
   }
}


- (bool) outlineView: (NSOutlineView *) outlineView isItemExpandable: (id) item
{
   DebugLog(@"isItemExpandable %@ %i", outlineView, [outlineView tag]);

   switch ([outlineView tag])
   {
      // Saved Rings outline data
      case TAG_OUTLINE_SAVED_RINGS:

         if (nil == item)
         {
            return NO;
         }

         return [self numberOfSubrings: item] > 0 ? YES: NO;
         break;

      // Applications outline data
      case TAG_OUTLINE_APPLICATIONS:
         return NO;
         break;
      
      default:
         return NO;
         break;
   }
}

- (id) outlineView: (NSOutlineView *) outlineView child: (int) index ofItem: (id) item
{
   int i = 0;

   switch ([outlineView tag])
   {
      // Saved Rings outline data
      case TAG_OUTLINE_SAVED_RINGS:
         if (nil == item)
         {
            return [pConfigLookup objectForKey: [[pConfigLookup allKeys] objectAtIndex: index]];
         }

         for (id key in item)
         {
            // Step through all the objects in this ring configuration and see if there are subrings
            if ([[item objectForKey: key] isKindOfClass: [NSDictionary class]] &&
                  [[item objectForKey: key] objectForKey: @"Submenu"])
            {
               if (i == index)
               {
                  return [item objectForKey: key];
               }
               i++;
            }
         }

         return nil;
         break;

      // Applications outline data
      case TAG_OUTLINE_APPLICATIONS:
         return [pApplicationsOutlineData objectAtIndex: index];
         break;
      
      default:
         return nil;
         break;
   }

}

- (id) outlineView: (NSOutlineView *) outlineView objectValueForTableColumn: (NSTableColumn *) tableColumn byItem: (id) item
{

   switch ([outlineView tag])
   {
      // Saved Rings outline data
      case TAG_OUTLINE_SAVED_RINGS:
         if ([item objectForKey: @"Name"] != nil)
         {
            // If the item has a name tag, then it is a top level item, use the name
            return [item objectForKey: @"Name"];
         }

         return [item objectForKey: @"Label"];
         break;

      // Applications outline data
      case TAG_OUTLINE_APPLICATIONS:
         return item;
         break;
      
      default:
         return nil;
         break;
   }

}


- (void) outlineView: (NSOutlineView *) outlineView setObjectValue: (id) object 
                                                    forTableColumn: (NSTableColumn *) tableColumn 
                                                            byItem: (id) item
{
   switch ([outlineView tag])
   {
      // Saved Rings outline data
      case TAG_OUTLINE_SAVED_RINGS:
         
         if ([item objectForKey: @"Submenu"] != nil)
         {
            // This is a sub-menu, update the item's label
            [item setObject: object forKey: @"Label"];
         }
         else
         {
            // This is a main menu

            if ([object caseInsensitiveCompare: [item objectForKey: @"Name"]] == NSOrderedSame ||
                [[item objectForKey: @"Name"] caseInsensitiveCompare: @"Default"] == NSOrderedSame)
            {
               // Don't do anything, the name didnt change, or it was default
            }
            else
            {
               
               // Put the old name in the file delete list
               if ([[NSFileManager defaultManager] fileExistsAtPath: 
                    [NSString stringWithFormat:@"%@/%@.plist", pSupportDirectory, [item objectForKey: @"Name"]]])
               {
                  [pFileDeleteList addObject: 
                   [NSString stringWithFormat:@"%@/%@.plist", pSupportDirectory, [item objectForKey: @"Name"]]];
               }
               
               // Add new name to the config lookup dictionary
               [pConfigLookup setObject: item forKey: object];
               
               // Remove old name from the config lookup dictionary
               [pConfigLookup removeObjectForKey: [item objectForKey:@"Name"]];
               
               // Update the item's name
               [item setObject: object forKey: @"Name"];
               
               
               // Select the newly renamed ring
               //[pSavedRingsOutline selectRowIndexes: [NSIndexSet indexSetWithIndex: [self indexForKey: object
               //                                                                          inDictionary: pConfigLookup]] 
               //                byExtendingSelection: NO];
               
            }
         }

         // Tell the saved rings outline to refresh from the root
         [pSavedRingsOutline reloadItem: nil reloadChildren: YES];
         
         // Select the newly renamed ring
         [pSavedRingsOutline selectRowIndexes: [NSIndexSet indexSetWithIndex: [self indexForKey: object
                                                                                   inDictionary: pConfigLookup]] 
                         byExtendingSelection: NO];
                  
         break;
         
      // Applications outline data
      case TAG_OUTLINE_APPLICATIONS:
      default:
         break;
   }   
}


// Outline delegate methods

- (void) outlineViewSelectionDidChange: (NSNotification *) aNotification
{
   NSEnumerator    *pAppsEnum;
   NSUInteger       i;
   NSIndexSet      *pSelectedRows;
   NSString        *pAppName;
   NSString        *pNewAppName;
   NSMutableString *pNewAppList = [NSMutableString stringWithCapacity: 40];

   DebugLog(@"outlineViewSelectionDidChange");

   switch ([[aNotification object] tag])
   {
      // Saved Rings outline data
      case TAG_OUTLINE_SAVED_RINGS:

         if ([[aNotification object] selectedRow] >= 0)
         {
            isSavedRingSelected = YES;
            pPreviewRing = [[aNotification object] itemAtRow: [[aNotification object] selectedRow]];

            // See if this is a subring
            if ([pPreviewRing objectForKey: @"Submenu"] != nil)
            {
               pPreviewRingParent   = pPreviewRing;
               pPreviewRing         = [pPreviewRing objectForKey: @"Submenu"];
               previewRingIsSubring = YES;

               [pSavedRingsRemove setEnabled: YES];

               // Hide the subring selection column
               [[pSegmentSetupTable tableColumnWithIdentifier: [NSString stringWithFormat: @"%i", COLUMN_SUBRING]] setHidden: YES];
            }
            else
            {
               pPreviewRingParent   = nil;
               previewRingIsSubring = NO;

               // See if this is the default ring, and if so don't allow its removal
               if ([self isDefault])
               {
                  [pSavedRingsRemove setEnabled: NO];
               }
               else 
               {
                  [pSavedRingsRemove setEnabled: YES];
               }

               // Display the subring selection column
               [[pSegmentSetupTable tableColumnWithIdentifier: [NSString stringWithFormat: @"%i", COLUMN_SUBRING]] setHidden: NO];
            }

            // Create a new ring preview
            [previewRingView destroyRing];
            [previewRingView createRing: YES];

            // Enable/Refresh all the Ring Settings controls
            [self updateRingSettingsControls];
         }
         else
         {
            isSavedRingSelected  = NO;
            pPreviewRingParent   = nil;
            pPreviewRing         = nil;
            previewRingIsSubring = NO;

            [pSavedRingsRemove setEnabled: NO];

            // Destroy the ring preview
            [previewRingView destroyRing];

            // Disable all the Ring Settings controls
            [self disableRingSettingsControls];
         }
         break;

      // Applications outline data
      case TAG_OUTLINE_APPLICATIONS:

         // Loop through all the old app names, removing them from the app lookup table
         pAppsEnum = [[[pPreviewRing objectForKey: @"Apps"] componentsSeparatedByString:@","] objectEnumerator];

         // Loop through all the app names, removing them from the app lookup table
         while (pAppName = [pAppsEnum nextObject])
         {
            [pAppLookup removeObjectForKey: pAppName];
         }

         // Loop through all the selected rows and build the new application list, adding it to the lookup table as well
         pSelectedRows = [[aNotification object] selectedRowIndexes];
         i             = [pSelectedRows firstIndex];

         while (i != NSNotFound)
         {
            pNewAppName = [[aNotification object] itemAtRow: i];
            [pAppLookup setObject: pPreviewRing forKey: pNewAppName];
            [pNewAppList appendFormat: @"%@,", pNewAppName];

            i = [pSelectedRows indexGreaterThanIndex: i];
         }

         // Now change the rings app list
         [pPreviewRing setObject: pNewAppList forKey: @"Apps"];
         break;
   }
}


// Table data source methods

- (NSInteger) numberOfRowsInTableView: (NSTableView *) aTableView
{
   NSInteger value = 0;

   if (isSavedRingSelected)
   {
      return [[pPreviewRing objectForKey: @"TotalSegments"] integerValue];
   }

   return value;
}


- (id) tableView: (NSTableView *) aTableView objectValueForTableColumn: (NSTableColumn *) aTableColumn row: (NSInteger) rowIndex
{
   int            tableColumn;
   NSInteger      segmentType;
   NSDictionary  *pSegmentInfo;

   // Convert the tag string to a number for ease of use
   tableColumn = [[aTableColumn identifier] intValue]; 
  
   // Figure out segment info for this row
   pSegmentInfo = [self ringSettingsRowInfo: rowIndex: &segmentType];

   if (pSegmentInfo == nil)
   {
      return nil;
   }

   // Return the appropriate information for this column
   switch (tableColumn)
   {
      case COLUMN_SEGMENT:
         
         switch (segmentType)
         {
            case SEGMENT_NORMAL:
               return [NSNumber numberWithInteger: rowIndex + 1];
               break;

            case SEGMENT_SCROLL_UP:
               return [NSString stringWithString: @"Scroll Up"];
               break;

            case SEGMENT_SCROLL_DOWN:
               return [NSString stringWithString: @"Scroll Down"];
               break;
         }
         break;

      case COLUMN_LABEL:
         return [pSegmentInfo objectForKey: @"Label"];
         break;

      case COLUMN_SUBRING:

         switch (segmentType)
         {
            case SEGMENT_NORMAL:
               [[aTableColumn dataCellForRow: rowIndex] setEnabled: YES];
               [[aTableColumn dataCellForRow: rowIndex] setTransparent: NO];
               return [NSNumber numberWithInteger: [pSegmentInfo objectForKey: @"Submenu"] == nil ? NSOffState: NSOnState];
               break;

            case SEGMENT_SCROLL_UP:
            case SEGMENT_SCROLL_DOWN:
               [[aTableColumn dataCellForRow: rowIndex] setEnabled: NO];
               [[aTableColumn dataCellForRow: rowIndex] setTransparent: YES];
               return [NSNumber numberWithInteger: NSOffState];
               break;
         }
         break;

      case COLUMN_KEY_SEQUENCE:
         return [RingFactory prettyPrintKeySequence: [pSegmentInfo objectForKey: @"Keys"]];
         break;
   }

   return nil;
}


- (NSString *) tableView: (NSTableView *)aTableView toolTipForCell: (NSCell *) aCell 
                                                              rect: (NSRectPointer) rect
                                                       tableColumn: (NSTableColumn *) aTableColumn
                                                               row: (int) row 
                                                     mouseLocation: (NSPoint) mouseLocation
{
   NSInteger      segmentType;
   NSDictionary  *pSegmentInfo;
   
   // Figure out segment info for this row
   pSegmentInfo = [self ringSettingsRowInfo: row: &segmentType];
   
   if (COLUMN_KEY_SEQUENCE == [[aTableColumn identifier] intValue])
   {
      return [RingFactory prettyPrintKeySequence: [pSegmentInfo objectForKey: @"Keys"]];
   }
   
   return nil;
}


- (void) tableView: (NSTableView *) aTableView setObjectValue: (id) anObject
                                               forTableColumn: (NSTableColumn *) aTableColumn 
                                                          row: (NSInteger) rowIndex
{
   NSInteger            tableColumn;
   NSInteger            segmentType;
   NSMutableDictionary *pSegmentInfo;

   // Convert the tag string to a number for ease of use
   tableColumn = [[aTableColumn identifier] integerValue]; 
  
   // Figure out segment info for this row
   pSegmentInfo = [self ringSettingsRowInfo: rowIndex: &segmentType];

   if (pSegmentInfo == nil)
   {
      return;
   }

   // Edit the data for this column / row
   switch (tableColumn)
   {
      case COLUMN_LABEL:
         [pSegmentInfo setObject: anObject forKey: @"Label"];
         break;

      case COLUMN_SUBRING:

         if ([anObject integerValue] == NSOnState)
         {
            // Make this a new subring
            [pSegmentInfo setObject: 
               [NSMutableDictionary 
                 dictionaryWithObjects: [NSArray arrayWithObjects: @"4",
                                                                   @"2",
                                          [NSMutableDictionary dictionaryWithObjects:
                                             [NSArray arrayWithObjects: @"",
                                                                        @"New",
                                                                        nil]
                                                               forKeys:
                                             [NSArray arrayWithObjects: @"Keys",
                                                                        @"Label",
                                                                        nil]],
                                          [NSMutableDictionary dictionaryWithObjects:
                                             [NSArray arrayWithObjects: @"",
                                                                        @"New",
                                                                        nil]
                                                               forKeys:
                                             [NSArray arrayWithObjects: @"Keys",
                                                                        @"Label",
                                                                        nil]],
                                          [NSMutableDictionary dictionaryWithObjects:
                                             [NSArray arrayWithObjects: @"",
                                                                        @"",
                                                                        nil]
                                                               forKeys:
                                             [NSArray arrayWithObjects: @"Keys",
                                                                        @"Label",
                                                                        nil]],
                                          [NSMutableDictionary dictionaryWithObjects:
                                             [NSArray arrayWithObjects: @"",
                                                                        @"",
                                                                        nil]
                                                               forKeys:
                                             [NSArray arrayWithObjects: @"Keys",
                                                                        @"Label",
                                                                        nil]],
                                                                   nil]
                               forKeys: [NSArray arrayWithObjects: @"TotalSegments", 
                                                                   @"RingSegments",
                                                                   @"0",
                                                                   @"1",
                                                                   @"ScrollUp",
                                                                   @"ScrollDown",
                                                                   nil]]
                             forKey: @"Submenu"];

            // Get rid of keys that may have been hanging around before it was a submenu
            [pSegmentInfo removeObjectForKey: @"Keys"];
            
            // Disable the record keys button - cant use it on a submenu selection
            [pSegmentSetupRecord setEnabled: NO];
         }
         else if ([anObject integerValue] == NSOffState)
         {
            // Delete the existing subring
            [pSegmentInfo removeObjectForKey: @"Submenu"];

            // Enable the record keys button
            [pSegmentSetupRecord setEnabled: YES];
         }

         // Select the preview ring to prevent issues when removing a subring
         [pSavedRingsOutline selectRowIndexes: [NSIndexSet indexSetWithIndex: [self indexForKey: [pPreviewRing objectForKey: @"Name"]
                                                                                   inDictionary: pConfigLookup]] 
                         byExtendingSelection: NO];
         break;
   }
   
   // Tell the saved rings outline to refresh from the root
   [pSavedRingsOutline reloadItem: nil reloadChildren: YES];
   
   // Reload the table
   [pSegmentSetupTable reloadData];
      
   // Create a new ring preview
   [previewRingView destroyRing];
   [previewRingView createRing: YES];
}


// Table delegate methods

- (void) tableViewSelectionDidChange: (NSNotification *) aNotification
{
   NSInteger     segmentType;
   NSDictionary *pSegmentInfo;

   DebugLog(@"tableViewSelectionDidChange");

   if ([[aNotification object] selectedRow] >= 0)
   {
      pSegmentInfo = [self ringSettingsRowInfo: [[aNotification object] selectedRow]: &segmentType];

      if ([pSegmentInfo objectForKey: @"Submenu"] != nil)
      {
         // Disable the record keys button - cant use it on a submenu selection
         [pSegmentSetupRecord setEnabled: NO];
      }
      else
      {
         // Enable the record keys button
         [pSegmentSetupRecord setEnabled: YES];
      }
   }
   else
   {
      [pSegmentSetupRecord setEnabled: NO];
   }
}


// Button actions

- (IBAction) addSavedRings: (id) pSender
{
   NSData               *pConfigXml;
   NSString             *pErrorDesc;
   NSPropertyListFormat  format;
   NSMutableDictionary  *pNewRing;
   NSInteger             i = 1;
   NSString             *pNewName;

   // Make a copy of the default ring
   // Grab the XML file into a data object
   pConfigXml = [[NSFileManager defaultManager] contentsAtPath: [[[[NSHomeDirectory() 
                                                                    stringByAppendingPathComponent:@"Library"]
                                                                    stringByAppendingPathComponent:@"Application Support"]
                                                                    stringByAppendingPathComponent:@"SwiftRing"]
                                                                    stringByAppendingPathComponent:@"Default.plist"]];
   
   // Convert it into a dictionary
   pNewRing = (NSMutableDictionary *)[NSPropertyListSerialization
                                      propertyListFromData:pConfigXml
                                      mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                      format:&format
                                      errorDescription:&pErrorDesc];

   // Get rid of the application list
   [pNewRing setObject: @"" forKey: @"Apps"];
   
   // Find a new name
   while ([pConfigLookup objectForKey: [NSString stringWithFormat:@"New %i", i]] != nil) 
   {
      i++;
      if (i > 20)
      {
         // Saftey valve for add spammers
         return;
      }
   }
          
   pNewName = [NSString stringWithFormat:@"New %i", i];
   [pNewRing setObject: pNewName forKey: @"Name"];

   // Add it to the lookup dictionary
   [pConfigLookup setObject: pNewRing forKey: pNewName];

   // Tell the outline to refresh from the root
   [pSavedRingsOutline reloadItem: nil reloadChildren: YES];

   // Select the newly created one
   [pSavedRingsOutline selectRowIndexes: [NSIndexSet indexSetWithIndex: [self indexForKey: pNewName inDictionary: pConfigLookup]] 
                       byExtendingSelection: NO];
}


- (IBAction) removeSavedRings: (id) pSender
{
   NSEnumerator         *pAppsEnum = nil;
   NSString             *pAppName = nil;
   NSString             *pAppList = nil;

   if (previewRingIsSubring)
   {
      // Remove the subring from the parent
      [pPreviewRingParent removeObjectForKey: @"Submenu"];
   }
   else
   {
      if ([[NSFileManager defaultManager] fileExistsAtPath: 
           [NSString stringWithFormat:@"%@/%@.plist", pSupportDirectory, [pPreviewRing objectForKey: @"Name"]]])
      {
         [pFileDeleteList addObject: 
          [NSString stringWithFormat:@"%@/%@.plist", pSupportDirectory, [pPreviewRing objectForKey: @"Name"]]];
      }

      // Remove entries from the app lookup table, indexed by the 'Apps' field
      pAppList = [pPreviewRing objectForKey: @"Apps"];

      if (nil != pAppList)
      {
         pAppsEnum = [[pAppList componentsSeparatedByString:@","] objectEnumerator];

         // Loop through all the app names, removing them from the app lookup table
         while (pAppName = [pAppsEnum nextObject])
         {
            [pAppLookup removeObjectForKey: pAppName];
         }
      }

      // Remove the subring from the lookup dictionary and mark for deletion later
      [pConfigLookup removeObjectForKey: [pPreviewRing objectForKey: @"Name"]];
   }

   // Tell the outline to refresh from the root
   [pSavedRingsOutline reloadItem: nil reloadChildren: YES];

   // Make sure nothing is selected
   [pSavedRingsOutline deselectAll: nil];
}


- (IBAction) refreshApplications: (id) pSender
{
   [self updateApplicationsOutlineData];
}


- (IBAction) movedSegmentsSlider: (id) pSender
{
   NSInteger i;
   NSInteger sliderValue   = [pSegmentsSlider integerValue];
   NSInteger ringSegments  = [[pPreviewRing objectForKey: @"RingSegments"] integerValue];
   NSString *pSegmentName  = [NSString stringWithFormat:@"%i", sliderValue - 1];

   if (sliderValue > ringSegments)
   {
      // Slider increased the segments

      for (i = ringSegments + 1; i <= sliderValue; i++)
      {
         if ([pPreviewRing objectForKey: pSegmentName] == nil)
         {
            // An existing segment was not already here, make new one(s)

            if ([pPreviewRing objectForKey: [NSString stringWithFormat:@"%i", i]] == nil)
            {
               [pPreviewRing setObject: [NSMutableDictionary 
                                            dictionaryWithObjects: [NSArray arrayWithObjects: @"",     @"New",   nil]
                                                          forKeys: [NSArray arrayWithObjects: @"Keys", @"Label", nil]]
                                forKey: [NSString stringWithFormat:@"%i", i - 1]];
            }
         }
      }
   }

   // Adjust the segment values
   [pPreviewRing setObject: [NSString stringWithFormat: @"%i", sliderValue] forKey: @"RingSegments"];
   [pPreviewRing setObject: [NSString stringWithFormat: @"%i", sliderValue + 2] forKey: @"TotalSegments"];

   // Create a new ring preview
   [previewRingView destroyRing];
   [previewRingView createRing: YES];

   // Reload the table
   [pSegmentSetupTable reloadData];
}


- (IBAction) recordKeySequence: (id) pSender
{
   [recordingPanel startRecording];
   [NSApp runModalForWindow: recordingPanel];
}


- (void) recordKeySequenceDone: (NSString *) pRecordedKeys
{
   NSInteger            segmentType;
   NSMutableDictionary *pSegmentInfo;

   pSegmentInfo = [self ringSettingsRowInfo: [pSegmentSetupTable selectedRow]: &segmentType];

   DebugLog (@"Done recording, selected row: %i, string %@", [pSegmentSetupTable selectedRow], pRecordedKeys);
   [pSegmentInfo setObject: pRecordedKeys forKey: @"Keys"];
}

// Preferences window dialog

- (IBAction) save: (id) pSender
{
   [self saveConfigs];

   // The rest is the same as the cancel actions
   [self cancel: self];
}

- (IBAction) cancel: (id) pSender
{
   // Deselect any selected saved ring
   [pSavedRingsOutline deselectAll: nil];
   [pSavedRingsOutline collapseItem: nil collapseChildren: YES];
   
   // Reload the configs from the files
   [self reloadConfigs];
   
   // Refresh all the underlying preferences window data
   [pSavedRingsOutline reloadItem: nil reloadChildren: YES];
   [self disableRingSettingsControls];
   
   [preferencesPanel close];
}


- (IBAction) setLaunchKey: (id) pSender
{
   DebugLog(@"New LaunchKey = %i\n", [[pSender selectedItem] tag]);
   
   [pPrefs setObject:[NSNumber numberWithInteger: [[pSender selectedItem] tag]] forKey: @"LaunchKey"];
}

- (IBAction) setAllowArrows: (id) pSender
{
   DebugLog(@"New allow arrows = %i\n", [pSender state]);
         
   [pPrefs setObject:[NSNumber numberWithInteger: [pSender state]] forKey: @"Arrows"];
}

- (IBAction) setMenuDelay: (id) pSender
{
   DebugLog(@"New Delay = %f\n", [pSender floatValue]);
   
   [pMenuDelayText setFloatValue:[pSender floatValue]];
   [pPrefs setObject:[NSNumber numberWithFloat: [pSender floatValue]] forKey: @"Delay"];
}

- (IBAction) setEnableMenuBar: (id) pSender
{
   DebugLog(@"New menu bar arrows = %i\n", [pSender state]);
         
   [pPrefs setObject:[NSNumber numberWithInteger: [pSender state]] forKey: @"MenuBar"];
}

- (IBAction) regKeyEntryStart: (id) pSender
{
	// Launch the registration panel
	[NSApp runModalForWindow: regPanel];

	[regKeyEntry setStringValue: @""];
}

- (IBAction) regKeyEntryDone: (id) pSender
{
	// Grab the key from the text field and process it
	NSString *rawKey = nil;
	NSString *normalizedKey = nil;
	
	DebugLog(@"Processing registration key");
	
	// Strip spaces and dashes
	rawKey = [regKeyEntry stringValue];
	
	if (nil != rawKey && ([rawKey length] >= 12))
	{
		// Valid string
		normalizedKey = [NSString stringWithString:[[rawKey  
											    	 stringByReplacingOccurrencesOfString: @" " withString: @""]
													 stringByReplacingOccurrencesOfString: @"-" withString: @""]];
		unsigned long long ullKey;
		
		if([[NSScanner scannerWithString: normalizedKey] scanHexLongLong: &ullKey])
		{
			// Valid hex string
			DebugLog(@"String: %@, Ulonglong: %llu", normalizedKey, ullKey);
			
			// Validate the registration key
			if (validateKey([NSNumber numberWithLongLong: ullKey]))
			{
				DebugLog(@"Valid registration key entered!");
				
				// Save the registration key, notify the overlay window, and pop up a message
				[pPrefs setObject:[NSNumber numberWithLongLong: ullKey] forKey: @"RegKey"];
				[regKeyStatus setStringValue: @"Full Version"];
                [regButton setEnabled: NO];
				
				[overlayWindow setValidKey: YES];
				[overlayWindow displayMessage:@"Key valid, thanks for buying!"];
				
				[NSApp stopModal];
				[regPanel close];
				[self save: self];
				
				return;
			}
			else
			{
				DebugLog(@"RSA verification failed");				
				[overlayWindow displayMessage:@"Key invalid, try again or contact us."];
			}
		}
		else
		{
			DebugLog(@"Hex scanning failed");
			[overlayWindow displayMessage:@"Key invalid, try again or contact us."];
		}
	}
	else
	{
		DebugLog(@"Invalid key length/format");
		[overlayWindow displayMessage:@"Key invalid, try again or contact us."];
	}
	
	[NSApp stopModal];
	[regPanel close];
}

- (BOOL) windowShouldClose: (id) window
{
   DebugLog(@"Preferences window closing");

   return YES;
}


- (void) windowDidResignKey: (NSNotification *) notification
{
   DebugLog(@"Preferences window not key"); 
}


// Private methods

- (int) numberOfSubrings: (id) item
{
   int count = 0;

   for (id key in item)
   {
      // Step through all the objects in this ring configuration and see if there are subrings
      if ([[item objectForKey: key] isKindOfClass: [NSDictionary class]] &&
          [[item objectForKey: key] objectForKey: @"Submenu"])
      {
         count++;
      }
   }

   DebugLog(@"numberOfSubrings: %i", count);

   return count;
}


- (NSInteger) indexForKey: (NSString *) searchKey inDictionary: (NSDictionary *) dictionary
{
   NSInteger index = 0;

   for (id key in dictionary)
   {
      if ([key localizedCaseInsensitiveCompare: searchKey] == NSOrderedSame)
      {
         return index;
      }

      index++;
   }

   return index;
}


- (void) updateRingSettingsControls
{
   bool enableApplicationsOutline;

   // First load up any underlying data
   enableApplicationsOutline = [self updateApplicationsOutlineData];
   [pSegmentsSlider setIntValue: [[pPreviewRing objectForKey: @"RingSegments"] intValue]];
   [pSegmentSetupTable deselectAll: self];
   [pSegmentSetupTable reloadData];
   
   // Now enable all the controls and labels
   [pApplicationsLabel   setEditable: NO];
   [pApplicationsLabel   setEnabled: YES];
   [pApplicationsOutline setEnabled: enableApplicationsOutline];
   [pApplicationsRefresh setEnabled: YES];

   [pSegmentsLabel       setEditable: NO];
   [pSegmentsLabel       setEnabled: YES];
   [pSegmentsSlider      setEnabled: YES];

   [pSegmentSetupLabel   setEditable: NO];
   [pSegmentSetupLabel   setEnabled: YES];
   [pSegmentSetupTable   setEnabled: YES];
}


- (void) disableRingSettingsControls
{
   // Clear away any underlying data
   [self updateApplicationsOutlineData];
   [pSegmentsSlider setIntValue: 0];
   [pSegmentSetupTable deselectAll: self];
   [pSegmentSetupTable reloadData];

   // Disable all the controls and labels
   [pApplicationsLabel   setEnabled: NO];
   [pApplicationsLabel   setEditable: YES];

   // Hack to make the underlying data clear away when removed
   [pApplicationsOutline setEnabled: YES];
   [pApplicationsOutline setEnabled: NO];
   [pApplicationsRefresh setEnabled: NO];

   [pSegmentsLabel       setEnabled: NO];
   [pSegmentsLabel       setEditable: YES];
   [pSegmentsSlider      setEnabled: NO];

   [pSegmentSetupLabel   setEnabled: NO];
   [pSegmentSetupLabel   setEditable: YES];
   [pSegmentSetupTable   setEnabled: NO];
}

- (bool) updateApplicationsOutlineData
{
   int existing, launched;
   bool addLaunched = YES;
   bool enable = NO;

   NSString *pExistingAppsString = nil;
   NSArray *pExistingApps = nil;
   NSArray *pLaunchedApps = nil;
   NSRunningApplication *pRunningApp = nil;

   // Start with a fresh list
   [pApplicationsOutlineData removeAllObjects];
   [pApplicationsOutlineDataPreSelected removeAllIndexes];

   if (nil == pPreviewRing)
   {
      // The application outline is not enabled
      enable = NO;
   }
   else if (previewRingIsSubring)
   {
      // Cannot modify apps from subring - the application outline is not enabled
      [pApplicationsOutlineData addObject: @"Select main ring to modify"];
      enable = NO;
   }
   else 
   {
      // Ok, we have a valid main preview ring!
      // Check all names in the app list against the currently running apps to not add duplicates
	   pExistingAppsString = [pPreviewRing objectForKey: @"Apps"];
	   
	   if (nil != pExistingAppsString)
	   {
		   pExistingApps = [[pPreviewRing objectForKey: @"Apps"] componentsSeparatedByString:@","];
	   }
	   
      //pLaunchedApps = [[NSWorkspace sharedWorkspace] launchedApplications];
      pLaunchedApps = [[NSWorkspace sharedWorkspace] runningApplications];

      for (launched = 0; launched < [pLaunchedApps count]; launched++)
      {
		 addLaunched = YES;
         pRunningApp = [pLaunchedApps objectAtIndex: launched];
  
		 // Omit all UI elements and background applications
		 if (pRunningApp.activationPolicy != NSApplicationActivationPolicyRegular) 
			 continue;
		  
		  DebugLog(@"%@", pRunningApp.localizedName);
		  
         for (existing = 0; (nil != pExistingApps) && (existing < [pExistingApps count]); existing++)
         {
            if ([[pExistingApps objectAtIndex: existing] localizedCaseInsensitiveCompare:
                pRunningApp.localizedName] ==
                NSOrderedSame)
            {
               addLaunched = NO;
			   break;
            }
         }

         if (addLaunched && (nil == [pAppLookup objectForKey: pRunningApp.localizedName]))
         {
            // This launched apps is not already in the existing apps list, or already has a ring defined, so add it
            [pApplicationsOutlineData addObject: pRunningApp.localizedName];
         }
	  }

      // Now add all the existing apps
      for (existing = 0; (nil != pExistingApps) && (existing < [pExistingApps count]); existing++)
      {
         if ([[pExistingApps objectAtIndex: existing] localizedCaseInsensitiveCompare: @""] != NSOrderedSame)
         {
            // Add items to the pre-selected apps array
            [pApplicationsOutlineDataPreSelected addIndex: [pApplicationsOutlineData count]];
            [pApplicationsOutlineData addObject: [pExistingApps objectAtIndex: existing]];
         }
      }

      if ([self isDefault])
      {
         enable = NO;
      }
      else
      {
         enable = YES;
      }
   }

   // Tell the outline to refresh from the root
   [pApplicationsOutline reloadItem: nil reloadChildren: YES];

   // Pre-select any necessary items
   [pApplicationsOutline selectRowIndexes: pApplicationsOutlineDataPreSelected byExtendingSelection: NO];

   return enable;
}


- (NSMutableDictionary *) ringSettingsRowInfo: (NSInteger) rowIndex: (NSInteger *) pRowType
{
   NSInteger totalSegments = [[pPreviewRing objectForKey: @"TotalSegments"] integerValue];
   NSInteger ringSegments  = [[pPreviewRing objectForKey: @"RingSegments"] integerValue];

   // Figure out which type of segment this row is
   if (rowIndex < ringSegments)
   {
      *pRowType = SEGMENT_NORMAL;
      return [pPreviewRing objectForKey: [NSString stringWithFormat:@"%i", rowIndex]];
   }
   else if (rowIndex == ringSegments)
   {
      *pRowType = SEGMENT_SCROLL_UP;
      return [pPreviewRing objectForKey: @"ScrollUp"];
   }
   else if (rowIndex < totalSegments)
   {
      *pRowType = SEGMENT_SCROLL_DOWN;
      return [pPreviewRing objectForKey: @"ScrollDown"];
   }

   *pRowType = SEGMENT_INVALID;
   return nil;
}


- (bool) isDefault
{
   if (pPreviewRing == nil)
   {
      return NO;
   }

   return [[pPreviewRing objectForKey: @"Name"] localizedCaseInsensitiveCompare: @"Default"] == NSOrderedSame;
}


- (void) saveConfigs
{
   NSInteger  i;  
   NSData    *xmlData;
   NSString  *error; 
   
   // Write out the preferences items to the file
   xmlData = [NSPropertyListSerialization dataFromPropertyList:pPrefs
                                                        format:NSPropertyListXMLFormat_v1_0
                                              errorDescription:&error];
   if (xmlData)
   {
      [xmlData writeToFile:[NSString stringWithFormat:@"%@/Preferences.plist", pPreferencesDirectory] 
                atomically:YES];
   }
   else
   {
      DebugLog(@"%@", error);
      [error release];
   }
   
   
   // Write out all the config lookup items to files
   for (id key in pConfigLookup)
   {
      xmlData = [NSPropertyListSerialization dataFromPropertyList:[pConfigLookup objectForKey: key]
                                                           format:NSPropertyListXMLFormat_v1_0
                                                 errorDescription:&error];
      if (xmlData)
      {
         [xmlData writeToFile:[NSString stringWithFormat:@"%@/%@.plist", pSupportDirectory, key] 
                   atomically:YES];
      }
      else
      {
         DebugLog(@"%@", error);
         [error release];
      }
   }
   
   // Remove files from the file delete list
   for (i = 0; i < [pFileDeleteList count]; i++)
   {
      [[NSFileManager defaultManager] removeItemAtPath: [pFileDeleteList objectAtIndex: i] 
                                                 error: NULL];
   }
   
   [pFileDeleteList removeAllObjects];
}


@end
