//
//  KeyboardSupport.h
//  Moonlight
//
//  Created by Diego Waxemberg on 8/25/18.
//  Copyright © 2018 Moonlight Game Streaming Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface KeyboardSupport : NSObject

struct KeyEvent {
    u_short keycode;
    u_short modifierKeycode;
    u_char modifier;
};

+ (BOOL)sendKeyEventForPress:(UIPress*)press down:(BOOL)down API_AVAILABLE(ios(13.4));
+ (BOOL)sendKeyEvent:(UIKey*)key down:(BOOL)down API_AVAILABLE(ios(13.4));
+ (BOOL)sendKeyCode:(UIKeyboardHIDUsage)usage modifiers:(UIKeyModifierFlags)modifiers down:(BOOL)down;
+ (struct KeyEvent) translateKeyEvent:(unichar) inputChar withModifierFlags:(UIKeyModifierFlags)modifierFlags;

@end
