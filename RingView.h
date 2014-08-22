//
//  RingView.h
//
//  Copyright 2009 SwiftRing. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "Ring.h"

@class OverlayWindow;
@class RingFactory;

@interface RingView : NSView 
{
   Ring     *pRing;   
   IBOutlet OverlayWindow *overlayWindow;
   IBOutlet RingFactory   *ringFactory;

   NSString     *pMessage;
   NSDictionary *pMessageAttributes;
   NSBezierPath *pMessageBox;
   NSPoint       messageLocation;
   NSTimer      *pMessageTimer;
   bool          displayingMessage;

   int           lastHitSegment;
}

- (void) createRing:  (bool) isPreview;
- (void) destroyRing;
- (RingActionStatus) detectHit: (NSPoint) location: 
                                (bool) scrollUp: 
                                (bool) scrollDown: 
                                (unsigned int) arrowBitfield:
                                (bool) isVisible;
- (void) resetHits;

- (void) displayMessage: (NSString *) pMessage;
@end
