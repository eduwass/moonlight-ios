//
//  main.m
//  Moonlight TV
//
//  Created by Diego Waxemberg on 8/25/18.
//  Copyright © 2018 Moonlight Game Streaming Project. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SofaAppDelegate.h"
#import "SofaDictation.h"

#define SDL_MAIN_HANDLED
#import <SDL.h>

int main(int argc, char * argv[]) {
    @autoreleasepool {
        [SofaDictation runSelfCheck];
        SDL_SetMainReady();
        [SofaAppDelegate importPairing];
        return UIApplicationMain(argc, argv, NSStringFromClass(SofaApplication.class), NSStringFromClass([SofaAppDelegate class]));
    }
}
