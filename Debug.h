/*
 *  Debug.h
 *
 *  Copyright 2009 SwiftRing. All rights reserved.
 *
 */

//#define DEBUG_MODE_ON

#ifdef DEBUG_MODE_ON
    #define DebugLog( s, ... ) NSLog( @"<%@:(%d)> %@", [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )
#else
    #define DebugLog( s, ... ) 
#endif
