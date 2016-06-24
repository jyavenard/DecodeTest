//
//  VTDecoder.hpp
//  DecodeTest
//
//  Created by Jean-Yves Avenard on 17/06/2016.
//  Copyright © 2016 Mozilla. All rights reserved.
//

#ifndef VTDecoder_hpp
#define VTDecoder_hpp

#include <stdio.h>
#include "main.h"
#import "H264Data.h"
#import "VideoToolbox/VTDecompressionSession.h"

class H264Data;
class H264Sample;

class MyIOSurfaceRef {
public:
    MyIOSurfaceRef(IOSurfaceRef aSurface)
    : mSurface(aSurface)
    {
        CFRetain(aSurface);
        IOSurfaceIncrementUseCount(mSurface);
    }
    MyIOSurfaceRef()
    : mSurface(nullptr)
    {
    }
    MyIOSurfaceRef(MyIOSurfaceRef&& aOther)
    : mSurface(aOther.mSurface)
    {
        aOther.mSurface = nullptr;
    }
    ~MyIOSurfaceRef()
    {
        if (mSurface) {
            IOSurfaceDecrementUseCount(mSurface);
            CFRelease(mSurface);
        }
    }
    MyIOSurfaceRef& operator=(MyIOSurfaceRef&& aOther)
    {
        mSurface  = aOther.mSurface;
        aOther.mSurface = nullptr;
        return *this;
    }
    IOSurfaceRef GetSurface() const
    {
        return mSurface;
    }
    void Clear()
    {
        if (mSurface) {
            IOSurfaceDecrementUseCount(mSurface);
            CFRelease(mSurface);
            mSurface = nullptr;
        }
    }
private:
    IOSurfaceRef mSurface;
};

class VTDecoder {
public:
    VTDecoder(TestView* aView);
    ~VTDecoder();
    void Start();
    bool OutputFrame(CVPixelBufferRef aImage, H264Sample* aFrameRef);

private:
    TestView* mView;
    H264Data* mData;
    int32_t mPictureWidth;
    int32_t mPictureHeight;
    CMVideoFormatDescriptionRef mFormat;
    VTDecompressionSessionRef mSession;

    // Method to pass a frame to VideoToolbox for decoding.
    bool DoDecode(H264Sample* aSample);
    // Method to set up the decompression session.
    bool InitializeSession();
    bool WaitForAsynchronousFrames();
    CFDictionaryRef CreateOutputConfiguration();
    CFDictionaryRef CreateDecoderSpecification();
    CFDictionaryRef CreateDecoderExtensions();
    NSLock* mLock;
    MyIOSurfaceRef mSurfaces[NUM_SAMPLES];
    size_t mNumSurfaces;
    size_t mIndex;
};

#endif /* VTDecoder_hpp */
