/**
 * clang++ main.mm -framework Cocoa -framework OpenGL -framework IOSurface -o test && ./test
 **/

#include "VTDecoder.h"
#include "MemUtils.h"

@implementation TestView

- (id)initWithFrame:(NSRect)aFrame
{
  if (self = [super initWithFrame:aFrame]) {
    NSOpenGLPixelFormatAttribute attribs[] = {
        NSOpenGLPFAAccelerated,
        NSOpenGLPFADoubleBuffer,
        (NSOpenGLPixelFormatAttribute)0
    };
    NSOpenGLPixelFormat* pixelFormat = [[[NSOpenGLPixelFormat alloc] initWithAttributes:attribs] autorelease];
    mContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
    GLint swapInt = 1;
    [mContext setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
    GLint opaque = 1;
    [mContext setValues:&opaque forParameter:NSOpenGLCPSurfaceOpacity];
    [mContext makeCurrentContext];
    [self _initGL];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_surfaceNeedsUpdate:)
                                                 name:NSViewGlobalFrameDidChangeNotification
                                               object:self];
    mDecoder = new VTDecoder(self);
    mStarted = false;
  }
  return self;
}

- (void)dealloc
{
  [self _cleanupGL];
  [mContext release];
  [super dealloc];
  delete mDecoder;
}

static GLuint
CompileShaders(const char* vertexShader, const char* fragmentShader)
{
  // Create the shaders
  GLuint vertexShaderID = glCreateShader(GL_VERTEX_SHADER);
  GLuint fragmentShaderID = glCreateShader(GL_FRAGMENT_SHADER);

  GLint result = GL_FALSE;
  int infoLogLength;

  // Compile Vertex Shader
  glShaderSource(vertexShaderID, 1, &vertexShader , NULL);
  glCompileShader(vertexShaderID);

  // Check Vertex Shader
  glGetShaderiv(vertexShaderID, GL_COMPILE_STATUS, &result);
  glGetShaderiv(vertexShaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* vertexShaderErrorMessage = new char[infoLogLength+1];
    glGetShaderInfoLog(vertexShaderID, infoLogLength, NULL, vertexShaderErrorMessage);
    printf("%s\n", vertexShaderErrorMessage);
    delete[] vertexShaderErrorMessage;
  }

  // Compile Fragment Shader
  glShaderSource(fragmentShaderID, 1, &fragmentShader , NULL);
  glCompileShader(fragmentShaderID);

  // Check Fragment Shader
  glGetShaderiv(fragmentShaderID, GL_COMPILE_STATUS, &result);
  glGetShaderiv(fragmentShaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* fragmentShaderErrorMessage = new char[infoLogLength+1];
    glGetShaderInfoLog(fragmentShaderID, infoLogLength, NULL, fragmentShaderErrorMessage);
    printf("%s\n", fragmentShaderErrorMessage);
    delete[] fragmentShaderErrorMessage;
  }

  // Link the program
  GLuint programID = glCreateProgram();
  glAttachShader(programID, vertexShaderID);
  glAttachShader(programID, fragmentShaderID);
  glLinkProgram(programID);

  // Check the program
  glGetProgramiv(programID, GL_LINK_STATUS, &result);
  glGetProgramiv(programID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* programErrorMessage = new char[infoLogLength+1];
    glGetProgramInfoLog(programID, infoLogLength, NULL, programErrorMessage);
    printf("%s\n", programErrorMessage);
    delete[] programErrorMessage;
  }

  glDeleteShader(vertexShaderID);
  glDeleteShader(fragmentShaderID);

  return programID;
}

- (void)upload:(IOSurfaceRef)surface
{
    GLsizei width = (GLsizei)IOSurfaceGetWidth(surface);
    GLsizei height = (GLsizei)IOSurfaceGetHeight(surface);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, mTexture);

    CGLError err = CGLTexImageIOSurface2D([mContext CGLContextObj],
                                          GL_TEXTURE_RECTANGLE_ARB, GL_RGB, width, height,
                                          GL_YCBCR_422_APPLE, GL_UNSIGNED_SHORT_8_8_APPLE, surface, 0);

    if (err != kCGLNoError) {
        NSLog(@"GL error=%d", (int)err);
        return;
    }
    [self drawme];
}

- (void)drawme
{
    [mContext setView:self];
    [mContext makeCurrentContext];

    NSSize backingSize = [self convertSizeToBacking:[self bounds].size];
    GLdouble width = backingSize.width;
    GLdouble height = backingSize.height;
    glViewport(0, 0, width, height);

    glClearColor(0.0, 1.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(mProgramID);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, mTexture);
    glUniform1i(mTextureUniform, 0);

    glEnableVertexAttribArray(mPosAttribute);
    glBindBuffer(GL_ARRAY_BUFFER, mVertexbuffer);
    glVertexAttribPointer(
                          mPosAttribute, // The attribute we want to configure
                          2,             // size
                          GL_FLOAT,      // type
                          GL_FALSE,      // normalized?
                          0,             // stride
                          (void*)0       // array buffer offset
                          );

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); // 4 indices starting at 0 -> 2 triangles

    glDisableVertexAttribArray(mPosAttribute);

    [mContext flushBuffer];
}

static GLuint
CreateTextureThroughIOSurface(NSSize size, CGLContextObj cglContextObj, void (^drawCallback)(CGContextRef ctx))
{
  int width = size.width;
  int height = size.height;

  NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
                         [NSNumber numberWithInt:width], kIOSurfaceWidth,
                         [NSNumber numberWithInt:height], kIOSurfaceHeight,
                         [NSNumber numberWithInt:4], kIOSurfaceBytesPerElement,
                         // [NSNumber numberWithBool:YES], kIOSurfaceIsGlobal,
                         nil];

  AutoCFRelease<IOSurfaceRef> surf = IOSurfaceCreate((CFDictionaryRef)dict);
  IOSurfaceLock(surf, 0, NULL);
  void* data = IOSurfaceGetBaseAddress(surf);
  size_t stride = IOSurfaceGetBytesPerRow(surf);

  CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
  CGContextRef imgCtx = CGBitmapContextCreate(data, width, height, 8, stride,
                                              rgb, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(rgb);
  drawCallback(imgCtx);

  IOSurfaceUnlock(surf, 0, NULL);

  GLuint texture = 0;
  glActiveTexture(GL_TEXTURE0);
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texture);

  CGLTexImageIOSurface2D(cglContextObj, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA, width, height,
                         GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, surf, 0);

  return texture;
}

- (void)_initGL
{
  // Create and compile our GLSL program from the shaders.
  mProgramID = CompileShaders(
    "#version 120\n"
    "// Input vertex data, different for all executions of this shader.\n"
    "attribute vec2 aPos;\n"
    "varying vec2 vPos;\n"
    "void main(){\n"
    "  vPos = aPos;\n"
    "  gl_Position = vec4(aPos.x * 2.0 - 1.0, 1.0 - aPos.y * 2.0, 0.0, 1.0);\n"
    "}\n",

    "#version 120\n"
    "varying vec2 vPos;\n"
    "uniform sampler2DRect uSampler;\n"
    "void main()\n"
    "{\n"
    "  gl_FragColor = texture2DRect(uSampler, vPos * vec2(1120, 626));\n" // <-- ATTENTION I HARDCODED THE TEXTURE SIZE HERE SORRY ABOUT THAT
    "}\n");

  // Create a texture
  mTexture = CreateTextureThroughIOSurface(NSMakeSize(1120, 626), [mContext CGLContextObj], ^(CGContextRef ctx) {
    // Clear with white.
    CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, 1120, 626));

    // Draw a bunch of circles.
    for (int i = 0; i < 30; i++) {
      CGFloat radius = 20.0f + 4.0f * i;
      CGFloat angle = i * 1.1;
      CGPoint circleCenter = { 560 + radius * cos(angle), 313 + radius * sin(angle) };
      CGFloat circleRadius = 10;
      CGContextSetRGBFillColor(ctx, 0, i % 2, 1 - (i % 2), 1);
      CGContextFillEllipseInRect(ctx, CGRectMake(circleCenter.x - circleRadius, circleCenter.y - circleRadius, circleRadius * 2, circleRadius * 2));
    }
  });
  mTextureUniform = glGetUniformLocation(mProgramID, "uSampler");

  // Get a handle for our buffers
  mPosAttribute = glGetAttribLocation(mProgramID, "aPos");

  static const GLfloat g_vertex_buffer_data[] = {
     0.0f,  0.0f,
     1.0f,  0.0f,
     0.0f,  1.0f,
     1.0f,  1.0f,
  };

  glGenBuffers(1, &mVertexbuffer);
  glBindBuffer(GL_ARRAY_BUFFER, mVertexbuffer);
  glBufferData(GL_ARRAY_BUFFER, sizeof(g_vertex_buffer_data), g_vertex_buffer_data, GL_STATIC_DRAW);
}

- (void)_cleanupGL
{
  glDeleteTextures(1, &mTexture);
  glDeleteBuffers(1, &mVertexbuffer);
}

- (void)_surfaceNeedsUpdate:(NSNotification*)notification
{
  [mContext update];
}

- (void)drawRect:(NSRect)aRect
{
    [self drawme];
    if (!mStarted) {
        mStarted = true;
        mDecoder->Start();
    }
}

- (BOOL)wantsBestResolutionOpenGLSurface
{
  return YES;
}

@end

@interface TerminateOnClose : NSObject<NSWindowDelegate>
@end

@implementation TerminateOnClose
- (void)windowWillClose:(NSNotification*)notification
{
  [NSApp terminate:self];
}
@end

int
main (int argc, char **argv)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  int style =
    NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask | NSMiniaturizableWindowMask;
  NSRect contentRect = NSMakeRect(400, 300, 600, 400);
  NSWindow* window = [[NSWindow alloc] initWithContentRect:contentRect
                                       styleMask:style
                                         backing:NSBackingStoreBuffered
                                           defer:NO];

  NSView* view = [[TestView alloc] initWithFrame:NSMakeRect(0, 0, contentRect.size.width, contentRect.size.height)];

  [window setContentView:view];
  [window setDelegate:[[TerminateOnClose alloc] autorelease]];
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:window];

  [NSApp run];

  [pool release];

  return 0;
}
