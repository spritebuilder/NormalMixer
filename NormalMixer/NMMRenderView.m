//
//  NMMRenderView.m
//  NormalMapMerge
//
//  Created by Thayer J Andrews on 10/15/14.
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import "NMMRenderView.h"

typedef struct ComputeProgramState
{
    GLuint program;
    GLuint vao;
    GLuint normalScaleLoc;
    
} ComputeProgramState;

typedef struct DisplayProgramState
{
    GLuint program;
    GLuint vao;
    GLuint positionScaleLoc;
    GLuint positionOffsetLoc;
    
} DisplayProgramState;

typedef struct Vertex
{
    GLfloat x,y;
    GLfloat s,t;
} Vertex;

typedef struct FBOState
{
    GLuint fbo;
    GLuint texture;
    CGSize size;
} FBOState;

static NSString* shaderVersionStringFromGLSLVersion(const GLubyte *glslVersion);
static void loadTextureFromImage(GLuint texture, NSImage *image);
static NSBitmapImageRep* bitmapImageRepFromImage(NSImage *image);
static ComputeProgramState setupComputeProgramWithVBO(GLuint vbo, NSString *shaderVersionString);
static DisplayProgramState setupDisplayProgramWithVBO(GLuint vbo, NSString *shaderVersionString);
static GLuint loadProgramWithBasenameAndVersion(NSString *basename, NSString *version);
static GLuint createProgramFromShaders(GLuint vtxShader, GLuint fragShader);
static GLuint compileShaderOfType(GLenum shaderType, NSString *shaderSource);
static GLuint createVAOForProgram(GLuint vbo, GLuint positionLoc, GLuint texCoordLoc);
static GLuint createTextureWithSize(CGSize size);
static GLuint createFBOWithTexture(GLuint texture);
static void bindTextureAsFBOStorage(GLuint fbo, GLuint texture);


static Vertex vertexData[] =
{
    {  0.0f,  0.0f,   0.0f, 0.0f },
    {  0.0f,  1.0f,   0.0f, 1.0f },
    {  1.0f,  1.0f,   1.0f, 1.0f },

    {  0.0f,  0.0f,   0.0f, 0.0f },
    {  1.0f,  1.0f,   1.0f, 1.0f },
    {  1.0f,  0.0f,   1.0f, 0.0f }
};

@interface NMMRenderView ()

@property (nonatomic, assign) float normalScale;

@property (nonatomic, assign) NSRect viewportRect;

@property (nonatomic, assign) ComputeProgramState computeProgram;
@property (nonatomic, assign) DisplayProgramState displayProgram;

@property (nonatomic, assign) GLuint baseTexture;
@property (nonatomic, assign) CGSize baseTextureSize;
@property (nonatomic, assign) GLuint detailTexture;
@property (nonatomic, assign) CGSize detailTextureSize;

@property (nonatomic, assign) FBOState offscreenRT;

@end


@implementation NMMRenderView

#pragma mark - NSOpenGLView overrides

- (id)initWithFrame:(NSRect)frame
{
    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
        // Must specify the 3.2 Core Profile to use OpenGL 3.2
#if NMM_SUPPORT_GL3
        NSOpenGLPFAOpenGLProfile,
        NSOpenGLProfileVersion3_2Core,
#endif
        0
    };
    
    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    NSAssert(pf, @"No OpenGL pixel format matches requested attributes.");
    
    self = [super initWithFrame:frame pixelFormat:pf];
    if (self)
    {
        [self initGL];
    }
    return self;
}

- (void)prepareOpenGL
{
    [super prepareOpenGL];
}

- (void)reshape
{
    [super reshape];
    
    // Get the view size in Points
    NSRect viewRectPoints = [self bounds];
    
#if NMM_SUPPORT_RETINA_RESOLUTION
    
    // Rendering at retina resolutions will reduce aliasing, but at the potential
    // cost of framerate and battery life due to the GPU needing to render more
    // pixels.
    
    // Any calculations the renderer does which use pixel dimentions, must be
    // in "retina" space.  [NSView convertRectToBacking] converts point sizes
    // to pixel sizes.  Thus the renderer gets the size in pixels, not points,
    // so that it can set it's viewport and perform and other pixel based
    // calculations appropriately.
    // viewRectPixels will be larger (2x) than viewRectPoints for retina displays.
    // viewRectPixels will be the same as viewRectPoints for non-retina displays
    self.viewportRect = [self convertRectToBacking:viewRectPoints];
    
#else
    
    // App will typically render faster and use less power rendering at
    // non-retina resolutions since the GPU needs to render less pixels.  There
    // is the cost of more aliasing, but it will be no-worse than on a Mac
    // without a retina display.
    
    // Points:Pixels is always 1:1 when not supporting retina resolutions
    self.viewportRect = viewRectPoints;
    
#endif
    
    [[self openGLContext] makeCurrentContext];
    glViewport(0, 0, self.viewportRect.size.width, self.viewportRect.size.height);
}


#pragma mark - NSOView overrides

- (void)renewGState
{
    // Called whenever graphics state updated (such as window resize)
    
    // OpenGL rendering is not synchronous with other rendering on the OSX.
    // Therefore, call disableScreenUpdatesUntilFlush so the window server
    // doesn't render non-OpenGL content in the window asynchronously from
    // OpenGL content, which could cause flickering.  (non-OpenGL content
    // includes the title bar and drawing done by the app with other APIs)
    [[self window] disableScreenUpdatesUntilFlush];
    
    [super renewGState];
}

- (void)drawRect:(NSRect)theRect
{
    // Called during resize operations.
    // Avoid flickering during resize by drawiing
    [self drawView];
}


#pragma mark - API

- (void)setBaseTextureFromImage:(NSImage *)image
{
    loadTextureFromImage(self.baseTexture, image);
    self.baseTextureSize = image.size;
}

- (void)setDetailTextureFromImage:(NSImage *)image
{
    loadTextureFromImage(self.detailTexture, image);
    self.detailTextureSize = image.size;
}

- (void)setNormalScaleValue:(float)scale
{
    self.normalScale = scale;
}

- (void)refresh
{
    if (CGSizeEqualToSize(self.baseTextureSize, CGSizeZero) ||
        CGSizeEqualToSize(self.detailTextureSize, CGSizeZero))
    {
        return;
    }
    
    if (!CGSizeEqualToSize(self.baseTextureSize, self.detailTextureSize))
    {
        NSLog(@"Warning, the base texture and detail texture aren't the same size. The results are undefined.");
    }
    
    if (!self.offscreenRT.fbo)
    {
        FBOState offscreenRT;
        offscreenRT.size = self.baseTextureSize;
        offscreenRT.texture = createTextureWithSize(offscreenRT.size);
        offscreenRT.fbo = createFBOWithTexture(offscreenRT.texture);
        self.offscreenRT = offscreenRT;
    }
    else if (!CGSizeEqualToSize(self.baseTextureSize, self.offscreenRT.size))
    {
        FBOState offscreenRT = self.offscreenRT;
        offscreenRT.size = self.baseTextureSize;
        offscreenRT.texture = createTextureWithSize(offscreenRT.size);
        bindTextureAsFBOStorage(offscreenRT.fbo, offscreenRT.texture);
        self.offscreenRT = offscreenRT;
    }
    [self recomputeNormals];
    [self setNeedsDisplay:YES];
}

- (NSBitmapImageRep *)imageRepForComputedNormals
{
    NSBitmapImageRep *imageRep = nil;
    if (self.offscreenRT.fbo)
    {
        // Get the current FBO binding
        GLint oldFBO;
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &oldFBO);
        
        // Bind the offscreen render target's FBO
        glBindFramebuffer(GL_FRAMEBUFFER, self.offscreenRT.fbo);
        
        // Read the FBO pixels into readbackBuffer
        GLsizei bufferSize = self.offscreenRT.size.width * self.offscreenRT.size.height * 4;
        GLubyte *readbackBuffer = malloc(bufferSize);
        glReadPixels(0, 0, self.offscreenRT.size.width, self.offscreenRT.size.height, GL_RGBA, GL_UNSIGNED_BYTE, readbackBuffer);
        
        // Restore the old FBO binding.
        glBindFramebuffer(GL_FRAMEBUFFER, oldFBO);
        
        // Create a bitmap image rep from the readback pixels
        imageRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&(readbackBuffer)
                                                           pixelsWide:self.offscreenRT.size.width
                                                           pixelsHigh:self.offscreenRT.size.height
                                                        bitsPerSample:8
                                                      samplesPerPixel:4
                                                             hasAlpha:YES
                                                             isPlanar:NO
                                                       colorSpaceName:NSCalibratedRGBColorSpace
                                                         bitmapFormat:NSAlphaNonpremultipliedBitmapFormat
                                                          bytesPerRow:4 * self.offscreenRT.size.width
                                                         bitsPerPixel:32];
        
        free(readbackBuffer);
    }
    return imageRep;
}

#pragma mark - Private

- (void)initGL
{
    // The reshape function may have changed the thread to which our OpenGL
    // context is attached before prepareOpenGL and initGL are called.  So call
    // makeCurrentContext to ensure that our OpenGL context current to this
    // thread (i.e. makeCurrentContext directs all OpenGL calls on this thread
    // to [self openGLContext])
    [[self openGLContext] makeCurrentContext];
    
    // Synchronize buffer swaps with vertical refresh rate
    GLint swapInt = 1;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
    
    const GLubyte *vendor = glGetString(GL_VENDOR);
    const GLubyte *renderer = glGetString(GL_RENDERER);
    const GLubyte *version = glGetString(GL_VERSION);
    const GLubyte *glslVersion = glGetString(GL_SHADING_LANGUAGE_VERSION);
    
    NSLog(@"   GL_VENDOR: %s", vendor);
    NSLog(@" GL_RENDERER: %s", renderer);
    NSLog(@"  GL_VERSION: %s", version);
    NSLog(@"GLSL_VERSION: %s", glslVersion);
    
    FBOState offscreenRT;
    offscreenRT.fbo = 0;
    offscreenRT.texture = 0;
    offscreenRT.size = CGSizeZero;
    self.offscreenRT = offscreenRT;
    
    NSString *shaderVersionString = shaderVersionStringFromGLSLVersion(glslVersion);

    // Create and load the VBO with vertex data
    GLuint vertexDataBuffer;
    glGenBuffers(1, &vertexDataBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexDataBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertexData), vertexData, GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    
    // Compute program setup
    self.computeProgram = setupComputeProgramWithVBO(vertexDataBuffer, shaderVersionString);
    
    // Display program setup
    self.displayProgram = setupDisplayProgramWithVBO(vertexDataBuffer, shaderVersionString);
    
    // Texture setup
    const GLuint numTextures = 2;
    GLuint textures[numTextures];
    for (int t = 0; t < numTextures; t++)
    {
        glGenTextures(1, &textures[t]);
        glBindTexture(GL_TEXTURE_2D, textures[t]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    
    self.baseTexture = textures[0];
    self.detailTexture = textures[1];

    // Misc render state
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);
    glDisable(GL_CULL_FACE);
}

- (void)drawView
{
    [self.openGLContext makeCurrentContext];
    if (self.offscreenRT.texture)
    {
        [self drawNormals];
    }
    else
    {
        // Bind the primary render target
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, self.viewportRect.size.width, self.viewportRect.size.height);
        
        // Clear the render target
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    CGLFlushDrawable([self.openGLContext CGLContextObj]);
}

- (void)drawNormals
{
    float imageAspect = self.offscreenRT.size.width / self.offscreenRT.size.height;
    float windowAspect = self.viewportRect.size.width / self.viewportRect.size.height;

    CGAffineTransform transform = CGAffineTransformIdentity;
    if (windowAspect > imageAspect)
    {
        transform = CGAffineTransformScale(transform, 1.0f / windowAspect, 1.0f);
    }
    else
    {
        transform = CGAffineTransformScale(transform, 1.0f, windowAspect);
    }
    transform = CGAffineTransformTranslate(transform, -1.0f, -1.0f);
    transform = CGAffineTransformScale(transform, 2.0f, 2.0f);
    transform = CGAffineTransformScale(transform, imageAspect, 1.0f);
    
    // Bind the primary render target
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(0, 0, self.viewportRect.size.width, self.viewportRect.size.height);
    
    // Clear the render target
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    // Bind the offscreen render target's backing texture to texture
    // unit 0.
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, self.offscreenRT.texture);
    
    glUseProgram(self.displayProgram.program);
    glUniform2f(self.displayProgram.positionScaleLoc, transform.a, transform.d);
    glUniform2f(self.displayProgram.positionOffsetLoc, transform.tx, transform.ty);
    
    // Bind the VAO and draw
    glBindVertexArray(self.displayProgram.vao);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glBindVertexArray(0);
}

- (void)recomputeNormals
{
    // Bind the offscreen render target and set the correct viewport
    glBindFramebuffer(GL_FRAMEBUFFER, self.offscreenRT.fbo);
    glViewport(0, 0, self.offscreenRT.size.width, self.offscreenRT.size.height);
    
    // Clear the render target
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    // Bind the base and detail maps to texture units 0 and 1
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, self.baseTexture);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, self.detailTexture);
    
    // Use the compute program
    glUseProgram(self.computeProgram.program);
    glUniform1f(self.computeProgram.normalScaleLoc, self.normalScale);

    // Bind the VAO and draw
    glBindVertexArray(self.computeProgram.vao);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glBindVertexArray(0);
}

@end

NSString* shaderVersionStringFromGLSLVersion(const GLubyte *glslVersion)
{
    NSString *decimalVersionString = [[NSString alloc] initWithCString:(const char*)glslVersion encoding:NSASCIIStringEncoding];
    NSArray *versionParts = [decimalVersionString componentsSeparatedByString:@"."];
    NSCAssert(versionParts.count == 2, @"GLSL version has an unexpected format.");
    
    return [[NSString alloc] initWithFormat:@"%@%@", versionParts[0], versionParts[1]];
}

void loadTextureFromImage(GLuint texture, NSImage *image)
{
    NSBitmapImageRep *bitmap = bitmapImageRepFromImage(image);
    
    // Set proper unpacking row length for bitmap.
    glPixelStorei(GL_UNPACK_ROW_LENGTH, (GLint)[bitmap pixelsWide]);
    
    // Set byte aligned unpacking (needed for 3 byte per pixel bitmaps).
    glPixelStorei (GL_UNPACK_ALIGNMENT, 1);
    
    glBindTexture (GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, image.size.width, image.size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, [bitmap bitmapData]);
}

NSBitmapImageRep* bitmapImageRepFromImage(NSImage *image)
{
    int width = image.size.width;
    int height = image.size.height;
    
    if(width < 1 || height < 1)
    {
        return nil;
    }
    
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                             initWithBitmapDataPlanes: NULL
                             pixelsWide: width
                             pixelsHigh: height
                             bitsPerSample: 8
                             samplesPerPixel: 4
                             hasAlpha: YES
                             isPlanar: NO
                             colorSpaceName: NSDeviceRGBColorSpace
                             bytesPerRow: width * 4
                             bitsPerPixel: 32];
    
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: ctx];
    [image drawAtPoint: NSZeroPoint fromRect: NSZeroRect operation: NSCompositeCopy fraction: 1.0];
    [ctx flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
    
    return rep;
}

ComputeProgramState setupComputeProgramWithVBO(GLuint vbo, NSString *shaderVersionString)
{
    ComputeProgramState computeProgram;
    computeProgram.program = loadProgramWithBasenameAndVersion(@"NMMComputeDeltas", shaderVersionString);
    
    glUseProgram(computeProgram.program);
    glUniform1i(glGetUniformLocation(computeProgram.program, "baseTexture"), 0);
    glUniform1i(glGetUniformLocation(computeProgram.program, "detailTexture"), 1);
    computeProgram.normalScaleLoc = glGetUniformLocation(computeProgram.program, "normalScale");
    
    GLint computePositionLoc = glGetAttribLocation(computeProgram.program, "inPosition");
    GLint computeTexCoordLoc = glGetAttribLocation(computeProgram.program, "inTexCoord");
    computeProgram.vao = createVAOForProgram(vbo, computePositionLoc, computeTexCoordLoc);
    
    return computeProgram;
}

DisplayProgramState setupDisplayProgramWithVBO(GLuint vbo, NSString *shaderVersionString)
{
    DisplayProgramState displayProgram;
    displayProgram.program = loadProgramWithBasenameAndVersion(@"NMMDisplayResults", shaderVersionString);
    
    glUseProgram(displayProgram.program);
    glUniform1i(glGetUniformLocation(displayProgram.program, "baseTexture"), 0);
    displayProgram.positionScaleLoc = glGetUniformLocation(displayProgram.program, "positionScale");
    displayProgram.positionOffsetLoc = glGetUniformLocation(displayProgram.program, "positionOffset");
    
    
    GLint displayPositionLoc = glGetAttribLocation(displayProgram.program, "inPosition");
    GLint displayTexCoordLoc = glGetAttribLocation(displayProgram.program, "inTexCoord");
    displayProgram.vao = createVAOForProgram(vbo, displayPositionLoc, displayTexCoordLoc);
    
    return displayProgram;
}

GLuint loadProgramWithBasenameAndVersion(NSString *basename, NSString *version)
{
    NSString *versionedShaderName = [basename stringByAppendingString:version];
    
    NSURL *vtxShaderURL = [[NSBundle mainBundle] URLForResource:versionedShaderName withExtension:@"vsh"];
    NSString *vtxShaderSource = [[NSString alloc] initWithContentsOfURL:vtxShaderURL encoding:NSASCIIStringEncoding error:nil];
    GLuint vtxShader = compileShaderOfType(GL_VERTEX_SHADER, vtxShaderSource);
    
    NSURL *fragShaderURL = [[NSBundle mainBundle] URLForResource:versionedShaderName withExtension:@"fsh"];
    NSString *fragShaderSource = [[NSString alloc] initWithContentsOfURL:fragShaderURL encoding:NSASCIIStringEncoding error:nil];
    GLuint fragShader = compileShaderOfType(GL_FRAGMENT_SHADER, fragShaderSource);
    
    GLuint program = createProgramFromShaders(vtxShader, fragShader);

    glDeleteShader(vtxShader);
    glDeleteShader(fragShader);
    
    return program;
}

GLuint createProgramFromShaders(GLuint vtxShader, GLuint fragShader)
{
    GLuint program = glCreateProgram();
    glAttachShader(program, vtxShader);
    glAttachShader(program, fragShader);
    glLinkProgram(program);
    
    GLint linkStatus;
    glGetProgramiv(program, GL_LINK_STATUS, &linkStatus);
    if (!linkStatus)
    {
        NSLog(@"Program link failed");
        
        GLint logLength;
        glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
        if (logLength > 0)
        {
            GLchar *log = (GLchar*) malloc(logLength);
            glGetProgramInfoLog(program, logLength, &logLength, log);
            NSLog(@"Program link log:%s\n", log);
            free(log);
        }
        
        glDeleteProgram(program);
        program = 0;
    }
    
    return program;
}

GLuint compileShaderOfType(GLenum shaderType, NSString *shaderSource)
{
    const char *shaderString = shaderSource.UTF8String;
    
    GLuint shader = glCreateShader(shaderType);
    glShaderSource(shader, 1, &shaderString, 0);
    glCompileShader(shader);
    
    GLint compileStatus;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compileStatus);
    if (!compileStatus)
    {
        NSLog(@"Shader compilation failed.");
        
        GLint shaderLogLength;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &shaderLogLength);
        if (shaderLogLength > 0)
        {
            GLchar *shaderLog = (GLchar*) malloc(shaderLogLength);
            glGetShaderInfoLog(shader, shaderLogLength, &shaderLogLength, shaderLog);
            NSLog(@"Shader compile log:%s\n", shaderLog);
            free(shaderLog);
            NSCAssert(0, @"Shader compilation failed.");
        }
    }
    
    return shader;
}

GLuint createVAOForProgram(GLuint vbo, GLuint positionLoc, GLuint texCoordLoc)
{
    GLuint vao;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glEnableVertexAttribArray(positionLoc);
    glVertexAttribPointer(positionLoc, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), 0);
    glEnableVertexAttribArray(texCoordLoc);
    glVertexAttribPointer(texCoordLoc, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)(offsetof(Vertex, s)));
    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    return vao;
}

GLuint createTextureWithSize(CGSize size)
{
    // Allocate an empty texture as the backing store for the FBO
    GLuint fboTexture;
    glGenTextures(1, &fboTexture);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, fboTexture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, size.width, size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    return fboTexture;
}

GLuint createFBOWithTexture(GLuint texture)
{
    // Get the current FBO binding
    GLint oldFBO;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &oldFBO);
    
    // FBO setup
    GLuint fbo;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    
    // Associate the texture with the FBO
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    
    // Check that the FBO is valid
    NSCAssert( glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, @"Could not attach texture to framebuffer");
    
    // Restore the old FBO binding.
    glBindFramebuffer(GL_FRAMEBUFFER, oldFBO);
    
    return fbo;
}

void bindTextureAsFBOStorage(GLuint fbo, GLuint texture)
{
    NSCAssert(fbo, @"Invalid fbo");
    NSCAssert(texture, @"Invalid texture");
    
    // Get the current FBO binding
    GLint oldFBO;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &oldFBO);

    // Bind the texture to the FBO.
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    
    // Check that the FBO is valid
    NSCAssert( glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, @"Could not attach texture to framebuffer");
    
    // Restore the old FBO binding.
    glBindFramebuffer(GL_FRAMEBUFFER, oldFBO);
}


