//
//  H264Data.mm
//  DecodeTest
//
//  Created by Jean-Yves Avenard on 24/06/2016.
//  Copyright © 2016 Mozilla. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "H264Data.h"
#import "MemUtils.h"

H264Data::H264Data()
    : mIndex(0)
{
    // Get the main bundle for the app
    CFBundleRef mainBundle = CFBundleGetMainBundle();

    for (int i = 0; i < NUM_SAMPLES + 1; i++) {
        NSString* nsStr = [NSString stringWithFormat:@"t%04d", i];

        // Get the URL to the sound file to play.
        AutoCFRelease<CFURLRef> dataFileURLRef = CFBundleCopyResourceURL(mainBundle, (CFStringRef)nsStr, CFSTR("bin"), NULL);
        NSData* h264Data = [[NSData alloc] initWithContentsOfURL:(__bridge NSURL*)(CFURLRef)dataFileURLRef];

        size_t size = [h264Data length];
        const void* data = [h264Data bytes];

        if (i == 0) {
            mInitData.mSize = size;
            mInitData.mData = new unsigned char[size];
            memcpy(mInitData.mData, data, size);
        } else {
            mVideo[i-1].mSize = size;
            mVideo[i-1].mData = new unsigned char[size];
            memcpy(mVideo[i-1].mData, data, size);
            mVideo[i-1].mTime = (i-1) * 16666LL;
            mVideo[i-1].mDuration = 16666LL;
        }
    }
}

H264Data::~H264Data()
{
    for (int i = 0; i < NUM_SAMPLES + 1; i++) {
        if (i == 0) {
            delete[] mInitData.mData;
        } else {
            delete[] mVideo[i-1].mData;
        }
    }
}

H264Sample*
H264Data::NextSample()
{
    if (mIndex >= NUM_SAMPLES) {
        return nullptr;
    }
    return &mVideo[mIndex++];
}

void
H264Data::Reset()
{
    mIndex = 0;
}
