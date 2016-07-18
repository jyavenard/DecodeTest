//
//  main.h
//  DecodeTest
//
//  Created by Jean-Yves Avenard on 17/06/2016.
//  Copyright © 2016 Mozilla. All rights reserved.
//

#ifndef main_h
#define main_h

#import <Cocoa/Cocoa.h>
#include <OpenGL/gl.h>
#include <atomic>

class VTDecoder;
class MyIOSurfaceRef;

@interface TestView: NSView
{
    NSOpenGLContext* mContext;
    GLuint mProgramID;
    GLuint mTexture;
    GLuint mTextureUniform;
    GLuint mPosAttribute;
    GLuint mVertexbuffer;
    VTDecoder* mDecoder;
    bool mStarted;
    size_t mIndex;
    std::atomic<int> mQueued;
}

- (void)output:(MyIOSurfaceRef*)surface;

@end

#endif /* main_h */
