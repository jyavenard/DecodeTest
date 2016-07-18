//
//  VTDecoder.cpp
//  DecodeTest
//
//  Created by Jean-Yves Avenard on 17/06/2016.
//  Copyright © 2016 Mozilla. All rights reserved.
//

#import "VTDecoder.h"
#import "MemUtils.h"
#include <assert.h>
#include <OpenGL/gl.h>

#define DECODE_AHEAD 1

VTDecoder::VTDecoder(TestView* aView)
    : mView(aView)
    , mData(new H264Data)
    , mPictureWidth(1120)
    , mPictureHeight(626)
    , mInput(0)
    , mOutput(0)
    , mDrained(false)
{
    InitializeSession();
    mQueue = dispatch_queue_create("com.example.MyQueue", DISPATCH_QUEUE_SERIAL);
}

VTDecoder::~VTDecoder()
{
    delete mData;
    if (mSession) {
        //LOG("%s: cleaning up session %p", __func__, mSession);
        VTDecompressionSessionInvalidate(mSession);
        CFRelease(mSession);
        mSession = nullptr;
    }
    if (mFormat) {
        //LOG("%s: releasing format %p", __func__, mFormat);
        CFRelease(mFormat);
        mFormat = nullptr;
    }
}

// Callback passed to the VideoToolbox decoder for returning data.
// This needs to be static because the API takes a C-style pair of
// function and userdata pointers. This validates parameters and
// forwards the decoded image back to an object method.
static void
PlatformCallback(void* decompressionOutputRefCon,
                 void* sourceFrameRefCon,
                 OSStatus status,
                 VTDecodeInfoFlags flags,
                 CVImageBufferRef image,
                 CMTime presentationTimeStamp,
                 CMTime presentationDuration)
{
    VTDecoder* decoder =
    static_cast<VTDecoder*>(decompressionOutputRefCon);

    // Validate our arguments.
    if (status != noErr || !image) {
        NSLog(@"VideoToolbox decoder returned no data");
        image = nullptr;
    } else if (flags & kVTDecodeInfo_FrameDropped) {
        NSLog(@"  ...frame tagged as dropped...");
    } else {
        assert(CFGetTypeID(image) == CVPixelBufferGetTypeID()); //, "VideoToolbox returned an unexpected image type");
    }

    if (image) {
        CFRetain(image);
    }
    dispatch_async(decoder->mQueue, ^{
        decoder->OutputFrame(image);
        if (image) {
            CFRelease(image);
        }
    });
}

void
VTDecoder::OutputFrame(CVPixelBufferRef aImage)
{
    if (!aImage) {
        // Image was dropped by decoder.
        return;
    }

    auto surface = CVPixelBufferGetIOSurface(aImage);
    assert(surface); // "Decoder didn't return an IOSurface backed buffer");

    NSLog(@"Returning frame %u for display", (unsigned int)++mOutput);
    MyIOSurfaceRef ref(surface);
    [mView output:&ref];
}

bool
VTDecoder::InitializeSession()
{
    OSStatus rv;

    AutoCFRelease<CFDictionaryRef> extensions = CreateDecoderExtensions();

    rv = CMVideoFormatDescriptionCreate(kCFAllocatorDefault,
                                        kCMVideoCodecType_H264,
                                        mPictureWidth,
                                        mPictureHeight,
                                        extensions,
                                        &mFormat);
    if (rv != noErr) {
        NSLog(@"Couldn't create format description!");
        return false;
    }

    // Contruct video decoder selection spec.
    AutoCFRelease<CFDictionaryRef> spec = CreateDecoderSpecification();

    // Contruct output configuration.
    AutoCFRelease<CFDictionaryRef> outputConfiguration =
        CreateOutputConfiguration();

    VTDecompressionOutputCallbackRecord cb = { PlatformCallback, this };
    rv = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                      mFormat,
                                      spec, // Video decoder selection.
                                      outputConfiguration, // Output video format.
                                      &cb,
                                      &mSession);

    if (rv != noErr) {
        NSLog(@"Couldn't create decompression session!");
        return false;
    }

    return true;
}

CFDictionaryRef
VTDecoder::CreateOutputConfiguration()
{
  // Output format type:
  SInt32 PixelFormatTypeValue = kCVPixelFormatType_422YpCbCr8;
  AutoCFRelease<CFNumberRef> PixelFormatTypeNumber =
    CFNumberCreate(kCFAllocatorDefault,
                   kCFNumberSInt32Type,
                   &PixelFormatTypeValue);
  // Construct IOSurface Properties
  const void* IOSurfaceKeys[] = { kIOSurfaceIsGlobal };
  const void* IOSurfaceValues[] = { kCFBooleanTrue };

  // Contruct output configuration.
  AutoCFRelease<CFDictionaryRef> IOSurfaceProperties =
    CFDictionaryCreate(kCFAllocatorDefault,
                       IOSurfaceKeys,
                       IOSurfaceValues,
                       ArrayLength(IOSurfaceKeys),
                       &kCFTypeDictionaryKeyCallBacks,
                       &kCFTypeDictionaryValueCallBacks);

  const void* outputKeys[] = { kCVPixelBufferIOSurfacePropertiesKey,
                               kCVPixelBufferPixelFormatTypeKey,
                               kCVPixelBufferOpenGLCompatibilityKey };
  const void* outputValues[] = { IOSurfaceProperties,
                                 PixelFormatTypeNumber,
                                 kCFBooleanTrue };

  return CFDictionaryCreate(kCFAllocatorDefault,
                            outputKeys,
                            outputValues,
                            ArrayLength(outputKeys),
                            &kCFTypeDictionaryKeyCallBacks,
                            &kCFTypeDictionaryValueCallBacks);
}

CFDictionaryRef
VTDecoder::CreateDecoderExtensions()
{
    AutoCFRelease<CFDataRef> avc_data = CFDataCreate(kCFAllocatorDefault,
                                                     mData->InitData()->mData,
                                                     (CFIndex)mData->InitData()->mSize);

    const void* atomsKey[] = { CFSTR("avcC") };
    const void* atomsValue[] = { avc_data };

    AutoCFRelease<CFDictionaryRef> atoms =
        CFDictionaryCreate(kCFAllocatorDefault,
                           atomsKey,
                           atomsValue,
                           ArrayLength(atomsKey),
                           &kCFTypeDictionaryKeyCallBacks,
                           &kCFTypeDictionaryValueCallBacks);

    const void* extensionKeys[] =
        { kCVImageBufferChromaLocationBottomFieldKey,
          kCVImageBufferChromaLocationTopFieldKey,
          kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms };

    const void* extensionValues[] =
        { kCVImageBufferChromaLocation_Left,
          kCVImageBufferChromaLocation_Left,
          atoms };

    return CFDictionaryCreate(kCFAllocatorDefault,
                              extensionKeys,
                              extensionValues,
                              ArrayLength(extensionKeys),
                              &kCFTypeDictionaryKeyCallBacks,
                              &kCFTypeDictionaryValueCallBacks);
}

CFDictionaryRef
VTDecoder::CreateDecoderSpecification()
{
    const void* specKeys[] = { kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder };
    const void* specValues[] = { kCFBooleanTrue };

    return CFDictionaryCreate(kCFAllocatorDefault,
                              specKeys,
                              specValues,
                              ArrayLength(specKeys),
                              &kCFTypeDictionaryKeyCallBacks,
                              &kCFTypeDictionaryValueCallBacks);
}

void
VTDecoder::Drain()
{
    VTDecompressionSessionWaitForAsynchronousFrames(mSession);
}

// Helper to fill in a timestamp structure.

// Number of microseconds per second. 1e6.
static const int64_t USECS_PER_S = 1000000;

static CMSampleTimingInfo
TimingInfoFromSample(H264Sample* aSample)
{
  CMSampleTimingInfo timestamp;

  timestamp.duration = CMTimeMake(aSample->mDuration, USECS_PER_S);
  timestamp.presentationTimeStamp = CMTimeMake(aSample->mTime, USECS_PER_S);
  timestamp.decodeTimeStamp = CMTimeMake(aSample->mTime, USECS_PER_S);

  return timestamp;
}

bool
VTDecoder::DoDecode(H264Sample* aSample)
{
    // For some reason this gives me a double-free error with stagefright.
    AutoCFRelease<CMBlockBufferRef> block = nullptr;
    AutoCFRelease<CMSampleBufferRef> sample = nullptr;
    VTDecodeInfoFlags infoFlags;
    OSStatus rv;

    rv = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, // Struct allocator.
                                            const_cast<uint8_t*>(aSample->mData),
                                            aSample->mSize,
                                            kCFAllocatorNull, // Block allocator.
                                            NULL, // Block source.
                                            0,    // Data offset.
                                            aSample->mSize,
                                            false,
                                            block.receive());
    if (rv != noErr) {
        NSLog(@"Couldn't create CMBlockBuffer");
        return false;
    }
    CMSampleTimingInfo timestamp = TimingInfoFromSample(aSample);
    rv = CMSampleBufferCreate(kCFAllocatorDefault, block, true, 0, 0, mFormat, 1, 1, &timestamp, 0, NULL, sample.receive());
    if (rv != noErr) {
        NSLog(@"Couldn't create CMSampleBuffer");
        return false;
    }

    VTDecodeFrameFlags decodeFlags =
        kVTDecodeFrame_EnableAsynchronousDecompression;
    rv = VTDecompressionSessionDecodeFrame(mSession,
                                           sample,
                                           decodeFlags,
                                           aSample,
                                           &infoFlags);
    if (rv != noErr && !(infoFlags & kVTDecodeInfo_FrameDropped)) {
        NSLog(@"AppleVTDecoder: Error %d VTDecompressionSessionDecodeFrame", rv);
        NSLog(@"Couldn't pass frame to decoder");
        return false;
    }

    return true;
}

void
VTDecoder::DecodeNextFrame()
{
    H264Sample* sample = mData->NextSample();
    if (!sample) {
        if (!mDrained) {
            NSLog(@"No more data, draining decoder");
            Drain();
            mDrained = true;
        }
        return;
    }
    NSLog(@"Starting decoding of frame %u", (unsigned int)++mInput);
    DoDecode(sample);
    if (mInput - mOutput < DECODE_AHEAD) {
        NotifyFrameNeeded();
    }
}

void
VTDecoder::NotifyFrameNeeded()
{
    dispatch_async(mQueue, ^{
        DecodeNextFrame();
    });
}
