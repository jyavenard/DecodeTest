//
//  MemUtil.h
//  DecodeTest
//
//  Created by Jean-Yves Avenard on 24/06/2016.
//  Copyright © 2016 Mozilla. All rights reserved.
//

#ifndef MemUtil_h
#define MemUtil_h

// Wrapper class to call CFRelease on reference types
// when they go out of scope.
template <class T>
class AutoCFRelease {
public:
    AutoCFRelease(T aRef)
    : mRef(aRef)
    {
    }
    ~AutoCFRelease()
    {
        if (mRef) {
            CFRelease(mRef);
        }
    }
    // Return the wrapped ref so it can be used as an in parameter.
    operator T()
    {
        return mRef;
    }
    // Return a pointer to the wrapped ref for use as an out parameter.
    T* receive()
    {
        return &mRef;
    }

private:
    // Copy operator isn't supported and is not implemented.
    AutoCFRelease<T>& operator=(const AutoCFRelease<T>&);
    T mRef;
};

// CFRefPtr: A CoreFoundation smart pointer.
template <class T>
class CFRefPtr {
public:
    explicit CFRefPtr(T aRef)
    : mRef(aRef)
    {
        if (mRef) {
            CFRetain(mRef);
        }
    }
    // Copy constructor.
    CFRefPtr(const CFRefPtr<T>& aCFRefPtr)
    : mRef(aCFRefPtr.mRef)
    {
        if (mRef) {
            CFRetain(mRef);
        }
    }
    // Copy operator
    CFRefPtr<T>& operator=(const CFRefPtr<T>& aCFRefPtr)
    {
        if (mRef == aCFRefPtr.mRef) {
            return;
        }
        if (mRef) {
            CFRelease(mRef);
        }
        mRef = aCFRefPtr.mRef;
        if (mRef) {
            CFRetain(mRef);
        }
        return *this;
    }
    ~CFRefPtr()
    {
        if (mRef) {
            CFRelease(mRef);
        }
    }
    // Return the wrapped ref so it can be used as an in parameter.
    operator T()
    {
        return mRef;
    }
    
private:
    T mRef;
};

/*
 * Compute the length of an array with constant length.  (Use of this method
 * with a non-array pointer will not compile.)
 *
 * Beware of the implicit trailing '\0' when using this with string constants.
 */
template<typename T, size_t N>
size_t
ArrayLength(T (&aArr)[N])
{
  return N;
}

#endif /* MemUtil_h */
