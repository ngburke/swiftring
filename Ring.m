//
//  Ring.m
//
//  Copyright 2009 SwiftRing. All rights reserved.
//

#import "Ring.h"
#import "RingFactory.h"
#import "Debug.h"

#define RING_INNER_RADIUS        50
#define RING_OUTER_RADIUS        60
#define RING_LABEL_RADIUS        70
#define SEGMENT_GAP              3
#define RING_VELOCITY_RADIUS     2
#define LABEL_HEIGHT_CORRECTION  0.90
#define LABEL_BOX_BORDER_X       6
#define LABEL_BOX_BORDER_Y       2
#define LABEL_BOX_ROUND          7
#define INVALID_KEY              -1

typedef enum _PARSE_STATES
{
   PARSE_RING = 0,
   PARSE_SCROLLUP,
   PARSE_SCROLLDOWN,
   PARSE_DONE,
} PARSE_STATES;

#define RADIANS(degrees) ((degrees) * M_PI / 180)
#define DEGREES(radians) ((radians) * 180 / M_PI)

@implementation Ring

// This function can recurse, and is used internally only
- (void) initRing: (NSDictionary *) pRingInfo: (int *) index: (float) startAngle: (NSArray *) pAttribKeys: 
                                               (NSArray *) pAttribObjects: (bool) isSubring;
{
   int   parseState    = PARSE_RING;
   int   ring          = *index;
   int   segment       = 0;
   int   ringSegments  = 0;
   int   totalSegments = 0;
   int   key           = 0;
   float angle; 
   float spanAngle;
   NSDictionary   *pSegmentInfo;
   NSDictionary   *pSubringInfo;
   NSString       *pKeyCode;

   // Normalize the start angle
   startAngle = (startAngle  > 0) ? startAngle  : 360 + startAngle;
   angle      = startAngle; 

   //DebugLog(@"initRing: index = %i", *index);
   //DebugLog(@"initRing: startAngle = %f", startAngle);

   totalSegments = [[pRingInfo objectForKey: @"TotalSegments"] intValue];
   ringSegments  = [[pRingInfo objectForKey: @"RingSegments"] intValue];

   spanAngle   = 360 / ([[pRingInfo objectForKey: @"RingSegments"] intValue] + 0);

   ringContainer[ring].numSegments      = totalSegments;
   ringContainer[ring].pLabelAttributes = [[NSDictionary alloc] initWithObjects: pAttribObjects forKeys: pAttribKeys];
   ringContainer[ring].isSubring        = isSubring;

   // Set up all the label and action info for each segment (MAX_SEGMENTS check is a fail-safe)
   while (TRUE && (segment < MAX_SEGMENTS))
   {
      // Parser state machine
      if (PARSE_RING == parseState)
      {
         pSegmentInfo = [pRingInfo objectForKey: [NSString stringWithFormat:@"%i", segment /*- (isSubring ? 1: 0)*/]];

         if ((segment >= ringSegments) || (nil == pSegmentInfo))
         {
            // Move to the next state immediately, skip processing
            parseState++;
            //DebugLog(@"Moved to PARSE_SCROLLUP %i", parseState);
            continue;
         }

      }
      else if (PARSE_SCROLLUP == parseState)
      {
         pSegmentInfo = [pRingInfo objectForKey: @"ScrollUp"];

         // Move to the next state after processing
         parseState++;
         //DebugLog(@"Moved to PARSE_SCROLLDOWN %i", parseState);

         if (nil == pSegmentInfo)
         {
            // Move to the next state immediately, skip processing
            ringContainer[ring].scrollUpSegment = -1;
            continue;
         }

         ringContainer[ring].scrollUpSegment = segment;
      }
      else if (PARSE_SCROLLDOWN == parseState)
      {
         pSegmentInfo = [pRingInfo objectForKey: @"ScrollDown"];

         // Move to the next state after processing
         parseState++;
         //DebugLog(@"Moved to PARSE_DONE %i", parseState);

         if (nil == pSegmentInfo)
         {
            // Move to the next state immediately, skip processing
            ringContainer[ring].scrollDownSegment = -1;
            continue;
         }

         ringContainer[ring].scrollDownSegment = segment;
      }
      else
      {
         break;
      }

      //DebugLog(@"Ring initializing segment: %i", segment);

      ringContainer[ring].label[segment].pLabel = [[NSString alloc] initWithString:[pSegmentInfo objectForKey:@"Label"]]; 

      //
      // Construct the keyboard actions.  Commas seperate keys that should be held down at the same time, spaces
      // seperate the ordering of keys pressed at the same time.
      //
      key = 0;

      // Keycodes are seperated by spaces
      //DebugLog(@"Keys: '%@'", [pSegmentInfo objectForKey: @"Keys"]);

      NSEnumerator *pKeyCodeEnum = [[[pSegmentInfo objectForKey: @"Keys"] componentsSeparatedByString:@" "] objectEnumerator];

      // Loop through all the keycodes
      while ((pKeyCode = [pKeyCodeEnum nextObject]) && (NSOrderedSame != [pKeyCode compare: @""]))
      {

         // Keycodes and up/down indication are seperated by underscores
         NSArray *pKeyUpDownArray = [pKeyCode componentsSeparatedByString:@"_"];

         ringContainer[ring].action[segment].keyCode[key]   = [[pKeyUpDownArray objectAtIndex: 0] intValue];
         ringContainer[ring].action[segment].keyIsDown[key] = [[pKeyUpDownArray objectAtIndex: 1] boolValue];

         //DebugLog(@"Code: %i  Down: %i  key: %i",
         //         ringContainer[ring].action[segment].keyCode[key], ringContainer[ring].action[segment].keyIsDown[key], key);
         
         key++;        
      }

      // Mark the key watermark
      if (key < MAX_KEYSTROKES)
      {
         ringContainer[ring].action[segment].keyCode[key] = INVALID_KEY;
      }      

      pSubringInfo = [pSegmentInfo objectForKey:@"Submenu"];

      // If there is a sub-ring, call this function recursively w/ a new index
      if (nil != pSubringInfo)
      {
         *index = *index + 1;
         
         if (*index < MAX_SEGMENTS)
         {
            ringContainer[ring].action[segment].pNextRing = &ringContainer[*index];
            [self initRing: pSubringInfo: index: 90/*angle*/: pAttribKeys: pAttribObjects: YES];
         }
         else
         {
            DebugLog(@"initRing: Out of segments!");
         }
      }

      segment++;

      // Keep advancing the angle counter clockwise - needed to track the entry angle for the subring
      if (PARSE_RING == parseState)
      {
         angle -= spanAngle;
      }

   } 

   // Generate the ring graphics and labels
   [self generatePaths: &ringContainer[ring] :ringContainer[ring].numSegments: startAngle: spanAngle: ringCenterX: ringCenterY: isSubring];
}



- (id) init: (NSDictionary *) pRingInfo: (float) centerX: (float) centerY
{
   DebugLog(@"init start");

   int      index;
   NSFont   *pFont          = [NSFont systemFontOfSize:15];
   //NSFont   *pFont          = [NSFont fontWithName:@"Verdana" size:15];
   NSColor  *pFgColor       = [NSColor colorWithDeviceRed: 0.9 green: 0.9 blue: 0.9 alpha: 1.0];
   NSArray  *pAttribKeys    = [NSArray arrayWithObjects:NSFontAttributeName, 
                                                  NSForegroundColorAttributeName,
                                                  nil];
   NSArray  *pAttribObjects = [NSArray arrayWithObjects:pFont, 
                                                  pFgColor,
                                                  nil];

   if (nil == pRingInfo)
   {
      return self;
   }

   ringCenterX = centerX;
   ringCenterY = centerY;
   index = 0;
   
   // Generate all ring text and paths
   [self initRing: pRingInfo: &index: 90: pAttribKeys: pAttribObjects: NO];

   // Set the current ring to the main ring for now
   pCurrentRing = &ringContainer[0];

   DebugLog(@"init done");
 
   return self;
}



- (void)dealloc
{
   int ringIndex, segIndex;

   //
   // Release all the items we allocated 
   // (only methods that have 'alloc', 'new', or 'copy' must be freed)
   //
   for (ringIndex = 0; ringIndex < MAX_RINGS; ringIndex++)
   {
      [ringContainer[ringIndex].pLabelAttributes release];
      ringContainer[ringIndex].pLabelAttributes = NULL;

      for (segIndex = 0; segIndex < ringContainer[ringIndex].numSegments; segIndex++)
      {
         [ringContainer[ringIndex].path[segIndex].pPath release];
         ringContainer[ringIndex].path[segIndex].pPath = NULL;

         [ringContainer[ringIndex].label[segIndex].pLabel release];
         ringContainer[ringIndex].label[segIndex].pLabel = NULL;
         
         [ringContainer[ringIndex].label[segIndex].pLabelBox release];
         ringContainer[ringIndex].label[segIndex].pLabelBox = NULL;
      }
   }

   [super dealloc];
}
 

- (int) getNumSegments
{
   return pCurrentRing->numSegments;
}


- (NSDictionary *) getLabelAttributes
{
   return pCurrentRing->pLabelAttributes;
}


- (NSBezierPath *) getSegmentPath: (int) segment
{
   return pCurrentRing->path[segment].pPath;
}


- (LabelElements) getSegmentLabel: (int) segment
{
   return pCurrentRing->label[segment];
}



- (int) detectHit:(NSPoint) location: (float) centerX: (float) centerY: (bool) scrollUp: (bool) scrollDown: (unsigned int) arrowBitfield;
{
   int i;
   int status = -1;

   location.x -= centerX;
   location.y -= centerY;
  
   if (arrowBitfield)
   {
      status = [Ring arrowSegmentHitTest: arrowBitfield: pCurrentRing->numSegments];
   }
   else if (scrollUp && (pCurrentRing->scrollUpSegment != 0))
   {
      status = pCurrentRing->scrollUpSegment;
   }

   else if (scrollDown && (pCurrentRing->scrollDownSegment != 0))
   {
      status = pCurrentRing->scrollDownSegment;
   }
   /*
   else if (pCurrentRing->isSubring && (sqrt((location.x * location.x) + (location.y * location.y)) > RING_VELOCITY_RADIUS))
   {
      //
      // Subring velocity buffer
      //
      if ([Ring isPointInAngle: location: pCurrentRing->path[0]])
      {
         status = 0;
      }
   }
   */
   // See if the point is within the ring's radius
   else if (sqrt((location.x * location.x) + (location.y * location.y)) < RING_OUTER_RADIUS)
   {
      // -1 represents no legal segment
      status = -1;
   }
   else
   {
      // Ok, now see which segment it passed through
      for (i = 0; (i < pCurrentRing->numSegments) && (pCurrentRing->path[i].pPath != NULL); i++)
      {
         if ([Ring isPointInAngle: location: pCurrentRing->path[i]])
         {
            status = i;
            break;
         }
      }
   }

   return status;
}


- (RingActionStatus) executeAction: (int) segment: (int *) pIgnoreKeyEvents
{
   int i;
   unsigned int flags;
   CGEventRef event;

   // Flags initialized to 0 will clear away the flag key used to bring up the ring,
   // essentially masking it from the defined user key sequence which is what we want!
   flags = 0;
   
   // Velocity buffer just causes a refresh, no action taken
   /*
   if (pCurrentRing->action[segment].isVelocityBuffer)
   {
      return RING_ACTION_REFRESH;
   }
   */

   // Execute all the key codes
   for (i = 0; i < MAX_KEYSTROKES; i++)
   {
      // Break if there is no valid keycode in the array
      if (INVALID_KEY == pCurrentRing->action[segment].keyCode[i])
      {
         DebugLog(@"Invalid key hit!");
         break;
      }
      else
      {
         DebugLog(@"Sending key: %i", pCurrentRing->action[segment].keyCode[i]);

         event = CGEventCreateKeyboardEvent(0, 
                                            pCurrentRing->action[segment].keyCode[i],
                                            pCurrentRing->action[segment].keyIsDown[i]);

         
         if (pCurrentRing->action[segment].keyIsDown[i])
         {
            switch (pCurrentRing->action[segment].keyCode[i])
            {
               case 54:
               case 55:
                  flags |= kCGEventFlagMaskCommand;
                  break;
                  
               case 56:
               case 60:
                  flags |= kCGEventFlagMaskShift;
                  break;
                  
               case 57:
                  flags |= kCGEventFlagMaskAlphaShift;
                  break;
                  
               case 58:
               case 61:
                  flags |= kCGEventFlagMaskAlternate;
                  break;
                  
               case 59:
               case 62:
                  flags |= kCGEventFlagMaskControl;
                  break;
                  
               case 63:
                  break;
            }
         }
         else
         {
            switch (pCurrentRing->action[segment].keyCode[i])
            {
               case 54:
               case 55:
                  flags &= ~kCGEventFlagMaskCommand;
                  break;
                  
               case 56:
               case 60:
                  flags &= ~kCGEventFlagMaskShift;
                  break;
                  
               case 57:
                  flags &= ~kCGEventFlagMaskAlphaShift;
                  break;
                  
               case 58:
               case 61:
                  flags &= ~kCGEventFlagMaskAlternate;
                  break;
                  
               case 59:
               case 62:
                  flags &= ~kCGEventFlagMaskControl;
                  break;
                  
               case 63:
                  break;
            }
         }
         
         CGEventSetFlags(event, flags);
         CGEventPost(kCGSessionEventTap, event);
         CFRelease(event);
         
         /*
         CGPostKeyboardEvent(0, 
                             pCurrentRing->action[segment].keyCode[i],
                             pCurrentRing->action[segment].keyIsDown[i]);
         */
      }
   }
      
   *pIgnoreKeyEvents = i;
   
   // Scroll events keep the same ring
   if (segment == pCurrentRing->scrollUpSegment ||
       segment == pCurrentRing->scrollDownSegment)
   {
      return RING_ACTION_STAY;
   }

   // Normal ring actions w/ no subring just dismiss the ring
   else if (NULL == pCurrentRing->action[segment].pNextRing)
   {
      return RING_ACTION_DONE;
   }
   
   // Actions w/ a subring move to the next ring
   else
   {
      pCurrentRing = pCurrentRing->action[segment].pNextRing;
   }

   return RING_ACTION_REFRESH;
}


- (BOOL) containsNextRing: (int) segment
{
   if (pCurrentRing->action[segment].pNextRing != NULL)
   {
      return YES;
   }
   
   return NO;
}

/*
- (BOOL) isVelocityBuffer: (int) segment
{
   return pCurrentRing->action[segment].isVelocityBuffer;
}
*/


- (BOOL) isSubring
{
   return pCurrentRing->isSubring;
}


- (void) generatePaths:(RingContainer*) pRingContainer: (int) segments: (float) startAngle: (float) spanAngle: 
                                                        (float) centerX: (float) centerY: (bool) isSubring
{
   int   i;
   int   nonRingSegments = 0;
   float angleCenter;
   float angleLeftEdge;
   float angleRightEdge;
   float labelX;
   float labelY;
   NSSize labelSize;

   // Adjust for non-ring segments
   if (pRingContainer->scrollUpSegment >= 0)
   {
      nonRingSegments++;
   }
   if (pRingContainer->scrollDownSegment >= 0)
   {
      nonRingSegments++;
   }

   angleCenter   = startAngle;
   angleLeftEdge = angleCenter + (spanAngle / 2);

   // Generate the segments
   for (i = 0; i < segments; i++)
   {
   
      //
      // Generate the bezier paths used for hit detection, clockwise (only for non-scroll wheel segments)
      //
      if ((i != pRingContainer->scrollUpSegment) && (i != pRingContainer->scrollDownSegment))
      {
         angleRightEdge = angleLeftEdge - spanAngle;

         pRingContainer->path[i].pPath = [[NSBezierPath alloc] init];

         [pRingContainer->path[i].pPath setLineWidth:2.0];

         [pRingContainer->path[i].pPath appendBezierPathWithArcWithCenter:NSMakePoint(centerX, centerY)
            radius:RING_INNER_RADIUS
            startAngle:angleLeftEdge - SEGMENT_GAP
            endAngle:angleRightEdge + SEGMENT_GAP
            clockwise:YES];

         [pRingContainer->path[i].pPath appendBezierPathWithArcWithCenter:NSMakePoint(centerX, centerY)
            radius:RING_OUTER_RADIUS
            startAngle:angleRightEdge + SEGMENT_GAP
            endAngle:angleLeftEdge - SEGMENT_GAP
            clockwise:NO];
     
         [pRingContainer->path[i].pPath closePath];
 
         // Store away the angles (always in positive form) for later hit detection
         pRingContainer->path[i].angleEnd   = (angleLeftEdge  > 0) ? angleLeftEdge  : 360 + angleLeftEdge;
         pRingContainer->path[i].angleStart = (angleRightEdge > 0) ? angleRightEdge : 360 + angleRightEdge;
      
         //DebugLog(@"Angles [%i] : %i %i", i, pRingContainer->path[i].angleStart, pRingContainer->path[i].angleEnd);

         angleLeftEdge -= spanAngle;
      }

      //
      // Generate the label positions, unless this is the special segment for the subring
      //
      /*
      if ((0 == i) && isSubring)
      {
         pRingContainer->action[i].isVelocityBuffer = YES;
      }
      else
      {
      */
         labelSize = [pRingContainer->label[i].pLabel sizeWithAttributes:pRingContainer->pLabelAttributes]; 
      
         // Scroll down segment
         if (i == pRingContainer->scrollDownSegment)
         {
            // Start by setting the basic points for the current segment based on the angle
            labelX = 0;
            labelY = (RING_LABEL_RADIUS * sin(RADIANS(270))) - (labelSize.height * LABEL_HEIGHT_CORRECTION) - (LABEL_BOX_BORDER_Y * 4);
         }
         // Scroll up segment
         else if (i == pRingContainer->scrollUpSegment)
         {
            // Start by setting the basic points for the current segment based on the angle
            labelX = 0;
            labelY = (RING_LABEL_RADIUS * sin(RADIANS(90))) + (labelSize.height * LABEL_HEIGHT_CORRECTION) + (LABEL_BOX_BORDER_Y * 4);
         }
         // Regular Segments
         else
         {
            // Start by setting the basic points for the current segment based on the angle
            labelX = RING_LABEL_RADIUS * cos(RADIANS(angleCenter));
            labelY = RING_LABEL_RADIUS * sin(RADIANS(angleCenter));
         }

         //DebugLog(@"labelX %f | labelY %f | labelSize %f %f", labelX, labelY, labelSize.height, labelSize.width);

         // If labelX = 0, the text must appear centered
         if (labelX > -1.0 && labelX < 1.0)
         {
            labelX -= (labelSize.width / 2);
         } 
         // If labelX > 0, account only for the label border
         else if (labelX >= 1.0)
         {
            labelX += LABEL_BOX_BORDER_X;
         }
         // If labelX < 0, account for label border and right justify
         else 
         {
            labelX -= labelSize.width + LABEL_BOX_BORDER_X;
         }

         // If labelY < 0, account for the label height
         if (labelY > -1.0 && labelY < 1.0)
         {
            labelY -= (labelSize.height * LABEL_HEIGHT_CORRECTION) / 2;
         }
         else if (labelY >= 1.0)
         {
            labelY += LABEL_BOX_BORDER_Y;
         }
         else
         {
            labelY -= (labelSize.height * LABEL_HEIGHT_CORRECTION) + LABEL_BOX_BORDER_Y;
         }

         //DebugLog(@"labelX %f | labelY %f | labelSize %f %f", labelX, labelY, labelSize.height, labelSize.width);

         // Finally, place the location relative to the center of the ring.
         pRingContainer->label[i].location.x = centerX + labelX;
         pRingContainer->label[i].location.y = centerY + labelY;

         // Create the label box
         pRingContainer->label[i].pLabelBox = [[NSBezierPath alloc] init];

         [pRingContainer->label[i].pLabelBox appendBezierPathWithRoundedRect: 
                                                NSMakeRect(pRingContainer->label[i].location.x - LABEL_BOX_BORDER_X,
                                                           pRingContainer->label[i].location.y - LABEL_BOX_BORDER_Y,
                                                           labelSize.width  + (LABEL_BOX_BORDER_X * 2),
                                                           (labelSize.height * LABEL_HEIGHT_CORRECTION) + (LABEL_BOX_BORDER_Y * 2))
                                                xRadius: LABEL_BOX_ROUND 
                                                yRadius: LABEL_BOX_ROUND];

      //}

      angleCenter -= spanAngle;
   }
}

+ (int) arrowSegmentHitTest: (unsigned int) arrowBitfield: (int) segments;
{
   // Arrow bitfield definition:
   #define ARROW_LEFT  (1 << 0)
   #define ARROW_RIGHT (1 << 1)
   #define ARROW_DOWN  (1 << 2)
   #define ARROW_UP    (1 << 3)
   
   unsigned int segment = -1;
   
   // Subtract off the scroll segments, right now those cannot be arrow activated
   segments -= 2;
   
   DebugLog(@"arrowBitfield = %i, segments = %i", arrowBitfield, segments);
   
   switch (segments)
   {
      case 1:
         segment = 0;
         break;
         
      case 2:
         if (ARROW_UP == arrowBitfield)
         {
            segment = 0;
         }
         else if (ARROW_DOWN == arrowBitfield)
         {
            segment = 1;
         }
         break;
         
      case 3:
         if (ARROW_UP == arrowBitfield)
         {
            segment = 0;
         }
         else if (ARROW_RIGHT == arrowBitfield)
         {
            segment = 1;
         }
         else if (ARROW_LEFT == arrowBitfield)
         {
            segment = 2;
         }         
         break;
         
      case 4:
         if (ARROW_UP == arrowBitfield)
         {
            segment = 0;
         }
         else if (ARROW_RIGHT == arrowBitfield)
         {
            segment = 1;
         }
         else if (ARROW_DOWN == arrowBitfield)
         {
            segment = 2;
         }
         else if (ARROW_LEFT == arrowBitfield)
         {
            segment = 3;
         }                  
         break;
         
      case 5:
         if (ARROW_UP == arrowBitfield)
         {
            segment = 0;
         }
         else if ((ARROW_UP | ARROW_RIGHT) == arrowBitfield)
         {
            segment = 1;
         }
         else if ((ARROW_DOWN | ARROW_RIGHT) == arrowBitfield)
         {
            segment = 2;
         }
         else if ((ARROW_DOWN | ARROW_LEFT) == arrowBitfield)
         {
            segment = 3;
         }                           
         else if ((ARROW_UP | ARROW_LEFT) == arrowBitfield)
         {
            segment = 4;
         }                                    
         break;
         
      case 6:
         if (ARROW_UP == arrowBitfield)
         {
            segment = 0;
         }
         else if ((ARROW_UP | ARROW_RIGHT) == arrowBitfield)
         {
            segment = 1;
         }
         else if ((ARROW_DOWN | ARROW_RIGHT) == arrowBitfield)
         {
            segment = 2;
         }
         else if (ARROW_DOWN == arrowBitfield)
         {
            segment = 3;
         }         
         else if ((ARROW_DOWN | ARROW_LEFT) == arrowBitfield)
         {
            segment = 4;
         }                           
         else if ((ARROW_UP | ARROW_LEFT) == arrowBitfield)
         {
            segment = 5;
         }                                    
         break;
   }
   
   return segment;
}

+ (bool) isPointInAngle: (NSPoint) location: (PathElements) path
{
   float pointAngle;

   // Calculate the arctan, and normalize to a positive angle
   pointAngle = DEGREES(atan2(location.y, location.x));

   if (pointAngle < 0)
   {
      pointAngle = 360 + pointAngle;
   }

   // Normal case, start angle less than end angle
   if (path.angleStart < path.angleEnd)
   {
      DebugLog(@"hitDetect - normal case! point angle: %f segstart: %i segend: %i", 
            pointAngle, path.angleStart, path.angleEnd);

      if (pointAngle >= path.angleStart && pointAngle < path.angleEnd)
      {
         return YES;
      }
   }
   // Wrap around case
   else
   {
      DebugLog(@"hitDetect - wrap case! point angle: %f segstart: %i segend: %i", 
            pointAngle, path.angleStart, path.angleEnd);

      if (pointAngle >= path.angleStart || pointAngle < path.angleEnd)
      {
         return YES;
      }
   }

   return NO;
}

@end
