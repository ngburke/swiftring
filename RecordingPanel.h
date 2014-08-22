//
//  RecordingPanel.h
//
//  Copyright 2009 SwiftRing. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class RingFactory;

@interface RecordingPanel : NSPanel {
   NSMutableString *pRecordedKeys;
   CGEventFlags     oldFlags;
   bool isRecording;
   int maxKeys;
   
   IBOutlet NSTextField *recordingText;
   IBOutlet RingFactory *ringFactory;
}

- (void)     startRecording;
- (IBAction) doneRecording: (id) pSender;
- (bool)     isRecording;

- (void)       processRecordingKeys: (CGEventRef) event ofType: (CGEventType) type;
- (NSString *) recordedKeys;

@end
