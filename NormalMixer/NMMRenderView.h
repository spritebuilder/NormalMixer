//
//  NMMRenderView.h
//  NormalMapMerge
//
//  Created by Thayer J Andrews on 10/15/14.
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>

// OpenGL 3.2 is only supported on MacOS X Lion and later
// CGL_VERSION_1_3 is defined as 1 on MacOS X Lion and later
#if CGL_VERSION_1_3
#define NMM_SUPPORT_GL3 1
#else
#define NMM_SUPPORT_GL3 0
#endif //!CGL_VERSION_1_3

#if NMM_SUPPORT_GL3
#import <OpenGL/gl3.h>
#else
#import <OpenGL/gl.h>
#endif


@interface NMMRenderView : NSOpenGLView

- (void)setBaseTextureFromImage:(NSImage *)image;
- (void)setDetailTextureFromImage:(NSImage *)image;
- (void)setNormalScaleValue:(float)scale;
- (void)refresh;
- (NSBitmapImageRep *)imageRepForComputedNormals;

@end
