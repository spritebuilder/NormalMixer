//
//  NMMWindowController.m
//  NormalMapMerge
//
//  Created by Thayer J Andrews on 10/15/14.
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import "NMMWindowController.h"
#import "NMMRenderView.h"


@interface NMMWindowController ()

@property (nonatomic, weak) IBOutlet NSImageView *baseNormalsView;
@property (nonatomic, weak) IBOutlet NSImageView *detailNormalsView;
@property (nonatomic, weak) IBOutlet NSView *renderViewContainer;
@property (nonatomic, weak) IBOutlet NSTextField *sliderValueField;
@property (nonatomic, strong) NMMRenderView *renderView;
@property (nonatomic, copy) NSURL* saveFileURL;

@end


#pragma mark - NSWindowController overrides

@implementation NMMWindowController

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    NSRect renderFrame = self.renderViewContainer.bounds;
    NMMRenderView *renderView = [[NMMRenderView alloc] initWithFrame:renderFrame];
    self.renderView = renderView;
    [self.renderViewContainer addSubview:self.renderView];
    
    
    
    [self.renderView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.renderViewContainer addConstraints:[NSLayoutConstraint
                                              constraintsWithVisualFormat:@"H:|-0-[renderView]-0-|"
                                              options:NSLayoutFormatDirectionLeadingToTrailing
                                              metrics:nil
                                              views:NSDictionaryOfVariableBindings(renderView)]];
    [self.renderViewContainer addConstraints:[NSLayoutConstraint
                                              constraintsWithVisualFormat:@"V:|-0-[renderView]-0-|"
                                              options:NSLayoutFormatDirectionLeadingToTrailing
                                              metrics:nil
                                              views:NSDictionaryOfVariableBindings(renderView)]];
}

#pragma mark - NSWindowDelegate methods

- (void)windowDidExpose:(NSNotification *)notification
{
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
}

#pragma mark - Actions

- (IBAction)refreshClicked:(id)sender
{
    NSImage *baseImage = self.baseNormalsView.image;
    NSImage *detailImage = self.detailNormalsView.image;
    
    if (baseImage && detailImage)
    {
        [self.renderView setBaseTextureFromImage:baseImage];
        [self.renderView setDetailTextureFromImage:detailImage];
        [self.renderView refresh];
    }
}

- (IBAction)scaleSliderDidMove:(id)sender
{
    NSSlider *slider = (NSSlider *)sender;
    float scaleValue = slider.floatValue;
    
    [self.sliderValueField setFloatValue:scaleValue];
    [self.renderView setNormalScaleValue:scaleValue];
    [self.renderView refresh];
}


#pragma mark - Menu Handling

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if (menuItem.action == @selector(saveDocument:))
    {
        // Disable the save menu if there is nothing to save.
        return ([self.renderView imageRepForComputedNormals] != nil);
    }
    else if (menuItem.action == @selector(saveDocumentAs:))
    {
        // Disable the save as menu if there is nothing to save.
        return ([self.renderView imageRepForComputedNormals] != nil);
    }
    return YES;
}

- (IBAction)saveDocumentAs:(id)sender
{
    NSBitmapImageRep *imageRep = [self.renderView imageRepForComputedNormals];
    if (imageRep)
    {
        NSSavePanel *savePanel = [NSSavePanel savePanel];
        [savePanel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result) {
            if (result == NSFileHandlingPanelOKButton)
            {
                self.saveFileURL = savePanel.URL;
                
                NSData *imageData = [imageRep representationUsingType:NSPNGFileType properties:nil];
                [imageData writeToURL:savePanel.URL atomically:NO];
            }
        }];
    }
}

- (IBAction)saveDocument:(id)sender
{
    NSBitmapImageRep *imageRep = [self.renderView imageRepForComputedNormals];
    if (imageRep)
    {
        if (self.saveFileURL)
        {
            NSData *imageData = [imageRep representationUsingType:NSPNGFileType properties:nil];
            [imageData writeToURL:self.saveFileURL atomically:NO];
        }
        else
        {
            NSSavePanel *savePanel = [NSSavePanel savePanel];
            [savePanel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result) {
                if (result == NSFileHandlingPanelOKButton)
                {
                    self.saveFileURL = savePanel.URL;
                    
                    NSData *imageData = [imageRep representationUsingType:NSPNGFileType properties:nil];
                    [imageData writeToURL:savePanel.URL atomically:NO];
                }
            }];
        }
    }
}


@end
