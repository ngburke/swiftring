//
//  RecordingPanel.m
//
//  Copyright 2009 SwiftRing. All rights reserved.
//

#import "Debug.h"
#import "RecordingPanel.h"
#import "RingFactory.h"
#import "Ring.h"


@implementation RecordingPanel

- (void) startRecording;
{
   DebugLog(@"startRecording");

   pRecordedKeys = [[NSMutableString alloc] initWithCapacity: 30];
   [recordingText setStringValue: @""];
   oldFlags      = 0;
   isRecording   = YES;
   maxKeys       = MAX_KEYSTROKES;
}


- (IBAction) doneRecording: (id) pSender
{
   isRecording = NO;
   [ringFactory recordKeySequenceDone: pRecordedKeys];
   [pRecordedKeys release];

   [NSApp stopModal];
   [self close];
}


- (bool) isRecording
{
   return isRecording;
}


- (void) processRecordingKeys: (CGEventRef) event ofType: (CGEventType) type
{
   UniCharCount   max = 10;
   UniCharCount   actual;
   UniChar        key[max];
   unsigned short keyCode;
   CGEventFlags   flags;
   CGEventFlags   changedFlags;
   
   if (maxKeys == 0)
   {
      return;
   }
   else 
   {
      maxKeys--;
   }

   
   CGEventKeyboardGetUnicodeString(event, max, &actual, key);
   keyCode = (unsigned short) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
   flags   = CGEventGetFlags(event);
   
   switch (type)
   {
      case kCGEventKeyUp:
         DebugLog(@"Key up! keycode: %x string: %@", keyCode, [RingFactory stringForKeyCode: keyCode withModifierFlags: flags]);
         [pRecordedKeys appendFormat: @"%i_0 ", keyCode];
         break;
         
      case kCGEventKeyDown:
         DebugLog(@"Key down! keycode: %x string: %@", keyCode, [RingFactory stringForKeyCode: keyCode withModifierFlags: flags]);
         [pRecordedKeys appendFormat: @"%i_1 ", keyCode];
         break;
         
      case kCGEventFlagsChanged:
         
         changedFlags = flags ^ oldFlags;
         
         if (changedFlags & oldFlags)
         {
            // Flag key up
            DebugLog(@"Key up flags! keycode: %x string: %@", keyCode, [RingFactory stringForKeyCode: keyCode withModifierFlags: flags]);
            [pRecordedKeys appendFormat: @"%i_0 ", keyCode];
         }
         else
         {
            // Flag key down 
            DebugLog(@"Key down flags! keycode: %x string: %@", keyCode, [RingFactory stringForKeyCode: keyCode withModifierFlags: flags]);
            [pRecordedKeys appendFormat: @"%i_1 ", keyCode];
         }
         
         oldFlags = flags;
         
         break;
   }
   
   [recordingText setStringValue: [RingFactory prettyPrintKeySequence: pRecordedKeys]];
}


- (NSString *) recordedKeys
{
   return pRecordedKeys;
}
@end
