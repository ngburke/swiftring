//
//  Ring.h
//
//  Copyright 2009 SwiftRing. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#define MAX_RINGS            9
#define MAX_SEGMENTS         10
#define MAX_SCROLL_SEGMENTS  2
#define SCROLL_OFFSET        8
#define SCROLL_UP_SEGMENT    8
#define SCROLL_DOWN_SEGMENT  9
#define MAX_KEYSTROKES       50

typedef enum _RingActionStatus
{
   RING_ACTION_NONE = 0, // No action
   RING_ACTION_DONE,     // Done with the ring
   RING_ACTION_STAY,     // Keep the same ring
   RING_ACTION_REFRESH,  // Need a refresh on the ring
} RingActionStatus;


typedef struct _LabelElements
{
   NSString     *pLabel;
   NSBezierPath *pLabelBox;
   NSPoint       location;
} LabelElements;


typedef struct _ActionElements
{
   int  keyCode[MAX_KEYSTROKES];
   BOOL keyIsDown[MAX_KEYSTROKES];
   // BOOL isVelocityBuffer;
   struct _RingContainer *pNextRing;
} ActionElements;
   
typedef struct _PathElements
{
   NSBezierPath *pPath;
   int           angleStart;  // Must always be positive
   int           angleEnd;    // Must always be positive
} PathElements;


typedef struct _RingContainer
{
   int             numSegments;
   bool            isSubring;
   int             scrollUpSegment;
   int             scrollDownSegment;
   PathElements    path[MAX_SEGMENTS];
   LabelElements   label[MAX_SEGMENTS];
   NSDictionary   *pLabelAttributes;
   struct _ActionElements  action[MAX_SEGMENTS];
} RingContainer;


@interface Ring : NSObject 
{
   float           ringCenterX;
   float           ringCenterY;
   RingContainer   ringContainer[MAX_RINGS];
   RingContainer  *pCurrentRing;
}

- (id)               init: (NSDictionary *) pRingInfo: (float) centerX: (float) centerY;
- (int)              getNumSegments;
- (NSDictionary *)   getLabelAttributes;
- (NSBezierPath *)   getSegmentPath:   (int) segment;
- (LabelElements)    getSegmentLabel:  (int) segment;

- (int)              detectHit:        (NSPoint) location: (float) centerX: (float) centerY: (bool) scrollUp: (bool) scrollDown: (unsigned int) arrowBitfield;
- (RingActionStatus) executeAction:    (int) segment: (int *) pIgnoreKeyEvents;
- (BOOL)             containsNextRing: (int) segment;
// - (BOOL)             isVelocityBuffer: (int) segment;
- (BOOL)             isSubring;

- (void) generatePaths: (RingContainer*) pRingContainer: (int) segments: (float) startAngle: (float) spanAngle: 
                                                         (float) centerX: (float) centerY: (bool) isSubring;

+ (int)  arrowSegmentHitTest: (unsigned int) arrowBitfield: (int) segments;
+ (bool) isPointInAngle: (NSPoint) location: (PathElements) path;
@end
