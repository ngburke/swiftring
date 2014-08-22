//
//  RingView.m
//
//  Copyright 2009 SwiftRing. All rights reserved.
//

#import "OverlayWindow.h"
#import "RingView.h"
#import "RingFactory.h"
#import "Ring.h"
#import "Debug.h"

#define MESSAGE_HEIGHT_CORRECTION   0.88 //0.78
#define MESSAGE_BOX_BORDER_X        20
#define MESSAGE_BOX_BORDER_Y        20
#define MESSAGE_BOX_ROUND           7
#define INVALID_SEGMENT             -1

@implementation RingView

// The designated initializer for NSView
- (id)initWithFrame:(NSRect)frame 
{
   pRing    = nil;
   pMessage = nil;

   self = [super initWithFrame:frame];

   return self;
}

- (void)drawRect:(NSRect)rect
{
   int i;
   int segments;
   NSBezierPath *pPath;
   LabelElements label;
   NSDictionary *pLabelAttributes;

   DebugLog(@"drawRect start");

   // Message display takes priority over Ring display
   if (displayingMessage)
   {
      [[NSColor colorWithDeviceRed: 0.1 green: 0.1 blue: 0.1 alpha: 0.8] setFill];
      [pMessageBox fill];

      [pMessage drawAtPoint:    messageLocation 
                withAttributes: pMessageAttributes];
   }
   else if (nil == pRing)
   {
      // Do nothing, just return
   }
   else
   {

      segments = [pRing getNumSegments];

      DebugLog(@"segments = %i", segments);

      for (i = 0; i < segments; i++)
      {
         pLabelAttributes = [pRing getLabelAttributes];

         // Draw the ring path
         pPath = [pRing getSegmentPath: i];

         /*
         if ([pRing isVelocityBuffer: i])
         {
            //Make velocity buffer rings grey
            [[NSColor colorWithDeviceRed: 0.6 green: 0.6 blue: 0.6 alpha: 1.0] setStroke];
            [[NSColor colorWithDeviceRed: 0.8 green: 0.8 blue: 0.8 alpha: 1.0] setFill];
         }
         else */ 
         if ([pRing containsNextRing: i])
         {
            // Rings that open sub-rings
            [[NSColor colorWithDeviceRed: 0.9 green: 0.9 blue: 0.9  alpha: 0.8] setStroke];
            [[NSColor colorWithDeviceRed: 0.5 green: 0.5 blue: 0.55 alpha: 0.8] setFill];
         }
         else
         {
            // Rings that do something
            [[NSColor colorWithDeviceRed: 1.0 green: 1.0 blue: 1.0  alpha: 0.8] setStroke];
            [[NSColor colorWithDeviceRed: 0.7 green: 0.7 blue: 0.75 alpha: 0.8] setFill];
         }
      
         [pPath stroke];
         [pPath fill];

         // Draw the corresponding label box and label
         label = [pRing getSegmentLabel: i];

         if ([label.pLabel localizedCaseInsensitiveCompare: @""] != NSOrderedSame)
         {
            // This isn't a 'blank' label, so draw it!
            [[NSColor colorWithDeviceRed: 0.1 green: 0.1 blue: 0.1 alpha: 0.8] setFill];
            [label.pLabelBox fill];

            [label.pLabel drawAtPoint: label.location withAttributes: pLabelAttributes];
         }
      }
   }

   // Force the main window to re-calculate the shadow
   [overlayWindow invalidateShadow];

   DebugLog(@"drawRect done");
}

- (void) createRing: (bool) isPreview
{
   float centerX;
   float centerY;

   // Find the center of this view
   centerX = [self frame].size.width / 2;
   centerY = [self frame].size.height / 2;

   // Get the RingFactory to make a new ring
   pRing = [ringFactory createRing:centerX :centerY: isPreview];

   // If creating a ring, stop displaying messages
   displayingMessage = NO;
   [overlayWindow setAlphaValue: 0.0];

   if (nil != pMessageTimer)
   {
      [pMessageTimer invalidate];
      pMessageTimer = nil;
   }

   lastHitSegment = INVALID_SEGMENT;

   // Invalidate the view so it will redraw
   [self setNeedsDisplay:YES];
}

- (void) destroyRing
{
   int ignoreEvents;
   
   // If there are any outstanding actions left, execute them now!
   // Note: If we've already executed a segment, the lastHitSegment is reset to INVALID_SEGMENT
   if (lastHitSegment != INVALID_SEGMENT)
   {
      DebugLog(@"Executed outstanding actions %i %i", lastHitSegment);
      [pRing executeAction: lastHitSegment: &ignoreEvents];
   }

   [pRing release];
   pRing = NULL;

   // Invalidate the view so it will redraw
   [self setNeedsDisplay:YES];
}

- (RingActionStatus) detectHit: (NSPoint) location: 
                                (bool) scrollUp: 
                                (bool) scrollDown: 
                                (unsigned int) arrowBitfield: 
                                (bool) isVisible;
{
   int   hitSegment;
   int   ignoreKeyEvents = 0;
   float centerX;
   float centerY;
   RingActionStatus status = RING_ACTION_NONE;

   // Find the center of this view
   centerX = [self frame].size.width / 2;
   centerY = [self frame].size.height / 2;

   hitSegment = [pRing detectHit: location: centerX: centerY: scrollUp: scrollDown: arrowBitfield];

   if (!(hitSegment < 0))
   {
      DebugLog(@"hitSegment %i", hitSegment);
      
      if (![pRing isSubring] || isVisible || scrollUp || scrollDown)
      {
         // Execute the action for this segment immediately if this is a main ring, the ring is visible, or its a scroll         
         status = [pRing executeAction: hitSegment: &ignoreKeyEvents];
         lastHitSegment = INVALID_SEGMENT;
         [overlayWindow setIgnoreKeyEvents: ignoreKeyEvents];
      }
      else
      {
         // Otherwise update the last hit segment for possible execution later when the mouse is released
         status = RING_ACTION_REFRESH;
         lastHitSegment = hitSegment;
      }

      // If we're not done, refresh the view and reset the display timer
      if (RING_ACTION_REFRESH == status)
      {
         [self setNeedsDisplay: YES];
      }
   }

   return status;
}


- (void) resetHits
{
   lastHitSegment = INVALID_SEGMENT;
}

- (void) displayMessage: (NSString *) pMessageString
{
   NSSize    messageSize;
   NSFont   *pFont           = [NSFont systemFontOfSize:30];
   //NSFont   *pFont           = [NSFont fontWithName:@"Verdana" size:30];
   //NSColor  *pFgColor        = [NSColor colorWithDeviceRed: 0.2 green: 0.8 blue: 0.2 alpha: 1.0];
   NSColor  *pFgColor        = [NSColor colorWithDeviceRed: 0.9 green: 0.9 blue: 0.9 alpha: 1.0];
   NSArray  *pAttribKeys     = [NSArray arrayWithObjects:NSFontAttributeName, 
                                                         NSForegroundColorAttributeName,
                                                         nil];
   NSArray  *pAttribObjects  = [NSArray arrayWithObjects:pFont, 
                                                         pFgColor,
                                                         nil];

   // Release any prior message stuff
   if (pMessage != nil)
   {
      [pMessage release];
      [pMessageAttributes release];
      [pMessageBox release];
      [pMessageTimer invalidate];

      pMessage = nil;
      pMessageAttributes = nil;
      pMessageBox = nil;
      pMessageTimer = nil;
      
      [overlayWindow setAlphaValue: 0.0];
   }

   pMessage           = [[NSString alloc] initWithString: pMessageString]; 
   pMessageAttributes = [[NSDictionary alloc] initWithObjects: pAttribObjects forKeys: pAttribKeys];

   // Create the label bounding box
   messageSize = [pMessage sizeWithAttributes: pMessageAttributes]; 

   // Put the message slightly above center
   messageLocation.x  = [self frame].origin.x + ([self frame].size.width / 2) - (messageSize.width / 2);
   messageLocation.y  = [self frame].origin.y + ([self frame].size.height / 2);

   pMessageBox = [[NSBezierPath alloc] init];

   [pMessageBox appendBezierPathWithRoundedRect: 
                   NSMakeRect(messageLocation.x - MESSAGE_BOX_BORDER_X,
                              messageLocation.y - MESSAGE_BOX_BORDER_Y,
                              messageSize.width  + (MESSAGE_BOX_BORDER_X * 2),
                              (messageSize.height * MESSAGE_HEIGHT_CORRECTION) + (MESSAGE_BOX_BORDER_Y * 2))
                   xRadius: MESSAGE_BOX_ROUND 
                   yRadius: MESSAGE_BOX_ROUND];


   // Fade in the main window and set a timer to fade it out
   [overlayWindow fadeIn];

   pMessageTimer = [NSTimer scheduledTimerWithTimeInterval:([pMessageString length] * 5 / 60)
                     target:self
                     selector:@selector(dismissMessage:)
                     userInfo:nil
                     repeats:NO];

   displayingMessage = YES;

   [overlayWindow trueCenter];

   [self setNeedsDisplay:YES];
}

- (void) dismissMessage: (NSTimer*) timer
{
   [overlayWindow fadeOut];
   displayingMessage = NO;

   // Invalidate the message timer
   pMessageTimer = nil;
}

@end
