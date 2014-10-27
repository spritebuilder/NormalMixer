//
//  AppDelegate.m
//  NormalMapMerge
//
//  Created by Thayer J Andrews on 10/15/14.
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import "AppDelegate.h"
#import "NMMWindowController.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (nonatomic, strong) NMMWindowController *mainWindowController;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    self.mainWindowController = [[NMMWindowController alloc] initWithWindowNibName:@"NMMWindowController"];
    [self.mainWindowController showWindow:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

@end
