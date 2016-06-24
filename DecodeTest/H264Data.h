//
//  H264Data.h
//  DecodeTest
//
//  Created by Jean-Yves Avenard on 24/06/2016.
//  Copyright © 2016 Mozilla. All rights reserved.
//

#ifndef H264Data_h
#define H264Data_h

#define NUM_SAMPLES 1422

struct H264Sample {
    size_t mSize;
    unsigned char* mData;
    int64_t mTime;
    int64_t mDuration;
};

class H264Data {
public:
    H264Data();
    ~H264Data();
    const H264Sample* InitData() const { return &mInitData; }
    H264Sample* NextSample();
    void Reset();
private:
    H264Sample mVideo[NUM_SAMPLES];
    H264Sample mInitData;
    size_t mIndex;
};



#endif /* H264Data_h */
